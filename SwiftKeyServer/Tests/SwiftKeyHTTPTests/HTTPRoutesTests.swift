import Foundation
import Vapor
import VaporTesting
import SwiftKeyAuthority
import SwiftKeyCore
import Testing
@testable import SwiftKeyHTTP

/// Fake attestation is restricted to this test target. The executable always
/// constructs AndroidAttestationVerifier, including when serving these routes.
private struct HTTPFixtureVerifier: EnrollmentVerifier {
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        guard certificates.count == 1, let key = certificates.first else { throw ProtocolError.invalidPublicKey }
        try ProtocolCrypto.validatePublicKey(key)
        return VerifiedAndroidIdentity(publicKey: key, certificateSHA256: ProtocolCrypto.sha256(key),
            packageName: "http-test.fixture", packageVersion: 1)
    }
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws {}
}

private struct HTTPFixture {
    let authority: Authority
    let directory: URL
    let adminToken = String(repeating: "admin-only-test-secret-", count: 3)
    let bootstrapToken = String(repeating: "bootstrap-only-test-secret-", count: 3)
    let now: UInt64 = 1_800_000_100
    let console = ConsoleAssets(indexHTML: Data("<!doctype html><script src='/app.js'></script>".utf8),
        script: Data("console.log('static test asset');".utf8), stylesheet: Data("body { color: black; }".utf8))

    static func make() throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-http-test-" + UUID().uuidString)
        let configuration = ServerConfiguration(stateDirectory: directory.path, androidPackage: "http-test.fixture",
            androidSigningCertificateSHA256: String(repeating: "00", count: 32))
        let authority = try Authority(configuration: configuration,
            bootstrapToken: String(repeating: "bootstrap-only-test-secret-", count: 3),
            verifier: HTTPFixtureVerifier(), clock: { 1_800_000_100 })
        return Self(authority: authority, directory: directory)
    }

    var headers: HTTPHeaders { ["Authorization": "Bearer " + adminToken] }
    func test(console: ConsoleAssets? = nil, adminToken: String? = nil,
              _ run: (Application) async throws -> Void) async throws {
        try await withHTTPApplication(authority: authority, adminToken: adminToken ?? self.adminToken,
            bootstrapToken: bootstrapToken, console: console ?? self.console, run)
    }
}

private func body<T: Encodable>(_ value: T) throws -> ByteBuffer { ByteBuffer(bytes: try JSONEncoder().encode(value)) }
private func decode<T: Decodable>(_ type: T.Type, _ response: TestingHTTPResponse) throws -> T {
    try JSONDecoder().decode(type, from: Data(response.body.readableBytesView))
}

@Test func adminRoutesRejectMissingWrongAndBootstrapBearersBeforeBodyOrLookup() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let paths = ["/v1/admin/accounts", "/v1/admin/accounts/unknown", "/v1/admin/accounts/unknown/devices",
                     "/v1/admin/accounts/unknown/epochs", "/v1/admin/ledger?limit=bad", "/v1/admin/status",
                     "/v1/admin", "/v1/admin/unknown-route"]
        for token in [nil, "wrong-test-token", fixture.bootstrapToken] {
            let headers: HTTPHeaders = token.map { ["Authorization": "Bearer " + $0] } ?? [:]
            for path in paths {
                let response = try await client.execute(uri: path, method: .GET, headers: headers)
                #expect(response.status == .forbidden)
                #expect(try decode(AuthorityErrorResponse.self, response).code == "unauthorized")
                #expect(response.headers.first(name: "Cache-Control") == "no-store")
            }
            let response = try await client.execute(uri: "/v1/admin/accounts", method: .POST,
                headers: headers, body: ByteBuffer(string: "not JSON"))
            #expect(response.status == .forbidden)
            let invitation = try await client.execute(uri: "/v1/admin/accounts/unknown/enrollment-invitation",
                method: .POST, headers: headers)
            #expect(invitation.status == .forbidden)
            #expect(try decode(AuthorityErrorResponse.self, invitation).code == "unauthorized")
        }
        let queryToken = try await client.execute(uri: "/v1/admin/accounts?token=" + fixture.adminToken, method: .GET)
        #expect(queryToken.status == .forbidden)
        var repeated = fixture.headers
        repeated.add(name: "Authorization", value: "Bearer " + fixture.bootstrapToken)
        let ambiguous = try await client.execute(uri: "/v1/admin/status", method: .GET, headers: repeated)
        #expect(ambiguous.status == .forbidden)
        let modified = try await client.execute(uri: "/v1/admin/status", method: .GET,
            headers: ["Authorization": "Bearer " + fixture.adminToken.dropLast() + "x"])
        #expect(modified.status == .forbidden)
        let wrongMethod = try await client.execute(uri: "/v1/admin/accounts", method: .DELETE)
        #expect(wrongMethod.status == .forbidden)
        let authenticatedUnknown = try await client.execute(uri: "/v1/admin/unknown-route", method: .GET, headers: fixture.headers)
        #expect(authenticatedUnknown.status == .notFound)
    }
    await #expect(throws: (any Error).self) {
        try await fixture.test(adminToken: fixture.bootstrapToken) { _ in }
    }
}

