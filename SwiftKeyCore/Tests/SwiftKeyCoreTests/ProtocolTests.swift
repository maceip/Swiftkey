import Foundation
import Testing
@testable import SwiftKeyCore

private let nonce = Data(0..<32)
private let account = "acct-1"
private let device = "device-1"
private let audience = "swiftkey.local"
private let domain = "swiftkey.workload"

private func fixedKey(_ scalar: UInt8 = 1) throws -> SoftwareSigningKey {
    try SoftwareSigningKey(rawRepresentation: Data(repeating: 0, count: 31) + Data([scalar]))
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

private func credential(_ delegation: EpochDelegation,
                        root: SoftwareSigningKey, server: SoftwareSigningKey) throws -> EpochCredential {
    let challenge = ChallengeEnvelope(accountID: delegation.accountID, deviceID: delegation.deviceID,
                                      operation: .issueEpoch, sequence: 7, nonce: nonce,
                                      expiresAt: try Epoch.bounds(for: delegation.epoch).start + 120,
                                      payloadHash: ProtocolCrypto.sha256(try delegation.canonicalBytes()))
    let authorization = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge,
                                          signature: try root.sign(message: challenge.canonicalBytes()))
    let unsigned = EpochCredential(delegation: delegation, authorization: authorization, serverSignature: Data())
    return EpochCredential(delegation: delegation, authorization: authorization,
                           serverSignature: try server.sign(message: unsigned.unsignedCanonicalBytes()))
}

private func changeJSON<T: Codable>(_ value: T, field: String, to replacement: Any) throws -> T {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    object[field] = replacement
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func fixedCanonicalVectorsAndHashes() throws {
    let key = try fixedKey()
    let vectors = try JSONDecoder().decode([String: [String: String]].self, from: fixture("canonical-v1.json"))
    let challenge = ChallengeEnvelope(accountID: account, deviceID: device, operation: .issueEpoch,
                                      sequence: 7, nonce: nonce, expiresAt: 28_800,
                                      payloadHash: ProtocolCrypto.sha256(Data("payload".utf8)))
    let delegation = EpochDelegation(accountID: account, deviceID: device, epoch: 1, publicKey: key.publicKey)
    let workload = WorkloadMessage(domain: domain, audience: audience, accountID: account, deviceID: device,
                                   epoch: 1, nonce: nonce, payload: Data("hello".utf8))
    for (name, bytes) in [("challenge", try challenge.canonicalBytes()),
                          ("delegation", try delegation.canonicalBytes()),
                          ("workload", try workload.canonicalBytes())] {
        #expect(hex(bytes) == vectors[name]?["hex"])
        #expect(hex(ProtocolCrypto.sha256(bytes)) == vectors[name]?["sha256"])
    }
}

@Test func fieldFramingAndUnicodeNormalization() throws {
    var first = try CanonicalEncoder(domain: "test")
    try first.append("a"); try first.append("bc")
    var second = try CanonicalEncoder(domain: "test")
    try second.append("ab"); try second.append("c")
    #expect(first.data != second.data)
    var composed = try CanonicalEncoder(domain: "test")
    try composed.append("é")
    var decomposed = try CanonicalEncoder(domain: "test")
    try decomposed.append("e\u{301}")
    #expect(composed.data == decomposed.data)
    var integer = try CanonicalEncoder(domain: "test")
    integer.append(UInt64(0x0102030405060708))
    #expect(integer.data.suffix(8) == Data([1, 2, 3, 4, 5, 6, 7, 8]))
    var optionalNil = try CanonicalEncoder(domain: "test")
    try optionalNil.appendOptional(nil)
    var optionalEmpty = try CanonicalEncoder(domain: "test")
    try optionalEmpty.appendOptional(Data())
    #expect(optionalNil.data != optionalEmpty.data)
}

@Test func jsonIsTransportNotSignedRepresentation() throws {
    let message = WorkloadMessage(domain: domain, audience: audience, accountID: account, deviceID: device,
                                  epoch: 1, nonce: nonce, payload: Data([0, 255, 128]))
    let encoded = try JSONEncoder().encode(message)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(json["payload"] as? String == "AP+A")
    #expect(json["nonce"] as? String == nonce.base64EncodedString())
    #expect(try JSONDecoder().decode(WorkloadMessage.self, from: encoded) == message)
    #expect(encoded != (try message.canonicalBytes()))
}

@Test func independentOpenSSLSignatureFixture() throws {
    let message = try fixture("openssl-message.bin")
    let signature = try fixture("openssl-signature.der")
    let key = try fixture("openssl-public-x963.bin")
    #expect(ProtocolCrypto.verify(signature: signature, message: message, publicKey: key))
    #expect(ProtocolCrypto.verify(signature: signature,
                                  sha256Digest: try PrehashedSHA256(ProtocolCrypto.sha256(message)), publicKey: key))
    #expect(!ProtocolCrypto.verify(signature: signature, message: message + Data([0]), publicKey: key))
    #expect(!ProtocolCrypto.verify(signature: signature + Data([0]), message: message, publicKey: key))
    #expect(!ProtocolCrypto.verify(signature: signature, message: message, publicKey: Data(key.dropFirst())))
}

