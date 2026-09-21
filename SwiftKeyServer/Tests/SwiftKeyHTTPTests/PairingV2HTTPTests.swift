import Foundation
import Vapor
import VaporTesting
import SwiftKeyAuthority
import SwiftKeyCore
import Testing
@testable import SwiftKeyHTTP

private struct V2HTTPVerifier: EnrollmentVerifier {
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        throw ProtocolError.invalidPublicKey // This route suite never supplies hardware trust.
    }
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws { throw ProtocolError.invalidPublicKey }
}
private struct V2HTTPFixture {
    let directory: URL
    let authority: Authority
    let admin = String(repeating: "isolated-http-admin-", count: 3)
    let bootstrap = String(repeating: "isolated-http-bootstrap-", count: 3)
    init(enabled: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-v2-http-" + UUID().uuidString)
        authority = try Authority(configuration: .init(stateDirectory: directory.path, androidPackage: "v2.http.test",
            androidSigningCertificateSHA256: String(repeating: "00", count: 32),
            pairingV2: enabled ? .init(origin: "https://authority.example") : nil),
            bootstrapToken: bootstrap, verifier: V2HTTPVerifier(), clock: { 1_800_000_100 })
    }
    func test(_ run: (Application) async throws -> Void) async throws {
        try await withHTTPApplication(authority: authority, adminToken: admin, bootstrapToken: bootstrap,
            console: .init(indexHTML: Data(), script: Data(), stylesheet: Data()), run)
    }
}
private func v2HTTPCode(_ response: TestingHTTPResponse) throws -> String {
    try JSONDecoder().decode(AuthorityErrorResponse.self, from: Data(response.body.readableBytesView)).code
}
private func v2HTTPPrepare() -> String {
    "{\"requestID\":\"\(UUID().uuidString.lowercased())\",\"rootKind\":\"android-strongbox-p256\"}"
}

@Test func v2HTTPAdmissionReturnsPinnedSignedPublicContextAndNoAccount() async throws {
    let fixture = try V2HTTPFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let pin = await fixture.authority.publicKey
    try await fixture.test { client in
        let response = try await client.execute(uri: "/v2/identities/prepare", method: .POST, body: ByteBuffer(string: v2HTTPPrepare()))
        #expect(response.status == .ok)
        #expect(response.headers.first(name: "Cache-Control") == "no-store")
        #expect(response.headers.first(name: "Access-Control-Allow-Origin") == nil)
        let prepared = try PairingV2JSON.decode(PairingV2.PreparationResponse.self, from: Data(response.body.readableBytesView))
        try prepared.challenge.verify(authorityPublicKey: pin)
        #expect(prepared.challenge.payload.authorityID == ProtocolCrypto.sha256(pin))
        #expect(prepared.challenge.payload.origin == "https://authority.example")
        #expect(prepared.challenge.payload.audience == PairingV2.audience)
        #expect(prepared.preparationCapability.count == 32)
        let account = try await client.execute(uri: "/v1/admin/accounts", method: .POST,
            headers: ["Authorization": "Bearer " + fixture.admin], body: ByteBuffer(string: "{\"label\":\"Bypass\"}"))
        #expect(account.status != .created && account.status != .ok)
        #expect(try await fixture.authority.listAccounts().accounts.isEmpty)
    }
}

@Test func v2HTTPRejectsAmbiguousOversizedAndUnsupportedInputsBeforeAdmission() async throws {
    let fixture = try V2HTTPFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let valid = v2HTTPPrepare()
        let duplicate = valid.dropLast() + ",\"requestID\":\"00000000-0000-4000-8000-000000000001\"}"
        let escaped = valid.dropLast() + ",\"r\\u0065questID\":\"00000000-0000-4000-8000-000000000001\"}"
        let unknown = valid.dropLast() + ",\"adminOverride\":true}"
        for body in [String(duplicate), String(escaped), String(unknown), "{}", "[]", valid.replacingOccurrences(of: "android-strongbox-p256", with: "software-p256")] {
            let response = try await client.execute(uri: "/v2/identities/prepare", method: .POST, body: ByteBuffer(string: body))
            #expect(response.status == .badRequest)
            #expect(try v2HTTPCode(response) == "invalidRequest")
        }
        let tooLarge = try await client.execute(uri: "/v2/operations", method: .POST,
            body: ByteBuffer(string: "{\"payload\":\"" + String(repeating: "x", count: 750_001) + "\"}"))
        #expect(tooLarge.status.code >= 400)
        let roster = try await client.execute(uri: "/v2/accounts/roster", method: .POST,
            body: ByteBuffer(string: "{\"accountID\":\"00000000-0000-4000-8000-000000000001\"}"))
        #expect(roster.status == .forbidden)
        #expect(try v2HTTPCode(roster) == "unauthorized")
    }
}