@Test func adminPagingRejectsMalformedDuplicateAndOutOfRangeValues() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        for query in ["after=-1", "after=18446744073709551616", "after=18446744073709551615", "after=1.0", "after=",
                      "limit=0", "limit=201", "limit=-1", "limit=1.5", "limit=1&limit=2",
                      "accountID=", "after=%ZZ", "unknown=1", "after=0&", "accountID=a%2Fb"] {
            let response = try await client.execute(uri: "/v1/admin/ledger?" + query, method: .GET, headers: fixture.headers)
            #expect(response.status == .badRequest, "query: \(query)")
            #expect(try decode(AuthorityErrorResponse.self, response).code == "invalidRequest")
        }
        let good = try await client.execute(uri: "/v1/admin/ledger?after=0&limit=1", method: .GET, headers: fixture.headers)
        #expect(good.status == .ok)
        #expect(try decode(LedgerPage.self, good).events.count <= 1)
        for path in ["/v1/admin/accounts/missing", "/v1/admin/accounts/missing/devices", "/v1/admin/accounts/missing/epochs"] {
            let unknown = try await client.execute(uri: path, method: .GET, headers: fixture.headers)
            #expect(unknown.status == .notFound)
            #expect(try decode(AuthorityErrorResponse.self, unknown).code == "notFound")
        }
    }
}

@Test func consoleAndErrorsAreNoncacheableWithScopedCSPAndNoCORSGrant() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        for path in ["/", "/app.js", "/style.css", "/health", "/v1/time", "/missing", "/v1/admin/status"] {
            let response = try await client.execute(uri: path, method: .GET,
                headers: ["Origin": "https://untrusted.invalid"])
            #expect(response.headers.first(name: "Cache-Control") == "no-store")
            #expect(response.headers.first(name: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
            #expect(response.headers.first(name: "Content-Security-Policy")?.contains("font-src 'self'") == true)
            #expect(response.headers.first(name: "Content-Security-Policy")?.contains("'unsafe-inline'") == false)
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff")
            #expect(response.headers.first(name: "Access-Control-Allow-Origin") == nil)
            let text = String(buffer: response.body)
            #expect(!text.contains(fixture.adminToken) && !text.contains(fixture.bootstrapToken))
            if path == "/missing" { #expect(response.status == .notFound) }
        }
        let preflight = try await client.execute(uri: "/v1/admin/accounts", method: .OPTIONS,
            headers: ["Origin": "https://untrusted.invalid",
                      "Access-Control-Request-Headers": "authorization"])
        #expect(preflight.headers.first(name: "Access-Control-Allow-Origin") == nil)
        #expect(preflight.status != .ok)
    }
}

@Test func selfHostedFontsUseExactWhitelistAndPreserveBinaryContent() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let font = Data([0x77, 0x4f, 0x46, 0x32, 0x00, 0xff, 0x80])
    let console = ConsoleAssets(indexHTML: fixture.console.indexHTML, script: fixture.console.script,
        stylesheet: fixture.console.stylesheet,
        fonts: ["host-grotesk.woff2": font, "jetbrains-mono.woff2": font, "unlisted.woff2": font])
    try await fixture.test(console: console) { client in
        for name in ["host-grotesk.woff2", "jetbrains-mono.woff2"] {
            let response = try await client.execute(uri: "/fonts/" + name, method: .GET)
            #expect(response.status == .ok)
            #expect(response.headers.first(name: "Content-Type") == "font/woff2")
            #expect(Data(response.body.readableBytesView) == font)
            #expect(response.headers.first(name: "Content-Security-Policy")?.contains("font-src 'self'") == true)
            #expect(response.headers.first(name: "Cross-Origin-Resource-Policy") == "same-origin")
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff")
        }
        for path in ["/fonts/unlisted.woff2", "/fonts/authority.json", "/fonts/host-grotesk.ttf", "/fonts/space-grotesk.woff2", "/fonts/ibm-plex-mono.woff2"] {
            #expect(try await client.execute(uri: path, method: .GET).status == .notFound)
        }
    }
    // Existing callers may omit optional assets, in which case routes are absent.
    try await fixture.test { client in
        let response = try await client.execute(uri: "/fonts/host-grotesk.woff2", method: .GET)
        #expect(response.status == .notFound)
    }
}