@Test func rawMessageAndDigestSigningCannotAccidentallyAgreeAfterDoubleHash() throws {
    let key = try fixedKey()
    let message = Data("raw canonical message".utf8)
    let digest = ProtocolCrypto.sha256(message)
    let rawSignature = try key.sign(message: message)
    let digestSignature = try key.sign(sha256Digest: PrehashedSHA256(digest))
    #expect(ProtocolCrypto.verify(signature: rawSignature, message: message, publicKey: key.publicKey))
    #expect(ProtocolCrypto.verify(signature: digestSignature, message: message, publicKey: key.publicKey))
    let doubleHashed = try key.sign(message: digest)
    #expect(!ProtocolCrypto.verify(signature: doubleHashed, message: message, publicKey: key.publicKey))
    #expect(throws: ProtocolError.invalidField("sha256Digest")) { try PrehashedSHA256(Data()) }
}

@Test func epochBoundsAreExactAndOverflowFailsClosed() throws {
    #expect(Epoch.number(at: 0) == 0)
    #expect(Epoch.number(at: 14_399) == 0)
    #expect(Epoch.number(at: 14_400) == 1)
    try Epoch.validate(0, now: 0)
    try Epoch.validate(0, now: 14_399)
    try Epoch.validate(1, now: 14_400)
    #expect(throws: ProtocolError.epochNotCurrent) { try Epoch.validate(0, now: 14_400) }
    #expect(throws: ProtocolError.epochNotCurrent) { try Epoch.validate(1, now: 14_399) }
    #expect(throws: ProtocolError.epochOverflow) { try Epoch.bounds(for: UInt64.max) }
}

@Test func challengeExpiryAndEveryFieldIsBoundByHardwareSignature() throws {
    let root = try fixedKey()
    let challenge = ChallengeEnvelope(accountID: account, deviceID: device, operation: .issueEpoch,
                                      sequence: 7, nonce: nonce, expiresAt: 500,
                                      payloadHash: ProtocolCrypto.sha256(Data("payload".utf8)))
    let signature = try root.sign(message: challenge.canonicalBytes())
    try challenge.validate(now: 499)
    #expect(throws: ProtocolError.challengeExpired) { try challenge.validate(now: 500) }
    for (field, value): (String, Any) in [
        ("accountID", "other-account"), ("deviceID", "other-device"), ("operation", "addDevice"),
        ("sequence", 8), ("nonce", Data(repeating: 9, count: 32).base64EncodedString()),
        ("expiresAt", 501), ("payloadHash", Data(repeating: 7, count: 32).base64EncodedString())
    ] {
        let altered = try changeJSON(challenge, field: field, to: value)
        #expect(!ProtocolCrypto.verify(signature: signature, message: try altered.canonicalBytes(), publicKey: root.publicKey))
    }
}

