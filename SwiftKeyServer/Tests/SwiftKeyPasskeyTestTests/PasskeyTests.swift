import Foundation
import Crypto
import SwiftCBOR
import Testing
import Vapor
import VaporTesting
import WebAuthn
@testable import SwiftKeyPasskeyTest

private let origin = "http://localhost:18202"
private func config() throws -> PasskeyTestConfiguration { try .init(relyingPartyID: "localhost", origin: origin) }
private func b64(_ value: [UInt8]) -> String { PasskeyValidation.base64URL(value) }
private func decode64(_ value: Any?) throws -> [UInt8] {
    let string = try #require(value as? String)
    return try #require(URLEncodedBase64(string).decodedBytes)
}
private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
private func object(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
private func rejects(_ operation: () async throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) async {
    do { try await operation(); Issue.record("Expected rejection", sourceLocation: sourceLocation) } catch {}
}

/// Synthetic authenticator. Tests use actual P-256 signatures over authenticator
/// data + SHA256(clientDataJSON); no fake verifier or success stub is involved.
private struct Authenticator {
    let key: P256.Signing.PrivateKey
    let id = [UInt8](repeating: 0x37, count: 32)
    init() throws { key = try P256.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x2a, count: 32)) }
    func client(challenge: [UInt8], create: Bool, origin clientOrigin: String = origin, crossOrigin: Bool = false) throws -> [UInt8] {
        Array(try json(["type": create ? "webauthn.create" : "webauthn.get", "challenge": b64(challenge), "origin": clientOrigin, "crossOrigin": crossOrigin]))
    }
    func data(flags: UInt8, counter: UInt32 = 0, rp: String = "localhost") -> [UInt8] {
        Array(SHA256.hash(data: Data(rp.utf8))) + [flags, UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16), UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter)]
    }
    func registrationJSON(challenge: [UInt8], flags: UInt8 = 0x45, rawID: [UInt8]? = nil,
                          embeddedID: [UInt8]? = nil, clientOrigin: String = origin, rp: String = "localhost", crossOrigin: Bool = false) throws -> [String: Any] {
        let rawKey = Array(key.publicKey.x963Representation)
        let cose: CBOR = .map([.unsignedInt(1): .unsignedInt(2), .unsignedInt(3): .negativeInt(6),
            .negativeInt(0): .unsignedInt(1), .negativeInt(1): .byteString(Array(rawKey[1..<33])),
            .negativeInt(2): .byteString(Array(rawKey[33..<65]))])
        let embedded = embeddedID ?? id
        let auth = data(flags: flags, rp: rp) + [UInt8](repeating: 0, count: 16)
            + [UInt8(embedded.count >> 8), UInt8(embedded.count & 255)] + embedded + cose.encode()
        let attestation: CBOR = .map([.utf8String("fmt"): .utf8String("none"),
            .utf8String("authData"): .byteString(auth), .utf8String("attStmt"): .map([:])])
        return ["id": b64(id), "rawId": b64(rawID ?? id), "type": "public-key", "response": [
            "clientDataJSON": b64(try client(challenge: challenge, create: true, origin: clientOrigin, crossOrigin: crossOrigin)),
            "attestationObject": b64(attestation.encode())]]
    }
    func registration(_ start: PasskeyRegistrationStart, flags: UInt8 = 0x45) throws -> RegistrationCredential {
        try JSONDecoder().decode(RegistrationCredential.self, from: json(registrationJSON(challenge: start.publicKey.base.challenge, flags: flags)))
    }
    func assertionJSON(challenge: [UInt8], user: [UInt8]?, flags: UInt8 = 0x05, counter: UInt32 = 1,
                       clientOrigin: String = origin, rp: String = "localhost", crossOrigin: Bool = false,
                       corruptSignature: Bool = false, rawID: [UInt8]? = nil) throws -> [String: Any] {
        let client = try client(challenge: challenge, create: false, origin: clientOrigin, crossOrigin: crossOrigin)
        let auth = data(flags: flags, counter: counter, rp: rp)
        var signature = Array(try key.signature(for: auth + Array(SHA256.hash(data: client))).derRepresentation)
        if corruptSignature { signature[signature.count - 1] ^= 1 }
        return ["id": b64(id), "rawId": b64(rawID ?? id), "type": "public-key", "response": [
            "clientDataJSON": b64(client), "authenticatorData": b64(auth), "signature": b64(signature),
            "userHandle": user.map(b64) as Any? ?? NSNull()]]
    }
    func assertion(_ start: PasskeyAuthenticationStart, user: [UInt8]?, counter: UInt32 = 1) throws -> AuthenticationCredential {
        try JSONDecoder().decode(AuthenticationCredential.self, from: json(assertionJSON(challenge: start.publicKey.challenge, user: user, counter: counter)))
    }
}
private struct Rig {
    let store: PasskeyTestStore
    let session: PasskeyTestStore.Session
    let auth: Authenticator
    let user: [UInt8]
    static func registered(now: @escaping @Sendable () -> TimeInterval = { 1000 }) async throws -> Self {
        let store = try PasskeyTestStore(configuration: config(), now: now)
        let (session, _) = try await store.bootstrap(existing: nil)
        let auth = try Authenticator()
        let start = try await store.beginRegistration(sessionID: session.id, username: "Synthetic phone")
        let result = try await store.finishRegistration(sessionID: session.id, ceremonyID: start.ceremonyID, credential: auth.registration(start))
        #expect(result.registered && !result.authenticated)
        return .init(store: store, session: session, auth: auth, user: start.publicKey.base.user.id)
    }
}