@Test func accountProvisioningWorksThroughExistingMobileRoutesWithoutLeakingSecrets() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let create = try await client.execute(uri: "/v1/admin/accounts", method: .POST, headers: fixture.headers,
            body: body(CreateAccountRequest(label: "HTTP test account")))
        #expect(create.status == .created)
        let provisioned = try decode(CreateAccountResponse.self, create)
        #expect(provisioned.enrollmentToken != fixture.bootstrapToken && provisioned.enrollmentToken != fixture.adminToken)
        let mobileHeaders: HTTPHeaders = ["Authorization": "Bearer " + provisioned.enrollmentToken]
        let denied = try await client.execute(uri: "/v1/admin/status", method: .GET, headers: mobileHeaders)
        #expect(denied.status == .forbidden)

        let challengeResponse = try await client.execute(uri: "/v1/bootstrap/challenge", method: .POST,
            headers: mobileHeaders, body: ByteBuffer(string: "{}"))
        #expect(challengeResponse.status == .ok)
        let bootstrap = try decode(BootstrapChallengeResponse.self, challengeResponse)
        #expect(bootstrap.challenge.accountID == provisioned.account.accountID)
        let root = SoftwareSigningKey()
        let enrollmentRequest = EnrollRequest(challenge: bootstrap.challenge, certificates: [root.publicKey],
            proof: try root.sign(message: bootstrap.challenge.canonicalBytes()))
        let enrolledResponse = try await client.execute(uri: "/v1/bootstrap/enroll", method: .POST,
            headers: mobileHeaders, body: body(enrollmentRequest))
        #expect(enrolledResponse.status == .ok)
        let enrolled = try decode(EnrollResponse.self, enrolledResponse)
        #expect(enrolled.accountID == provisioned.account.accountID && enrolled.publicKey == root.publicKey)

        let leaf = SoftwareSigningKey()
        let delegation = EpochDelegation(accountID: enrolled.accountID, deviceID: enrolled.deviceID,
            epoch: Epoch.number(at: fixture.now), publicKey: leaf.publicKey)
        let operationResponse = try await client.execute(uri: "/v1/challenges", method: .POST,
            body: body(ChallengeRequest(accountID: enrolled.accountID, deviceID: enrolled.deviceID,
                operation: .issueEpoch, payloadHash: ProtocolCrypto.sha256(try delegation.canonicalBytes()))))
        #expect(operationResponse.status == .ok)
        let challenge = try decode(ChallengeEnvelope.self, operationResponse)
        let auth = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge,
            signature: try root.sign(message: challenge.canonicalBytes()))
        let issuedResponse = try await client.execute(uri: "/v1/epochs", method: .POST,
            body: body(IssueEpochRequest(delegation: delegation, authorization: auth)))
        #expect(issuedResponse.status == .ok)
        let credential = try decode(EpochCredential.self, issuedResponse)
        let message = WorkloadMessage(domain: "swiftkey.demo.echo.v1", audience: "swiftkey.local",
            accountID: enrolled.accountID, deviceID: enrolled.deviceID, epoch: delegation.epoch,
            nonce: ProtocolCrypto.randomNonce(), payload: Data("private workload body".utf8))
        let workload = VerifyWorkloadRequest(credential: credential,
            workload: SignedWorkload(message: message, signature: try leaf.sign(message: message.canonicalBytes())))
        let accepted = try await client.execute(uri: "/v1/workloads", method: .POST, body: body(workload))
        #expect(accepted.status == .ok)
        let replay = try await client.execute(uri: "/v1/workloads", method: .POST, body: body(workload))
        #expect(replay.status == .conflict)
        #expect(try decode(AuthorityErrorResponse.self, replay).code == "replayedWorkload")

        for path in ["/v1/admin/accounts", "/v1/admin/accounts/\(enrolled.accountID)",
                     "/v1/admin/accounts/\(enrolled.accountID)/devices", "/v1/admin/accounts/\(enrolled.accountID)/epochs",
                     "/v1/admin/ledger?accountID=\(enrolled.accountID)&limit=200", "/v1/admin/status"] {
            let response = try await client.execute(uri: path, method: .GET, headers: fixture.headers)
            #expect(response.status == .ok)
            let text = String(buffer: response.body)
            for secret in [fixture.adminToken, fixture.bootstrapToken, provisioned.enrollmentToken,
                           root.rawRepresentation.base64EncodedString(), leaf.rawRepresentation.base64EncodedString(),
                           message.payload.base64EncodedString(), "bootstrapTokenHash", "signingKey", "privateKey", "enrollmentToken"] {
                #expect(!text.contains(secret), "Sensitive data appeared in \(path)")
            }
        }
        let badAccount = try await client.execute(uri: "/v1/admin/accounts", method: .POST,
            headers: fixture.headers, body: ByteBuffer(string: "{\"label\":7}"))
        #expect(badAccount.status == .badRequest)
    }
}