@Test func invalidLengthsAndKeysAreRejected() throws {
    #expect(throws: ProtocolError.invalidPublicKey) { try ProtocolCrypto.validatePublicKey(Data(repeating: 0, count: 65)) }
    var oversized = try CanonicalEncoder(domain: "test")
    #expect(throws: ProtocolError.fieldTooLarge) { try oversized.append(Data(repeating: 0, count: 1_048_577)) }
    let bad = ChallengeEnvelope(accountID: "", deviceID: device, operation: .enroll, sequence: 0,
                                nonce: nonce, expiresAt: 1, payloadHash: Data(repeating: 0, count: 32))
    #expect(throws: ProtocolError.invalidField("accountID")) { try bad.canonicalBytes() }
    let badNonce = WorkloadMessage(domain: domain, audience: audience, accountID: account, deviceID: device,
                                   epoch: 1, nonce: Data([1]), payload: Data())
    #expect(throws: ProtocolError.invalidField("nonce")) { try badNonce.canonicalBytes() }
    let badHash = EpochDelegation(accountID: account, deviceID: device, epoch: 1,
                                  publicKey: try fixedKey().publicKey, previousPublicKeyHash: Data([1]))
    #expect(throws: ProtocolError.invalidField("previousPublicKeyHash")) { try badHash.canonicalBytes() }
}

@Test func credentialValidForEpochAfterConsumedChallengeExpires() throws {
    let root = try fixedKey(1), server = try fixedKey(2), epochKey = try fixedKey(3)
    let delegation = EpochDelegation(accountID: account, deviceID: device, epoch: 1, publicKey: epochKey.publicKey)
    let value = try credential(delegation, root: root, server: server)
    #expect(value.authorization.challenge.expiresAt < 20_000)
    try ProtocolValidation.verifyCredential(value, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                            accountID: account, deviceID: device, now: 20_000)
    for now: UInt64 in [14_399, 28_800] {
        #expect(throws: ProtocolError.epochNotCurrent) {
            try ProtocolValidation.verifyCredential(value, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                                    accountID: account, deviceID: device, now: now)
        }
    }
    #expect(throws: ProtocolError.invalidSignature) {
        try ProtocolValidation.verifyCredential(value, rootPublicKey: root.publicKey, serverPublicKey: root.publicKey,
                                                accountID: account, deviceID: device, now: 20_000)
    }
}

@Test func unsupportedAppleAssertionsNeverFallBackToGenericECDSA() throws {
    let root = try fixedKey()
    let challenge = ChallengeEnvelope(accountID: account, deviceID: device, operation: .issueEpoch,
                                      sequence: 0, nonce: nonce, expiresAt: 500, payloadHash: Data(repeating: 0, count: 32))
    let authorization = RootAuthorization(kind: .appleAppAttest, challenge: challenge,
                                          signature: try root.sign(message: challenge.canonicalBytes()))
    #expect(throws: ProtocolError.unsupportedAuthorization) {
        try ProtocolValidation.verifyAuthorization(authorization, publicKey: root.publicKey, now: 499)
    }
}

@Test func credentialRejectsDelegationOrRootAuthorizationTampering() throws {
    let root = try fixedKey(1), server = try fixedKey(2), leaf = try fixedKey(3)
    let delegation = EpochDelegation(accountID: account, deviceID: device, epoch: 1, publicKey: leaf.publicKey)
    let value = try credential(delegation, root: root, server: server)
    let swapped = EpochCredential(delegation: EpochDelegation(accountID: account, deviceID: device, epoch: 1,
                                                             publicKey: root.publicKey),
                                  authorization: value.authorization, serverSignature: value.serverSignature)
    #expect(throws: ProtocolError.bindingMismatch) {
        try ProtocolValidation.verifyCredential(swapped, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                                accountID: account, deviceID: device, now: 20_000)
    }
    let changed = RootAuthorization(kind: .androidStrongBoxP256, challenge: value.authorization.challenge, signature: Data([1]))
    let badRoot = EpochCredential(delegation: delegation, authorization: changed, serverSignature: value.serverSignature)
    #expect(throws: ProtocolError.invalidSignature) {
        try ProtocolValidation.verifyCredential(badRoot, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                                accountID: account, deviceID: device, now: 20_000)
    }
}