@Test func configurationRequiresExplicitOptInAndExactOrigin() throws {
    #expect(try PasskeyTestConfiguration.fromEnvironment([:]) == nil)
    for env in [["SWIFTKEY_PASSKEY_TEST_ENABLED": "true"], ["SWIFTKEY_PASSKEY_RP_ID": "localhost"], ["SWIFTKEY_PASSKEY_TEST_ENABLED": "1"]] {
        #expect(throws: (any Error).self) { try PasskeyTestConfiguration.fromEnvironment(env) }
    }
    for invalid in ["http://example.com", "http://localhost:18202/", "http://user@localhost:18202", "http://localhost:18202?x=1", "http://evil.localhost:18202"] {
        #expect(throws: (any Error).self) { try PasskeyTestConfiguration(relyingPartyID: "localhost", origin: invalid) }
    }
    #expect(try config().localPort == 18202)
    #expect(try PasskeyTestConfiguration(relyingPartyID: "example.com", origin: "https://example.com").secureCookies)
}

@Test func realRegistrationAndAssertionRequireUVAndKeepAuthoritySeparate() async throws {
    let rig = try await Rig.registered()
    let start = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    #expect(start.publicKey.userVerification == .required)
    let result = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID,
        credential: rig.auth.assertion(start, user: rig.user))
    #expect(result.authenticated && !result.registered)
    #expect(result.signCount == 1 && !result.backupEligible && !result.backedUp)
    let (_, bootstrap) = try await rig.store.bootstrap(existing: rig.session.id)
    #expect(bootstrap.username == "Synthetic phone")
    await rig.store.signOut(sessionID: rig.session.id)
    let (_, signedOut) = try await rig.store.bootstrap(existing: rig.session.id)
    #expect(signedOut.username == nil)
}

@Test func registrationOptionsRequireResidentES256AndUV() async throws {
    let store = try PasskeyTestStore(configuration: config())
    let (session, _) = try await store.bootstrap(existing: nil)
    let start = try await store.beginRegistration(sessionID: session.id, username: "Test")
    let value = try object(JSONEncoder().encode(start))
    let options = try #require(value["publicKey"] as? [String: Any])
    let selection = try #require(options["authenticatorSelection"] as? [String: Any])
    #expect(selection["residentKey"] as? String == "required")
    #expect(selection["userVerification"] as? String == "required")
    #expect(options["attestation"] as? String == "none")
    #expect((options["pubKeyCredParams"] as? [[String: Any]])?.first?["alg"] as? Int == -7)
}

@Test func replayCrossSessionAndSupersededCeremoniesReject() async throws {
    let rig = try await Rig.registered()
    let start = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    let assertion = try rig.auth.assertion(start, user: rig.user)
    let (other, _) = try await rig.store.bootstrap(existing: nil)
    await rejects { _ = try await rig.store.finishAuthentication(sessionID: other.id, ceremonyID: start.ceremonyID, credential: assertion) }
    _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID, credential: assertion)
    await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID, credential: assertion) }
    let previous = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    _ = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: previous.ceremonyID, credential: rig.auth.assertion(previous, user: rig.user, counter: 2)) }
}

