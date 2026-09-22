import CryptoKit
import Foundation
import Security
import XCTest
@testable import SwiftKeyPasskeys

final class MockPasskeyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let suppliedHash = Data((0..<32).map(UInt8.init))
    private let user = Data([1, 2, 3, 4])

    func testProductionAndRealRelyingPartiesAreUnavailable() throws {
        expect(.productionUnavailable) { _ = try MockPasskeyEngine(mode: .production) }
        var engine = try MockPasskeyEngine()
        for rp in ["example.com", "SwiftKey.mock", "swiftkey.mock.", "swiftkey.mock.evil", "https://swiftkey.mock", "127.0.0.1", ""] {
            expect(.relyingPartyNotAllowed) { _ = try engine.approve(.create(createRequest(rpID: rp)), now: now) }
        }
        for rp in ["localhost", "swiftkey.mock"] {
            let response = try create(&engine, createRequest(rpID: rp))
            XCTAssertEqual(response.credential.rpID, rp)
        }
    }

    func testMalformedTypedRequestsFailBeforeApprovalOrKeyGeneration() throws {
        var engine = try MockPasskeyEngine()
        for size in [0, 31, 33] {
            expect(.malformedRequest) { _ = try engine.approve(.create(createRequest(clientHash: Data(repeating: 0, count: size))), now: now) }
        }
        for size in [0, 65] {
            expect(.malformedRequest) { _ = try engine.approve(.create(createRequest(handle: Data(repeating: 0, count: size))), now: now) }
        }
        for name in ["", "a\n", String(repeating: "é", count: 129)] {
            let request = MockCreatePasskeyRequest(rpID: "swiftkey.mock", userHandle: user, userName: name,
                                                  displayName: "Alice", clientDataHash: suppliedHash)
            expect(.malformedRequest) { _ = try engine.approve(.create(request), now: now) }
        }
        expect(.unsupportedAlgorithm) { _ = try engine.approve(.create(createRequest(algorithms: [-257])), now: now) }
        expect(.malformedRequest) { _ = try engine.approve(.create(createRequest(excluded: [Data()])), now: now) }
        expect(.malformedRequest) { _ = try engine.approve(.create(createRequest(excluded: Array(repeating: Data([1]), count: 129))), now: now) }
        XCTAssertTrue(engine.credentials.isEmpty)
        XCTAssertTrue(engine.state.consumedRequests.isEmpty)
    }

    func testRegistrationHasIndependentCBORCOSEAndAnonymousNoneAttestation() throws {
        var engine = try MockPasskeyEngine()
        let response = try create(&engine, createRequest())
        var decoder = CBORDecoder(response.attestationObject)
        let attestation = try decoder.complete().map()
        XCTAssertEqual(try attestation[.text("fmt")]?.text(), "none")
        XCTAssertEqual(try attestation[.text("attStmt")]?.map().count, 0)
        let auth = try XCTUnwrap(attestation[.text("authData")]).bytes()
        XCTAssertEqual(auth, response.authenticatorData)
        XCTAssertEqual(auth.prefix(32), Data(SHA256.hash(data: Data("swiftkey.mock".utf8))))
        XCTAssertEqual(auth[32], 0x45) // Simulated UP+UV+AT. BE/BS/ED are zero.
        XCTAssertEqual(auth.subdata(in: 33..<37), Data(repeating: 0, count: 4))
        XCTAssertEqual(auth.subdata(in: 37..<53), Data(repeating: 0, count: 16))
        XCTAssertEqual(auth.subdata(in: 53..<55), Data([0, 32]))
        XCTAssertEqual(auth.subdata(in: 55..<87), response.credential.id)
        var coseDecoder = CBORDecoder(auth.subdata(in: 87..<auth.count))
        let cose = try coseDecoder.complete().map()
        XCTAssertEqual(cose.count, 5)
        XCTAssertEqual(try cose[.integer(1)]?.integer(), 2)
        XCTAssertEqual(try cose[.integer(3)]?.integer(), -7)
        XCTAssertEqual(try cose[.integer(-1)]?.integer(), 1)
        let x = try XCTUnwrap(cose[.integer(-2)]).bytes()
        let y = try XCTUnwrap(cose[.integer(-3)]).bytes()
        XCTAssertEqual(x.count, 32); XCTAssertEqual(y.count, 32)
        XCTAssertEqual(Data([4]) + x + y, response.publicKeyX963)
        XCTAssertEqual(response.credential.id.count, 32)
    }

    func testAssertionVerifiesUsingIndependentSecurityFrameworkAndExactOSHash() throws {
        var engine = try MockPasskeyEngine()
        let registration = try create(&engine, createRequest())
        let request = signRequest(id: registration.credential.id)
        let token = try engine.approve(.sign(request), now: now)
        let response = try engine.sign(request, approval: token, now: now)
        try response.verify(publicKeyX963: registration.publicKeyX963)
        let expected = Data(SHA256.hash(data: Data("swiftkey.mock".utf8))) + Data([5, 0, 0, 0, 0])
        XCTAssertEqual(response.authenticatorData, expected)
        XCTAssertEqual(response.clientDataHash, suppliedHash)
        XCTAssertTrue(try verifyWithSecurity(publicKey: registration.publicKeyX963,
            payload: expected + suppliedHash, signature: response.signatureDER))
        XCTAssertFalse(try verifyWithSecurity(publicKey: registration.publicKeyX963,
            payload: expected + Data(SHA256.hash(data: suppliedHash)), signature: response.signatureDER))
        XCTAssertEqual(response.userHandle, user)
        XCTAssertEqual(response.credentialID, registration.credential.id)
    }

    func testApprovalBindsEveryRequestFieldAndCannotBeReusedAfterMismatch() throws {
        var engine = try MockPasskeyEngine()
        let original = createRequest()
        let changed = MockCreatePasskeyRequest(requestID: original.requestID, rpID: original.rpID, userHandle: original.userHandle,
            userName: original.userName, displayName: "A different user label", clientDataHash: original.clientDataHash)
        let token = try engine.approve(.create(original), now: now)
        expect(.approvalMismatch) { _ = try engine.create(changed, approval: token, now: now) }
        expect(.invalidApproval) { _ = try engine.create(original, approval: token, now: now) }
        XCTAssertTrue(engine.credentials.isEmpty)
    }

    func testApprovalCannotSwitchHashRPAccountOrOperation() throws {
        for change in ["hash", "rp", "user", "id"] {
            var engine = try MockPasskeyEngine()
            let original = createRequest()
            let changed = MockCreatePasskeyRequest(requestID: change == "id" ? UUID() : original.requestID,
                rpID: change == "rp" ? "localhost" : original.rpID,
                userHandle: change == "user" ? Data([99]) : original.userHandle,
                userName: original.userName, displayName: original.displayName,
                clientDataHash: change == "hash" ? Data(repeating: 9, count: 32) : original.clientDataHash)
            let token = try engine.approve(.create(original), now: now)
            expect(.approvalMismatch) { _ = try engine.create(changed, approval: token, now: now) }
        }
        var engine = try MockPasskeyEngine()
        let request = createRequest()
        let token = try engine.approve(.create(request), now: now)
        let signing = MockSignPasskeyRequest(requestID: request.requestID, rpID: request.rpID, clientDataHash: request.clientDataHash)
        expect(.approvalMismatch) { _ = try engine.sign(signing, approval: token, now: now) }
    }

    func testAcceptedRequestCannotReplayAfterCodablePersistenceOrDeletion() throws {
        var engine = try MockPasskeyEngine()
        let request = createRequest()
        let token = try engine.approve(.create(request), now: now)
        let response = try engine.create(request, approval: token, now: now)
        expect(.replayed) { _ = try engine.create(request, approval: token, now: now) }
        var restored = try MockPasskeyEngine(state: JSONDecoder().decode(MockPasskeyState.self, from: JSONEncoder().encode(engine.state)))
        expect(.replayed) { _ = try restored.approve(.create(request), now: now) }
        try restored.deleteCredential(id: response.credential.id)
        expect(.replayed) { _ = try restored.approve(.create(request), now: now) }
    }

    func testSignReplayJournalSurvivesReload() throws {
        var engine = try MockPasskeyEngine()
        let credential = try create(&engine, createRequest()).credential
        let request = signRequest(id: credential.id)
        let token = try engine.approve(.sign(request), now: now)
        _ = try engine.sign(request, approval: token, now: now)
        var restored = try MockPasskeyEngine(state: engine.state)
        expect(.replayed) { _ = try restored.approve(.sign(request), now: now) }
        XCTAssertEqual(restored.state.consumedRequests.count, 2)
    }

    func testCancellationPersistsWithoutCreatingAKey() throws {
        var engine = try MockPasskeyEngine()
        let request = createRequest()
        let token = try engine.approve(.create(request), now: now)
        try engine.cancel(token, now: now)
        expect(.cancelled) { _ = try engine.create(request, approval: token, now: now) }
        var restored = try MockPasskeyEngine(state: engine.state)
        expect(.cancelled) { _ = try restored.approve(.create(request), now: now) }
        XCTAssertTrue(restored.credentials.isEmpty)
    }

    func testApprovalExpiryClockRollbackAndUnknownTokenFailClosed() throws {
        for delta: TimeInterval in [-1, 60, 600] {
            var engine = try MockPasskeyEngine()
            let request = createRequest(); let token = try engine.approve(.create(request), now: now)
            expect(.approvalExpired) { _ = try engine.create(request, approval: token, now: now.addingTimeInterval(delta)) }
        }
        var engine = try MockPasskeyEngine(); var other = try MockPasskeyEngine()
        let request = createRequest(); let token = try other.approve(.create(request), now: now)
        expect(.invalidApproval) { _ = try engine.create(request, approval: token, now: now) }
        let local = try engine.approve(.create(request), now: now)
        _ = try engine.create(request, approval: local, now: now.addingTimeInterval(59.999))
    }

    func testSameRPAndUserKeepCredentialAndKeyAcrossReloadAndFourHourBoundaries() throws {
        var engine = try MockPasskeyEngine()
        let first = try create(&engine, createRequest())
        var restored = try MockPasskeyEngine(state: engine.state)
        let later = now.addingTimeInterval(14_400 * 10)
        let request = createRequest(clientHash: Data(repeating: 7, count: 32))
        let token = try restored.approve(.create(request), now: later)
        let second = try restored.create(request, approval: token, now: later)
        XCTAssertEqual(first.credential.id, second.credential.id)
        XCTAssertEqual(first.publicKeyX963, second.publicKeyX963)
        XCTAssertEqual(first.credential.createdAt, second.credential.createdAt)
        XCTAssertEqual(restored.credentials.count, 1)
    }

    func testDifferentRPOrUserHasDifferentStableKeys() throws {
        var engine = try MockPasskeyEngine()
        let a = try create(&engine, createRequest())
        let b = try create(&engine, createRequest(handle: Data([9])))
        let c = try create(&engine, createRequest(rpID: "localhost"))
        XCTAssertEqual(Set([a.credential.id, b.credential.id, c.credential.id]).count, 3)
        XCTAssertEqual(Set([a.publicKeyX963, b.publicKeyX963, c.publicKeyX963]).count, 3)
    }

    func testAllowListsUserHandlesAndExplicitSelectionAreBound() throws {
        var engine = try MockPasskeyEngine()
        let a = try create(&engine, createRequest()).credential
        let b = try create(&engine, createRequest(handle: Data([9]))).credential
        let ambiguous = signRequest()
        let token = try engine.approve(.sign(ambiguous), now: now)
        expect(.ambiguousCredential) { _ = try engine.sign(ambiguous, approval: token, now: now) }
        let allowed = MockSignPasskeyRequest(rpID: "swiftkey.mock", clientDataHash: suppliedHash, allowedCredentialIDs: [b.id])
        XCTAssertEqual(engine.matchingCredentials(for: allowed).map(\.id), [b.id])
        let disallowed = MockSignPasskeyRequest(rpID: "swiftkey.mock", clientDataHash: suppliedHash, credentialID: a.id, allowedCredentialIDs: [b.id])
        let disallowedToken = try engine.approve(.sign(disallowed), now: now)
        expect(.noMatchingCredential) { _ = try engine.sign(disallowed, approval: disallowedToken, now: now) }
        let wrongUser = MockSignPasskeyRequest(rpID: "swiftkey.mock", clientDataHash: suppliedHash, credentialID: a.id, userHandle: b.userHandle)
        XCTAssertTrue(engine.matchingCredentials(for: wrongUser).isEmpty)
        let wrongRP = signRequest(rpID: "localhost", id: a.id)
        XCTAssertTrue(engine.matchingCredentials(for: wrongRP).isEmpty)
    }

    func testExclusionAppliesToAnyMatchingCredentialAtTheExactRP() throws {
        var engine = try MockPasskeyEngine()
        let a = try create(&engine, createRequest()).credential
        let excluded = createRequest(handle: Data([8]), excluded: [a.id])
        let token = try engine.approve(.create(excluded), now: now)
        expect(.credentialExcluded) { _ = try engine.create(excluded, approval: token, now: now) }
        let otherRP = try create(&engine, createRequest(rpID: "localhost", excluded: [a.id]))
        XCTAssertNotEqual(otherRP.credential.id, a.id)
        XCTAssertEqual(engine.credentials.count, 2)
    }

    func testPersistedKeyMaterialMustMatchPublicKeyAndMockRP() throws {
        var engine = try MockPasskeyEngine()
        _ = try create(&engine, createRequest())
        let encoded = try JSONEncoder().encode(engine.state)
        for field in ["mockPrivateKeyRawRepresentation", "publicKeyX963", "rpID", "id"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            var credentials = try XCTUnwrap(object["credentials"] as? [[String: Any]])
            credentials[0][field] = field == "rpID" ? "example.com" : Data(repeating: 0, count: field == "id" ? 31 : 32).base64EncodedString()
            object["credentials"] = credentials
            let tampered = try JSONDecoder().decode(MockPasskeyState.self, from: JSONSerialization.data(withJSONObject: object))
            expect(.invalidState) { _ = try MockPasskeyEngine(state: tampered) }
        }
    }

    func testPersistedSchemaDuplicateCredentialsAndDuplicateJournalAreRejected() throws {
        var engine = try MockPasskeyEngine()
        _ = try create(&engine, createRequest())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(engine.state)) as? [String: Any])
        for field in ["formatVersion", "credentials", "consumedRequests"] {
            var object = original
            if field == "formatVersion" { object[field] = 2 }
            else { let values = try XCTUnwrap(object[field] as? [Any]); object[field] = values + values }
            let state = try JSONDecoder().decode(MockPasskeyState.self, from: JSONSerialization.data(withJSONObject: object))
            expect(.invalidState) { _ = try MockPasskeyEngine(state: state) }
        }
    }

    func testResponseJSONPreservesExactClientDataOrUsesEmptyOSPlaceholder() throws {
        var engine = try MockPasskeyEngine()
        let raw = Data("{\"type\":\"webauthn.create\",\"challenge\":\"opaque-browser-input\"}".utf8)
        let response = try create(&engine, createRequest(clientHash: Data(SHA256.hash(data: raw))))
        let placeholder = try responseJSON(response.webAuthnJSON())
        XCTAssertEqual(placeholder["clientDataJSON"] as? String, "")
        let full = try responseJSON(response.webAuthnJSON(clientDataJSON: raw))
        XCTAssertEqual(full["clientDataJSON"] as? String, raw.base64URLEncodedString())
        expect(.approvalMismatch) { _ = try response.webAuthnJSON(clientDataJSON: raw + Data([32])) }
        let assertionRequest = signRequest(id: response.credential.id)
        let token = try engine.approve(.sign(assertionRequest), now: now)
        let assertion = try engine.sign(assertionRequest, approval: token, now: now)
        expect(.approvalMismatch) { _ = try assertion.webAuthnJSON(clientDataJSON: raw) }
        XCTAssertEqual(try responseJSON(assertion.webAuthnJSON())["clientDataJSON"] as? String, "")
    }

    func testVerifierRejectsWrongKeyRPFlagsHashAndSignature() throws {
        var engine = try MockPasskeyEngine()
        let registration = try create(&engine, createRequest())
        let request = signRequest(id: registration.credential.id)
        let token = try engine.approve(.sign(request), now: now)
        let response = try engine.sign(request, approval: token, now: now)
        expect(.verificationFailed) { try response.verify(publicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation) }
        for field in ["rp", "flags", "hash", "signature"] {
            var auth = response.authenticatorData
            if field == "flags" { auth[32] = 0x1d }
            let changed = MockAssertionResponse(credentialID: response.credentialID, userHandle: response.userHandle,
                rpID: field == "rp" ? "localhost" : response.rpID, authenticatorData: auth,
                signatureDER: field == "signature" ? Data(repeating: 0, count: 64) : response.signatureDER,
                clientDataHash: field == "hash" ? Data(repeating: 7, count: 32) : response.clientDataHash)
            expect(.verificationFailed) { try changed.verify(publicKeyX963: registration.publicKeyX963) }
        }
    }

    func testBoundedApprovalAndReplayJournalsDoNotSilentlyEvictAcceptedRequests() throws {
        var engine = try MockPasskeyEngine()
        let first = createRequest()
        _ = try engine.approve(.create(first), now: now)
        expect(.approvalPending) { _ = try engine.approve(.create(first), now: now) }
        for _ in 1..<64 { _ = try engine.approve(.create(createRequest()), now: now) }
        expect(.capacity) { _ = try engine.approve(.create(createRequest()), now: now) }
        var full = MockPasskeyState()
        full.consumedRequests = (0..<MockPasskeyEngine.maximumConsumedRequests).map { _ in
            MockConsumedRequest(requestID: UUID(), operationDigest: suppliedHash, consumedAt: now, outcome: .completed)
        }
        var restored = try MockPasskeyEngine(state: full)
        expect(.capacity) { _ = try restored.approve(.create(createRequest()), now: now) }
        XCTAssertEqual(restored.state.consumedRequests.count, MockPasskeyEngine.maximumConsumedRequests)
    }

    func testPersistenceRoundTripAndDescriptionsNeverExposeEncodedPrivateKey() throws {
        var engine = try MockPasskeyEngine()
        let response = try create(&engine, createRequest())
        let bytes = try JSONEncoder().encode(engine.state)
        let restored = try MockPasskeyEngine(state: JSONDecoder().decode(MockPasskeyState.self, from: bytes))
        XCTAssertEqual(restored.credentials[0].publicKeyX963, response.publicKeyX963)
        let privateValue = response.credential.mockPrivateKeyRawRepresentation.base64EncodedString()
        XCTAssertFalse(String(describing: response.credential).contains(privateValue))
        XCTAssertFalse(String(describing: engine.state).contains(privateValue))
        XCTAssertTrue(String(describing: engine.state).contains("redacted"))
    }

    func testPublicInteropFixtureFromActualMockEngine() throws {
        var engine = try MockPasskeyEngine()
        let registrationChallenge = Data((0..<32).map { UInt8($0 + 1) }).base64URLEncodedString()
        let assertionChallenge = Data((0..<32).map { UInt8($0 + 99) }).base64URLEncodedString()
        func collected(type: String, challenge: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": type, "challenge": challenge,
                "origin": "https://swiftkey.mock", "crossOrigin": false], options: [.sortedKeys])
        }
        let registrationData = try collected(type: "webauthn.create", challenge: registrationChallenge)
        let assertionData = try collected(type: "webauthn.get", challenge: assertionChallenge)
        let registration = try create(&engine, createRequest(clientHash: Data(SHA256.hash(data: registrationData))))
        let request = signRequest(clientHash: Data(SHA256.hash(data: assertionData)), id: registration.credential.id)
        let token = try engine.approve(.sign(request), now: now)
        let assertion = try engine.sign(request, approval: token, now: now)
        XCTAssertTrue(try verifyWithSecurity(publicKey: registration.publicKeyX963,
            payload: assertion.authenticatorData + Data(SHA256.hash(data: assertionData)), signature: assertion.signatureDER))
        let fixture: [String: Any] = ["source": "SwiftKey iOS mock software authenticator; simulated user verification only",
            "rpId": "swiftkey.mock", "origin": "https://swiftkey.mock", "userHandle": user.base64URLEncodedString(),
            "registrationChallenge": registrationChallenge, "assertionChallenge": assertionChallenge,
            "registration": try JSONSerialization.jsonObject(with: registration.webAuthnJSON(clientDataJSON: registrationData)),
            "assertion": try JSONSerialization.jsonObject(with: assertion.webAuthnJSON(clientDataJSON: assertionData))]
        let bytes = try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys, .prettyPrinted])
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("mockPrivateKeyRawRepresentation"))
        if let path = ProcessInfo.processInfo.environment["SWIFTKEY_IOS_MOCK_FIXTURE"] {
            XCTAssertTrue(path.hasPrefix("/tmp/"))
            guard path.hasPrefix("/tmp/") else { return }
            try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func createRequest(rpID: String = "swiftkey.mock", handle: Data? = nil, clientHash: Data? = nil,
                               algorithms: [Int] = [-7], excluded: [Data] = []) -> MockCreatePasskeyRequest {
        MockCreatePasskeyRequest(rpID: rpID, userHandle: handle ?? user, userName: "alice@swiftkey.mock",
            displayName: "Alice Mock", clientDataHash: clientHash ?? suppliedHash, algorithms: algorithms, excludedCredentialIDs: excluded)
    }
    private func signRequest(rpID: String = "swiftkey.mock", clientHash: Data? = nil, id: Data? = nil) -> MockSignPasskeyRequest {
        MockSignPasskeyRequest(rpID: rpID, clientDataHash: clientHash ?? suppliedHash, credentialID: id)
    }
    private func create(_ engine: inout MockPasskeyEngine, _ request: MockCreatePasskeyRequest) throws -> MockRegistrationResponse {
        let token = try engine.approve(.create(request), now: now)
        return try engine.create(request, approval: token, now: now)
    }
    private func expect(_ expected: MockPasskeyError, file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? MockPasskeyError, expected, file: file, line: line)
        }
    }
    private func responseJSON(_ bytes: Data) throws -> [String: Any] {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        return try XCTUnwrap(object["response"] as? [String: Any])
    }
    private func verifyWithSecurity(publicKey: Data, payload: Data, signature: Data) throws -> Bool {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: 256]
        let key = try XCTUnwrap(SecKeyCreateWithData(publicKey as CFData, attributes as CFDictionary, &error))
        return SecKeyVerifySignature(key, .ecdsaSignatureMessageX962SHA256, payload as CFData, signature as CFData, &error)
    }
}