@Test func membershipAndRecoveryBindTheExactCandidateAndLostRoot() throws {
    let key = try fixedKey()
    let add = DeviceMembershipChange(accountID: account, deviceID: device, publicKey: key.publicKey, operation: .addDevice)
    let recover = RecoveryChange(accountID: account, lostDeviceID: "lost", replacementDeviceID: device, publicKey: key.publicKey)
    #expect(try add.canonicalBytes() != recover.canonicalBytes())
    let differentLost = RecoveryChange(accountID: account, lostDeviceID: "another-lost", replacementDeviceID: device, publicKey: key.publicKey)
    #expect(try recover.canonicalBytes() != differentLost.canonicalBytes())
    #expect(throws: ProtocolError.bindingMismatch) {
        try RecoveryChange(accountID: account, lostDeviceID: device, replacementDeviceID: device, publicKey: key.publicKey).canonicalBytes()
    }
    #expect(throws: ProtocolError.invalidField("publicKey")) {
        try DeviceMembershipChange(accountID: account, deviceID: device, publicKey: key.publicKey, operation: .revokeDevice).canonicalBytes()
    }
}

@Test func workloadTamperingAndAudienceSubstitutionFail() throws {
    let root = try fixedKey(1), server = try fixedKey(2), leaf = try fixedKey(3)
    let delegation = EpochDelegation(accountID: account, deviceID: device, epoch: 1, publicKey: leaf.publicKey)
    let cert = try credential(delegation, root: root, server: server)
    let message = WorkloadMessage(domain: domain, audience: audience, accountID: account, deviceID: device,
                                  epoch: 1, nonce: nonce, payload: Data("hello".utf8))
    let signature = try leaf.sign(message: message.canonicalBytes())
    func validate(_ candidate: WorkloadMessage) throws {
        let authenticated = AuthenticatedWorkload(credential: cert, workload: SignedWorkload(message: candidate, signature: signature))
        try ProtocolValidation.verifyWorkload(authenticated, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                              expectedDomain: domain, expectedAudience: audience,
                                              accountID: account, deviceID: device, now: 20_000)
    }
    try validate(message)
    for (field, value): (String, Any) in [
        ("domain", "other"), ("audience", "other"), ("accountID", "other"), ("deviceID", "other"),
        ("epoch", 2), ("nonce", Data(repeating: 9, count: 32).base64EncodedString()),
        ("payload", Data("tampered".utf8).base64EncodedString())
    ] {
        let altered = try changeJSON(message, field: field, to: value)
        #expect(throws: (any Error).self) { try validate(altered) }
    }
    let unauthorizedAudience = WorkloadMessage(domain: domain, audience: "other", accountID: account,
                                               deviceID: device, epoch: 1, nonce: nonce, payload: Data())
    let validButWrongAudience = SignedWorkload(message: unauthorizedAudience,
                                              signature: try leaf.sign(message: unauthorizedAudience.canonicalBytes()))
    #expect(throws: ProtocolError.bindingMismatch) {
        try ProtocolValidation.verifyWorkload(AuthenticatedWorkload(credential: cert, workload: validButWrongAudience),
                                              rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                              expectedDomain: domain, expectedAudience: "other", accountID: account,
                                              deviceID: device, now: 20_000)
    }
}

@Test func lazyRotationRequiresFreshCredentialAndLinksPreviousKey() async throws {
    let root = try fixedKey(1), server = try fixedKey(2)
    let manager = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    #expect(await manager.snapshot() == nil)
    let first = try await manager.prepareDelegation(now: 14_400)
    #expect(try await manager.prepareDelegation(now: 28_799) == first)
    await #expect(throws: ProtocolError.credentialRequired) {
        try await manager.signWorkload(domain: domain, audience: audience, payload: Data(), nonce: nonce, now: 14_400)
    }
    let cert = try credential(first, root: root, server: server)
    try await manager.acceptCredential(cert, now: 14_400)
    let signed = try await manager.signWorkload(domain: domain, audience: audience, payload: Data([1]), nonce: nonce, now: 28_799)
    try ProtocolValidation.verifyWorkload(signed, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey,
                                          expectedDomain: domain, expectedAudience: audience, accountID: account,
                                          deviceID: device, now: 28_799)
    let next = try await manager.prepareDelegation(now: 28_800)
    #expect(next.epoch == 2)
    #expect(next.publicKey != first.publicKey)
    #expect(next.previousPublicKeyHash == ProtocolCrypto.sha256(first.publicKey))
    #expect(try await manager.currentCredential(now: 28_800) == nil)
    await #expect(throws: ProtocolError.bindingMismatch) { try await manager.acceptCredential(cert, now: 28_800) }
    await #expect(throws: ProtocolError.epochNotCurrent) { try await manager.prepareDelegation(now: 14_400) }
}