@Test func enrollmentInvitationCanBeReissuedOnlyBeforeFirstDeviceEnrollment() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let original = try await fixture.authority.createAccount(CreateAccountRequest(label: "Invitation recovery test"))
    let initialBootstrap = try await fixture.authority.bootstrapChallenge(token: fixture.bootstrapToken)
    try await fixture.test { client in
        let missing = try await client.execute(uri: "/v1/admin/accounts/unknown/enrollment-invitation",
            method: .POST, headers: fixture.headers)
        #expect(missing.status == .notFound)
        #expect(try decode(AuthorityErrorResponse.self, missing).code == "notFound")
        let initialAccount = try await client.execute(
            uri: "/v1/admin/accounts/\(initialBootstrap.challenge.accountID)/enrollment-invitation",
            method: .POST, headers: fixture.headers)
        #expect(initialAccount.status == .forbidden)
        #expect(try decode(AuthorityErrorResponse.self, initialAccount).code == "accountNotPending")

        let path = "/v1/admin/accounts/\(original.account.accountID)/enrollment-invitation"
        for token in [nil, "wrong-test-token", fixture.bootstrapToken] {
            let headers: HTTPHeaders = token.map { ["Authorization": "Bearer " + $0] } ?? [:]
            let denied = try await client.execute(uri: path, method: .POST, headers: headers)
            #expect(denied.status == .forbidden)
            #expect(try decode(AuthorityErrorResponse.self, denied).code == "unauthorized")
        }
        let renewedResponse = try await client.execute(uri: path, method: .POST, headers: fixture.headers)
        #expect(renewedResponse.status == .ok)
        #expect(renewedResponse.headers.first(name: "Cache-Control") == "no-store")
        let renewed = try decode(CreateAccountResponse.self, renewedResponse)
        #expect(renewed.account.accountID == original.account.accountID)
        #expect(renewed.account.status == "pending" && renewed.account.deviceCount == 0)
        #expect(renewed.enrollmentToken != original.enrollmentToken)
        #expect(renewed.expiresAt == fixture.now + 900)
        for publicPath in ["/v1/admin/accounts/\(original.account.accountID)",
                           "/v1/admin/ledger?accountID=\(original.account.accountID)"] {
            let view = try await client.execute(uri: publicPath, method: .GET, headers: fixture.headers)
            #expect(view.status == .ok)
            let text = String(buffer: view.body)
            #expect(!text.contains(original.enrollmentToken) && !text.contains(renewed.enrollmentToken))
        }

        let oldToken = try await client.execute(uri: "/v1/bootstrap/challenge", method: .POST,
            headers: ["Authorization": "Bearer " + original.enrollmentToken], body: ByteBuffer(string: "{}"))
        #expect(oldToken.status == .forbidden)
        #expect(try decode(AuthorityErrorResponse.self, oldToken).code == "unauthorized")
        let mobileHeaders: HTTPHeaders = ["Authorization": "Bearer " + renewed.enrollmentToken]
        let mobileCannotReissue = try await client.execute(uri: path, method: .POST, headers: mobileHeaders)
        #expect(mobileCannotReissue.status == .forbidden)
        #expect(try decode(AuthorityErrorResponse.self, mobileCannotReissue).code == "unauthorized")
        let challengeResponse = try await client.execute(uri: "/v1/bootstrap/challenge", method: .POST,
            headers: mobileHeaders, body: ByteBuffer(string: "{}"))
        #expect(challengeResponse.status == .ok)
        let challenge = try decode(BootstrapChallengeResponse.self, challengeResponse).challenge
        let root = SoftwareSigningKey()
        let enrollment = EnrollRequest(challenge: challenge, certificates: [root.publicKey],
            proof: try root.sign(message: challenge.canonicalBytes()))
        let enrolled = try await client.execute(uri: "/v1/bootstrap/enroll", method: .POST,
            headers: mobileHeaders, body: body(enrollment))
        #expect(enrolled.status == .ok)

        let activeAccount = try await client.execute(uri: path, method: .POST, headers: fixture.headers)
        #expect(activeAccount.status == .forbidden)
        #expect(try decode(AuthorityErrorResponse.self, activeAccount).code == "accountNotPending")
        #expect(!String(buffer: activeAccount.body).contains(renewed.enrollmentToken))
    }
}