@Test func registrationRejectsMismatchedIDsOriginRPAndFlags() async throws {
    for fault in ["rawID", "embeddedID", "origin", "rp", "crossOrigin", "noUP", "noUV", "noAT", "BSwithoutBE", "extension"] {
        let store = try PasskeyTestStore(configuration: config())
        let (session, _) = try await store.bootstrap(existing: nil)
        let start = try await store.beginRegistration(sessionID: session.id, username: "Synthetic")
        let auth = try Authenticator()
        let flags: UInt8 = ["noUP": 0x44, "noUV": 0x41, "noAT": 0x05, "BSwithoutBE": 0x55, "extension": 0xc5][fault] ?? 0x45
        let value = try auth.registrationJSON(challenge: start.publicKey.base.challenge, flags: flags,
            rawID: fault == "rawID" ? [1] : nil, embeddedID: fault == "embeddedID" ? [2] : nil,
            clientOrigin: fault == "origin" ? "http://other.invalid" : origin,
            rp: fault == "rp" ? "other.invalid" : "localhost", crossOrigin: fault == "crossOrigin")
        let credential = try JSONDecoder().decode(RegistrationCredential.self, from: json(value))
        await rejects { _ = try await store.finishRegistration(sessionID: session.id, ceremonyID: start.ceremonyID, credential: credential) }
    }
}

@Test func signedAssertionsRejectEveryUnboundOrAlteredInputAndConsumeAttempt() async throws {
    for fault in ["userHandle", "nilHandle", "rawID", "origin", "rp", "challenge", "crossOrigin", "signature", "noUP", "noUV", "AT", "BSwithoutBE", "changedBE", "extension"] {
        let rig = try await Rig.registered()
        let start = try await rig.store.beginAuthentication(sessionID: rig.session.id)
        let flags: UInt8 = ["noUP": 0x04, "noUV": 0x01, "AT": 0x45, "BSwithoutBE": 0x15, "changedBE": 0x0d, "extension": 0x85][fault] ?? 0x05
        let value = try rig.auth.assertionJSON(challenge: fault == "challenge" ? [1,2,3] : start.publicKey.challenge,
            user: fault == "nilHandle" ? nil : (fault == "userHandle" ? [99] : rig.user), flags: flags,
            clientOrigin: fault == "origin" ? "https://other.invalid" : origin,
            rp: fault == "rp" ? "other.invalid" : "localhost", crossOrigin: fault == "crossOrigin",
            corruptSignature: fault == "signature", rawID: fault == "rawID" ? [1] : nil)
        let credential = try JSONDecoder().decode(AuthenticationCredential.self, from: json(value))
        await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID, credential: credential) }
        await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID, credential: rig.auth.assertion(start, user: rig.user)) }
    }
}

@Test func credentialUniquenessAndSignatureCounterAreAtomic() async throws {
    let rig = try await Rig.registered()
    let duplicate = try await rig.store.beginRegistration(sessionID: rig.session.id, username: "Other user")
    await rejects { _ = try await rig.store.finishRegistration(sessionID: rig.session.id, ceremonyID: duplicate.ceremonyID, credential: rig.auth.registration(duplicate)) }
    let first = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: first.ceremonyID, credential: rig.auth.assertion(first, user: rig.user))
    let next = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: next.ceremonyID, credential: rig.auth.assertion(next, user: rig.user)) }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1000
    func read() -> TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}
@Test func expiredCeremoniesAndSessionCSRFReject() async throws {
    let clock = Clock()
    let rig = try await Rig.registered(now: { clock.read() })
    let start = try await rig.store.beginAuthentication(sessionID: rig.session.id)
    clock.advance(121)
    await rejects { _ = try await rig.store.finishAuthentication(sessionID: rig.session.id, ceremonyID: start.ceremonyID, credential: rig.auth.assertion(start, user: rig.user)) }
    await rejects { _ = try await rig.store.authorize(rig.session.id, csrf: "wrong") }
    #expect(try await rig.store.authorize(rig.session.id, csrf: rig.session.csrf) == rig.session.id)
    clock.advance(1800)
    await rejects { _ = try await rig.store.authorize(rig.session.id, csrf: rig.session.csrf) }
}