@Test func snapshotRestoresSameUnexpiredKeyAndCredential() async throws {
    let root = try fixedKey(1), server = try fixedKey(2)
    let first = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    let delegation = try await first.prepareDelegation(now: 14_400)
    let cert = try credential(delegation, root: root, server: server)
    try await first.acceptCredential(cert, now: 14_400)
    let snapshot = try #require(await first.snapshot())
    let restoredSnapshot = try JSONDecoder().decode(EpochManagerSnapshot.self, from: JSONEncoder().encode(snapshot))
    let second = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    try await second.restore(restoredSnapshot, now: 28_799)
    #expect(try await second.prepareDelegation(now: 28_799) == delegation)
    #expect(try await second.currentCredential(now: 28_799) == cert)
    let signed = try await second.signWorkload(domain: domain, audience: audience, payload: Data(), nonce: nonce, now: 28_799)
    #expect(ProtocolCrypto.verify(signature: signed.workload.signature,
                                  message: try signed.workload.message.canonicalBytes(), publicKey: delegation.publicKey))
    let transport = try JSONEncoder().encode(VerifyWorkloadRequest(credential: signed.credential, workload: signed.workload))
    #expect(!String(decoding: transport, as: UTF8.self).contains("privateKey"))
}

@Test func expiredSnapshotRotatesAndFutureOrChangedPinsFailClosed() async throws {
    let root = try fixedKey(1), server = try fixedKey(2)
    let original = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    let old = try await original.prepareDelegation(now: 14_400)
    try await original.acceptCredential(credential(old, root: root, server: server), now: 14_400)
    let snapshot = try #require(await original.snapshot())
    let restored = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    try await restored.restore(snapshot, now: 28_800)
    let next = try await restored.prepareDelegation(now: 28_800)
    #expect(next.publicKey != old.publicKey)
    #expect(next.previousPublicKeyHash == ProtocolCrypto.sha256(old.publicKey))
    #expect(try await restored.currentCredential(now: 28_800) == nil)
    let beforeEpoch = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: server.publicKey)
    await #expect(throws: ProtocolError.epochNotCurrent) { try await beforeEpoch.restore(snapshot, now: 14_399) }
    #expect(await beforeEpoch.snapshot() == nil)
    let changedPin = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey, serverPublicKey: root.publicKey)
    await #expect(throws: ProtocolError.bindingMismatch) { try await changedPin.restore(snapshot, now: 20_000) }
    let changedAudience = EpochManager(accountID: account, deviceID: device, rootPublicKey: root.publicKey,
                                       serverPublicKey: server.publicKey, audience: "other")
    await #expect(throws: ProtocolError.bindingMismatch) { try await changedAudience.restore(snapshot, now: 20_000) }
    let changedPrivate = EpochManagerSnapshot(delegation: snapshot.delegation, privateKey: root.rawRepresentation,
                                              credential: snapshot.credential, rootPublicKeyHash: snapshot.rootPublicKeyHash,
                                              serverPublicKeyHash: snapshot.serverPublicKeyHash,
                                              previousPublicKeyHash: snapshot.previousPublicKeyHash)
    await #expect(throws: ProtocolError.bindingMismatch) { try await beforeEpoch.restore(changedPrivate, now: 20_000) }
    #expect(await beforeEpoch.snapshot() == nil)
}