@Test func originalBootstrapAndPairingRoutesRemainRegistered() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let bootstrap = try await client.execute(uri: "/v1/bootstrap/challenge", method: .POST,
            headers: ["Authorization": "Bearer " + fixture.bootstrapToken], body: ByteBuffer(string: "{}"))
        #expect(bootstrap.status == .ok)
        for path in ["/v1/bootstrap/enroll", "/v1/challenges", "/v1/epochs", "/v1/workloads",
                     "/v1/pairings/challenge", "/v1/pairings/enroll", "/v1/pairings/approve",
                     "/v1/pairings/confirm", "/v1/devices/revoke", "/v1/recovery"] {
            let response = try await client.execute(uri: path, method: .POST, body: ByteBuffer(string: "{}"))
            #expect(response.status == .badRequest, "Existing route must parse its protocol DTO: \(path)")
        }
    }
}

private struct UISessionHeader: Decodable {
    let sessionID: String
    let revision: UInt64
}

private func uiCallback(_ response: TestingHTTPResponse, identifier: String, property: String) throws -> String {
    let object = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView)) as! [String: Any]
    func find(_ node: [String: Any]) -> String? {
        let modifiers = node["modifiers"] as? [[String: Any]] ?? []
        if modifiers.contains(where: { $0["kind"] as? String == "accessibilityIdentifier" && ($0["args"] as? [String: Any])?["id"] as? String == identifier }),
           let callback = (node["props"] as? [String: Any])?[property] as? String { return callback }
        return (node["children"] as? [[String: Any]] ?? []).lazy.compactMap(find).first
    }
    let tree = try #require(object["tree"] as? [String: Any])
    return try #require(find(tree))
}

private func uiEvents(_ revision: UInt64, _ events: [[String: String]]) throws -> ByteBuffer {
    ByteBuffer(bytes: try JSONSerialization.data(withJSONObject: ["revision": revision, "events": events]))
}

@Test func swiftWorkspaceCallbacksCreateRealAccountsAndRejectStaleOrInventedActions() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { client in
        let unauthorized = try await client.execute(uri: "/v1/admin/ui/sessions", method: .POST)
        #expect(unauthorized.status == .forbidden)
        #expect(try await fixture.authority.listAccounts().accounts.isEmpty)
        let initial = try await client.execute(uri: "/v1/admin/ui/sessions", method: .POST, headers: fixture.headers)
        #expect(initial.status == .created)
        let session = try decode(UISessionHeader.self, initial)
        let field = try uiCallback(initial, identifier: "swiftkey.account-label", property: "onChange")
        let create = try uiCallback(initial, identifier: "swiftkey.create-account", property: "onTap")
        #expect(Int64(create) != nil)
        let path = "/v1/admin/ui/sessions/\(session.sessionID)/events"
        let invalid = try await client.execute(uri: path, method: .POST, headers: fixture.headers,
            body: uiEvents(session.revision, [["id": field, "kind": "string", "value": "must not commit"], ["id": "1", "kind": "void"]]))
        #expect(invalid.status == .badRequest)
        #expect(try await fixture.authority.listAccounts().accounts.isEmpty)
        let created = try await client.execute(uri: path, method: .POST, headers: fixture.headers,
            body: uiEvents(session.revision, [["id": field, "kind": "string", "value": "Actual Swift action"], ["id": create, "kind": "void"]]))
        #expect(created.status == .ok)
        let accounts = try await fixture.authority.listAccounts().accounts
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "Actual Swift action")
        #expect(try await fixture.authority.ledger().events.contains { $0.kind == "account.created" })
        let stale = try await client.execute(uri: path, method: .POST, headers: fixture.headers,
            body: uiEvents(session.revision, [["id": create, "kind": "void"]]))
        #expect(stale.status == .conflict)
        #expect(try await fixture.authority.listAccounts().accounts.count == 1)
        let firstText = String(decoding: created.body.readableBytesView, as: UTF8.self)
        #expect(!firstText.contains(fixture.adminToken))
        #expect(!firstText.contains(fixture.bootstrapToken))
        // A second tab gets the public registry, not the first tab's one-time
        // invitation panel or unsubmitted account-name draft.
        let second = try await client.execute(uri: "/v1/admin/ui/sessions", method: .POST, headers: fixture.headers)
        #expect(!String(decoding: second.body.readableBytesView, as: UTF8.self).contains("swiftkey.invitation"))
        let disconnected = try await client.execute(uri: "/v1/admin/ui/sessions/\(session.sessionID)", method: .DELETE, headers: fixture.headers)
        #expect(disconnected.status == .noContent)
        let closed = try await client.execute(uri: path, method: .POST, headers: fixture.headers,
            body: uiEvents(try decode(UISessionHeader.self, created).revision, [["id": create, "kind": "void"]]))
        #expect(closed.status == .notFound)
    }
}