/// Test-only CBOR decoder independent of the production encoder.
private struct CBORDecoder {
    enum Key: Hashable { case integer(Int), text(String) }
    indirect enum Value {
        case number(Int), string(String), data(Data), dictionary([Key: Value])
        func map() throws -> [Key: Value] { guard case .dictionary(let value) = self else { throw Failure.shape }; return value }
        func bytes() throws -> Data { guard case .data(let value) = self else { throw Failure.shape }; return value }
        func text() throws -> String { guard case .string(let value) = self else { throw Failure.shape }; return value }
        func integer() throws -> Int { guard case .number(let value) = self else { throw Failure.shape }; return value }
    }
    enum Failure: Error { case shape, truncated, duplicate, trailing }
    let data: Data
    var position = 0
    init(_ data: Data) { self.data = data }
    mutating func complete() throws -> Value {
        let result = try value()
        guard position == data.count else { throw Failure.trailing }
        return result
    }
    private mutating func byte() throws -> UInt8 {
        guard position < data.count else { throw Failure.truncated }
        defer { position += 1 }; return data[position]
    }
    private mutating func value() throws -> Value {
        let header = try byte(); let major = header >> 5; let extra = header & 31
        let count: Int
        switch extra {
        case 0..<24: count = Int(extra)
        case 24: count = Int(try byte())
        case 25: count = (Int(try byte()) << 8) | Int(try byte())
        default: throw Failure.shape
        }
        switch major {
        case 0: return .number(count)
        case 1: return .number(-1 - count)
        case 2, 3:
            guard position + count <= data.count else { throw Failure.truncated }
            let bytes = data.subdata(in: position..<(position + count)); position += count
            if major == 2 { return .data(bytes) }
            guard let string = String(data: bytes, encoding: .utf8) else { throw Failure.shape }
            return .string(string)
        case 5:
            var dictionary: [Key: Value] = [:]
            for _ in 0..<count {
                let key: Key
                switch try value() { case .number(let value): key = .integer(value); case .string(let value): key = .text(value); default: throw Failure.shape }
                guard dictionary[key] == nil else { throw Failure.duplicate }
                dictionary[key] = try value()
            }
            return .dictionary(dictionary)
        default: throw Failure.shape
        }
    }
}