private func withApp(_ run: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    app.middleware = .init(); app.logger.logLevel = .critical
    do { try SwiftKeyPasskeyTest.configureStandalone(app, configuration: config()); try await run(app) }
    catch { try? await app.asyncShutdown(); throw error }
    try await app.asyncShutdown()
}
private func responseObject(_ response: TestingHTTPResponse) throws -> [String: Any] {
    try object(Data(response.body.readableBytesView))
}
private func bootstrap(_ app: Application) async throws -> (String, String) {
    let response = try await app.testing().sendRequest(.GET, "/passkeys/test/bootstrap", headers: ["Host": "localhost:18202"])
    #expect(response.status == .ok)
    let cookie = try #require(response.headers.first(name: "Set-Cookie")?.split(separator: ";").first.map(String.init))
    #expect(response.headers.first(name: "Set-Cookie")?.contains("HttpOnly; SameSite=Strict") == true)
    return (cookie, try #require(responseObject(response)["csrf"] as? String))
}
private func headers(_ cookie: String, _ csrf: String) -> HTTPHeaders {
    ["Host": "localhost:18202", "Origin": origin, "Cookie": cookie, "X-SwiftKey-Test-CSRF": csrf, "Content-Type": "application/json"]
}

@Test func browserHTTPRoundTripUsesRealVerifier() async throws {
    try await withApp { app in
        let (cookie, csrf) = try await bootstrap(app)
        let h = headers(cookie, csrf)
        func post(_ suffix: String, _ value: [String: Any]) async throws -> TestingHTTPResponse {
            try await app.testing().sendRequest(.POST, "/passkeys/test/" + suffix, headers: h, body: ByteBuffer(data: json(value)))
        }
        let auth = try Authenticator()
        let options = try responseObject(await post("registration/options", ["username": "Browser fixture"]))
        let key = try #require(options["publicKey"] as? [String: Any])
        let challenge = try decode64(key["challenge"])
        let user = try #require(key["user"] as? [String: Any])
        let userHandle = try decode64(user["id"])
        let created = try await post("registration/verify", ["ceremonyID": try #require(options["ceremonyID"]), "credential": auth.registrationJSON(challenge: challenge)])
        #expect(created.status == .ok)
        #expect(try responseObject(created)["authenticated"] as? Bool == false)
        let start = try responseObject(await post("authentication/options", [:]))
        let requestKey = try #require(start["publicKey"] as? [String: Any])
        let assertionChallenge = try decode64(requestKey["challenge"])
        let finish: [String: Any] = ["ceremonyID": try #require(start["ceremonyID"]), "credential": try auth.assertionJSON(challenge: assertionChallenge, user: userHandle)]
        let verified = try await post("authentication/verify", finish)
        #expect(verified.status == .ok)
        #expect(try responseObject(verified)["authenticated"] as? Bool == true)
        #expect(verified.headers.first(name: "Cache-Control") == "no-store")
        #expect(try await post("authentication/verify", finish).status == .conflict)
        #expect(try await app.testing().sendRequest(.GET, "/v1/admin/accounts").status == .notFound)
        #expect(try await app.testing().sendRequest(.GET, "/favicon.ico").status == .notFound)
    }
}

@Test func HTTPRejectsWrongHostOriginCSRFSessionAndOversizedBodies() async throws {
    try await withApp { app in
        let (cookie, csrf) = try await bootstrap(app)
        let normal = headers(cookie, csrf)
        for change in ["Host", "Origin", "X-SwiftKey-Test-CSRF", "Cookie"] {
            var h = normal; h.replaceOrAdd(name: change, value: "wrong")
            let result = try await app.testing().sendRequest(.POST, "/passkeys/test/authentication/options", headers: h, body: ByteBuffer(string: "{}"))
            #expect(result.status != .ok)
            #expect(result.headers.first(name: "Cache-Control") == "no-store")
        }
        var duplicate = normal; duplicate.add(name: "Cookie", value: cookie)
        #expect(try await app.testing().sendRequest(.POST, "/passkeys/test/authentication/options", headers: duplicate, body: ByteBuffer(string: "{}")).status == .unauthorized)
        let huge = ByteBuffer(string: String(repeating: " ", count: 131_073))
        #expect(try await app.testing().sendRequest(.POST, "/passkeys/test/authentication/options", headers: normal, body: huge).status == .payloadTooLarge)
        let page = try await app.testing().sendRequest(.GET, "/passkeys/test", headers: ["Host": "localhost:18202"])
        #expect(page.status == .ok)
        #expect(page.body.string.contains("/passkeys/test/app.js"))
        #expect(!page.body.string.contains("<script>"))
        #expect(page.headers.first(name: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
    }
}

@Test func actualAndroidEngineFixtureVerifiesWithIndependentSwiftRP() async throws {
    struct Fixture: Decodable {
        let source: String
        let rpId: String
        let origin: String
        let userHandle: String
        let registrationChallenge: String
        let assertionChallenge: String
        let registration: RegistrationCredential
        let assertion: AuthenticationCredential
    }
    let url = try #require(Bundle.module.url(forResource: "android-engine", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    #expect(fixture.rpId == "example.com" && fixture.origin == "https://example.com")
    let manager = WebAuthnManager(configuration: .init(relyingPartyID: fixture.rpId,
        relyingPartyName: "Independent engine test", relyingPartyOrigin: fixture.origin))
    let id = try PasskeyValidation.registration(fixture.registration)
    let registered = try await manager.finishRegistration(challenge: decode64(fixture.registrationChallenge),
        credentialCreationData: fixture.registration, requireUserVerification: true,
        supportedPublicKeyAlgorithms: [.init(alg: .algES256)], confirmCredentialIDNotRegisteredYet: { _ in true })
    #expect(!registered.backupEligible && !registered.isBackedUp)
    #expect(try PasskeyValidation.credentialID(fixture.assertion.id, raw: fixture.assertion.rawID) == id)
    #expect(fixture.assertion.response.userHandle == (try decode64(fixture.userHandle)))
    try PasskeyValidation.clientData(fixture.assertion.response.clientDataJSON)
    let flags = try PasskeyValidation.flags(fixture.assertion.response.authenticatorData, registration: false)
    #expect(!flags.eligible && !flags.backedUp)
    let verified = try manager.finishAuthentication(credential: fixture.assertion,
        expectedChallenge: decode64(fixture.assertionChallenge), credentialPublicKey: registered.publicKey,
        credentialCurrentSignCount: registered.signCount, requireUserVerification: true)
    // Android engine deliberately uses the WebAuthn zero-counter mode.
    #expect(registered.signCount == 0 && verified.newSignCount == 0)
}

@Test func actualIOSMockEngineFixtureVerifiesWithIndependentSwiftRP() async throws {
    struct Fixture: Decodable {
        let source: String
        let rpId: String
        let origin: String
        let userHandle: String
        let registrationChallenge: String
        let assertionChallenge: String
        let registration: RegistrationCredential
        let assertion: AuthenticationCredential
    }
    let url = try #require(Bundle.module.url(forResource: "ios-mock-engine", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    #expect(fixture.rpId == "swiftkey.mock" && fixture.origin == "https://swiftkey.mock")
    #expect(fixture.source.contains("mock software authenticator") && fixture.source.contains("simulated user verification"))
    let manager = WebAuthnManager(configuration: .init(relyingPartyID: fixture.rpId,
        relyingPartyName: "Independent iOS mock test", relyingPartyOrigin: fixture.origin))
    let id = try PasskeyValidation.registration(fixture.registration)
    let registered = try await manager.finishRegistration(challenge: decode64(fixture.registrationChallenge),
        credentialCreationData: fixture.registration, requireUserVerification: true,
        supportedPublicKeyAlgorithms: [.init(alg: .algES256)], confirmCredentialIDNotRegisteredYet: { _ in true })
    #expect(!registered.backupEligible && !registered.isBackedUp)
    #expect(try PasskeyValidation.credentialID(fixture.assertion.id, raw: fixture.assertion.rawID) == id)
    #expect(fixture.assertion.response.userHandle == (try decode64(fixture.userHandle)))
    try PasskeyValidation.clientData(fixture.assertion.response.clientDataJSON)
    let flags = try PasskeyValidation.flags(fixture.assertion.response.authenticatorData, registration: false)
    #expect(!flags.eligible && !flags.backedUp)
    #expect(throws: (any Error).self) {
        try manager.finishAuthentication(credential: fixture.assertion,
            expectedChallenge: [UInt8](repeating: 0, count: 32), credentialPublicKey: registered.publicKey,
            credentialCurrentSignCount: registered.signCount, requireUserVerification: true)
    }
    let verified = try manager.finishAuthentication(credential: fixture.assertion,
        expectedChallenge: decode64(fixture.assertionChallenge), credentialPublicKey: registered.publicKey,
        credentialCurrentSignCount: registered.signCount, requireUserVerification: true)
    // Real ES256/CBOR interoperability; the fixture's UP/UV are explicitly simulated.
    // This is not evidence of a signed Apple extension or real user verification.
    #expect(registered.signCount == 0 && verified.newSignCount == 0)
}