@Test func vaporAdminAuthenticationPrecedesBodyCollectionForEveryNamespaceRoute() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { app in
        let oversized = ByteBuffer(string: String(repeating: "x", count: 2_000_001))
        for path in ["/v1/admin", "/v1/admin/", "/v1/admin/accounts", "/v1/admin/unknown-route", "/v1/admin/ui/sessions/missing/events"] {
            for method in [HTTPMethod.POST, .PUT, .DELETE, .OPTIONS] {
                let response = try await app.execute(uri: path, method: method, body: oversized)
                #expect(response.status == .forbidden, "Unauthenticated \(method) \(path) must be rejected before its body is consumed")
                #expect(try decode(AuthorityErrorResponse.self, response).code == "unauthorized")
                #expect(response.headers.first(name: "Cache-Control") == "no-store")
            }
        }
        #expect(try await fixture.authority.listAccounts().accounts.isEmpty)
        let unrelated = try await app.execute(uri: "/v1/administer", method: .GET)
        #expect(unrelated.status == .notFound)
        #expect(try decode(AuthorityErrorResponse.self, unrelated).code == "notFound")
    }
}

@Test func vaporPrecollectedBodiesKeepExactV1AdminAndWorkspaceLimits() async throws {
    let fixture = try HTTPFixture.make()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try await fixture.test { app in
        let create = "{\"label\":\"Exactly bounded account\"}"
        let exact = try await app.execute(uri: "/v1/admin/accounts", method: .POST, headers: fixture.headers,
            body: paddedHTTPBody(create, count: 16_384))
        #expect(exact.status == .created)
        let excess = try await app.execute(uri: "/v1/admin/accounts", method: .POST, headers: fixture.headers,
            body: paddedHTTPBody(create, count: 16_385))
        #expect(excess.status == .payloadTooLarge)
        #expect(try decode(AuthorityErrorResponse.self, excess).code == "invalidRequest")
        #expect(try await fixture.authority.listAccounts().accounts.count == 1)
        let v1 = try await app.execute(uri: "/v1/challenges", method: .POST, body: paddedHTTPBody("{}", count: 2_000_000))
        #expect(v1.status == .badRequest) // The full body reached DTO validation.
        let v1Excess = try await app.execute(uri: "/v1/challenges", method: .POST, body: paddedHTTPBody("{}", count: 2_000_001))
        #expect(v1Excess.status == .payloadTooLarge)
        let events = "{\"revision\":1,\"events\":[]}"
        let eventResponse = try await app.execute(uri: "/v1/admin/ui/sessions/missing/events", method: .POST, headers: fixture.headers,
            body: paddedHTTPBody(events, count: 131_072))
        #expect(eventResponse.status == .notFound)
        let eventExcess = try await app.execute(uri: "/v1/admin/ui/sessions/missing/events", method: .POST, headers: fixture.headers,
            body: paddedHTTPBody(events, count: 131_073))
        #expect(eventExcess.status == .payloadTooLarge)
        for response in [excess, v1Excess, eventExcess] {
            #expect(response.headers.first(name: "Cache-Control") == "no-store")
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff")
            #expect(response.headers.first(name: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
            #expect(response.headers.first(name: "Access-Control-Allow-Origin") == nil)
        }
    }
}