@Test func v2HTTPAdmissionBudgetCannotBeResetByForwardedHeadersOrNewRequestIDs() async throws {
    let fixture = try V2HTTPFixture(); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        for number in 0..<9 {
            let response = try await client.execute(uri: "/v2/identities/prepare", method: .POST,
                headers: ["X-Forwarded-For": "192.0.2.\(number)"], body: ByteBuffer(string: v2HTTPPrepare()))
            #expect(response.status == (number < 8 ? .ok : .tooManyRequests))
            if number == 8 { #expect(try v2HTTPCode(response) == "rateLimited") }
        }
    }
}

@Test func v2HTTPRequiresExplicitAuthorityOptIn() async throws {
    let fixture = try V2HTTPFixture(enabled: false); defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let response = try await client.execute(uri: "/v2/identities/prepare", method: .POST, body: ByteBuffer(string: v2HTTPPrepare()))
        #expect(response.status.code >= 400)
        #expect(try v2HTTPCode(response) == "v2Unavailable")
    }
}

@Test func vaporV2PrecollectedAndSocketBodiesKeepExactLimitAndSignedDispatch() async throws {
    for live in [false, true] {
        let fixture = try V2HTTPFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let pin = await fixture.authority.publicKey
        try await fixture.test { app in
            let client = try app.testing(method: live ? .running(hostname: "127.0.0.1", port: 0) : .inMemory)
            let exact = try await client.sendRequest(.POST, "/v2/identities/prepare",
                body: paddedHTTPBody(v2HTTPPrepare(), count: 750_000))
            #expect(exact.status == .ok, "Transport live=\(live)")
            let admitted = try PairingV2JSON.decode(PairingV2.PreparationResponse.self, from: Data(exact.body.readableBytesView))
            try admitted.challenge.verify(authorityPublicKey: pin)
            let excess = try await client.sendRequest(.POST, "/v2/identities/prepare",
                body: paddedHTTPBody(v2HTTPPrepare(), count: 750_001))
            #expect(excess.status == .payloadTooLarge, "Transport live=\(live)")
            #expect(try v2HTTPCode(excess) == "invalidRequest")
            #expect(excess.headers.first(name: "Cache-Control") == "no-store")
            #expect(excess.headers.first(name: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
            #expect(excess.headers.first(name: "X-Content-Type-Options") == "nosniff")
            #expect(excess.headers.first(name: "Access-Control-Allow-Origin") == nil)
            let unknown = try await client.sendRequest(.POST, "/v1/admin/unknown-route", body: ByteBuffer(string: "invalid JSON"))
            #expect(unknown.status == .forbidden)
            #expect(try v2HTTPCode(unknown) == "unauthorized")
        }
    }
}

@Test func vaporV2AdmissionThrottleRunsBeforeMalformedBodyDecoding() async throws {
    let fixture = try V2HTTPFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { app in
        for attempt in 0..<17 {
            let response = try await app.execute(uri: "/v2/identities/attest", method: .POST,
                headers: ["X-Forwarded-For": "192.0.2.\(attempt)", "Forwarded": "for=192.0.2.\(attempt)"],
                body: ByteBuffer(string: "not JSON"))
            #expect(response.status == (attempt < 16 ? .badRequest : .tooManyRequests))
            #expect(try v2HTTPCode(response) == (attempt < 16 ? "invalidRequest" : "rateLimited"))
            #expect(response.headers.first(name: "Cache-Control") == "no-store")
        }
    }
}
