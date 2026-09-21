import Foundation
import Testing
import SwiftKeyCore
import CSQLite
@testable import SwiftKeyAuthority

/// Test-only SQLite inspection. The HTTP/admin model never exposes this blob.
private func storedSnapshot(_ directory: URL) throws -> Data {
    guard let resolved = realpath(directory.path, nil) else { throw AuthorityError.rejected("Cannot resolve fixture directory") }
    let databasePath = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent("authority.sqlite3").path
    free(resolved)
    var db: OpaquePointer?
    guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK, let db else { throw AuthorityError.rejected("Cannot open fixture database") }
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT data FROM authority_snapshot WHERE singleton=1", -1, &statement, nil) == SQLITE_OK, let statement else { throw AuthorityError.rejected("Cannot inspect fixture snapshot") }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw AuthorityError.rejected("Missing fixture snapshot") }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
}

// Fixture attestation exists only in this test target. The production executable
// always constructs AndroidAttestationVerifier and has no fixture switch.
private actor FixtureVerifier: EnrollmentVerifier {
    private var revoked = false
    private var revokedKeys: Set<Data> = []
    private var pauseKey: Data?
    private var entered = false
    private var started: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    func revokeTrust() { revoked = true }
    func revokeTrust(for key: Data) { revokedKeys.insert(key) }
    func pauseVerification(for key: Data) { pauseKey = key; entered = false }
    func waitUntilStarted() async {
        if entered { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
    private func pauseIfRequested(_ key: Data) async {
        guard pauseKey == key else { return }
        pauseKey = nil; entered = true
        started?.resume(); started = nil
        await withCheckedContinuation { paused = $0 }
    }
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws {
        await pauseIfRequested(identity.publicKey)
        if revoked || revokedKeys.contains(identity.publicKey) { throw AuthorityError.protocolFailure(code: "attestationRejected", message: "Fixture trust revoked") }
    }
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        guard let key = certificates.first, certificates.count == 1 else { throw AuthorityError.rejected("Invalid test fixture") }
        try ProtocolCrypto.validatePublicKey(key)
        await pauseIfRequested(key)
        return VerifiedAndroidIdentity(publicKey: key, certificateSHA256: ProtocolCrypto.sha256(key), packageName: "test.fixture", packageVersion: 1)
    }
}

/// Lets a test replace an invitation while its original attestation awaits.
private actor PausingFixtureVerifier: EnrollmentVerifier {
    private var shouldPause = true
    private var entered = false
    private var started: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if entered { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
    func revalidate(_ identity: VerifiedAndroidIdentity, now: UInt64) async throws {}
    func verify(certificates: [Data], challenge: Data, now: UInt64) async throws -> VerifiedAndroidIdentity {
        guard let key = certificates.first, certificates.count == 1 else { throw AuthorityError.rejected("Invalid test fixture") }
        try ProtocolCrypto.validatePublicKey(key)
        if shouldPause {
            shouldPause = false
            entered = true
            started?.resume(); started = nil
            await withCheckedContinuation { paused = $0 }
        }
        return VerifiedAndroidIdentity(publicKey: key, certificateSHA256: ProtocolCrypto.sha256(key), packageName: "test.fixture", packageVersion: 1)
    }
}
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1_800_000_100
    func now() -> UInt64 { lock.withLock { value } }
    func advance(_ seconds: UInt64) { lock.withLock { value += seconds } }
}
private struct Fixture {
    let authority: Authority
    let root: SoftwareSigningKey
    let enrollment: EnrollResponse
    let bootstrap: BootstrapChallengeResponse
    let directory: URL
    let clock: TestClock
    let verifier: FixtureVerifier
    let token = String(repeating: "fixture-only-secret", count: 3)
    static func create() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-authority-test-" + UUID().uuidString)
        let clock = TestClock()
        let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
        let token = String(repeating: "fixture-only-secret", count: 3)
        let verifier = FixtureVerifier()
        let authority = try Authority(configuration: config, bootstrapToken: token, verifier: verifier, clock: { clock.now() })
        let root = SoftwareSigningKey()
        let bootstrap = try await authority.bootstrapChallenge(token: token)
        let request = EnrollRequest(challenge: bootstrap.challenge, certificates: [root.publicKey], proof: try root.sign(message: bootstrap.challenge.canonicalBytes()))
        let enrollment = try await authority.bootstrapEnroll(request, token: token)
        return Fixture(authority: authority, root: root, enrollment: enrollment, bootstrap: bootstrap, directory: directory, clock: clock, verifier: verifier)
    }
    func authorization(_ operation: SwiftKeyCore.Operation, payload: Data, deviceID: String? = nil, key: SoftwareSigningKey? = nil) async throws -> RootAuthorization {
        let challenge = try await authority.challenge(ChallengeRequest(accountID: enrollment.accountID, deviceID: deviceID ?? enrollment.deviceID, operation: operation, payloadHash: ProtocolCrypto.sha256(payload)))
        return RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge, signature: try (key ?? root).sign(message: challenge.canonicalBytes()))
    }
    func issue(key: SoftwareSigningKey = SoftwareSigningKey(), previous: Data? = nil, deviceID: String? = nil, rootKey: SoftwareSigningKey? = nil) async throws -> (EpochCredential, SoftwareSigningKey) {
        let delegation = EpochDelegation(accountID: enrollment.accountID, deviceID: deviceID ?? enrollment.deviceID, epoch: clock.now() / Epoch.duration, publicKey: key.publicKey, previousPublicKeyHash: previous)
        let auth = try await authorization(.issueEpoch, payload: delegation.canonicalBytes(), deviceID: deviceID, key: rootKey)
        return (try await authority.issueEpoch(IssueEpochRequest(delegation: delegation, authorization: auth)), key)
    }
    func workload(_ credential: EpochCredential, key: SoftwareSigningKey, nonce: Data = Data(repeating: 42, count: 32)) throws -> VerifyWorkloadRequest {
        let message = WorkloadMessage(domain: "swiftkey.demo.echo.v1", audience: "swiftkey.local", accountID: credential.delegation.accountID, deviceID: credential.delegation.deviceID, epoch: credential.delegation.epoch, nonce: nonce, payload: Data("hello".utf8))
        return VerifyWorkloadRequest(credential: credential, workload: SignedWorkload(message: message, signature: try key.sign(message: message.canonicalBytes())))
    }
    func candidate(key: SoftwareSigningKey = SoftwareSigningKey()) async throws -> (PairingCandidate, SoftwareSigningKey) {
        let pending = try await authority.pairingChallenge(PairingChallengeRequest(accountID: enrollment.accountID))
        let candidate = try await authority.pairingEnroll(EnrollRequest(challenge: pending.challenge, certificates: [key.publicKey], proof: try key.sign(message: pending.challenge.canonicalBytes())))
        return (candidate, key)
    }
    func approve(_ candidate: PairingCandidate) async throws {
        let change = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: candidate.publicKey, operation: .addDevice)
        let auth = try await authorization(.addDevice, payload: change.canonicalBytes())
        _ = try await authority.approvePairing(MembershipRequest(change: change, authorization: auth))
    }
}

@Test func bootstrapRetryRequiresSameKeyAndFreshValidProof() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let retried = try await f.authority.bootstrapEnroll(EnrollRequest(challenge: f.bootstrap.challenge, certificates: [f.root.publicKey], proof: try f.root.sign(message: f.bootstrap.challenge.canonicalBytes())), token: f.token)
    #expect(retried.deviceID == f.enrollment.deviceID)
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapChallenge(token: f.token) }
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(EnrollRequest(challenge: f.bootstrap.challenge, certificates: [f.root.publicKey], proof: Data()), token: f.token) }
    let other = SoftwareSigningKey()
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(EnrollRequest(challenge: f.bootstrap.challenge, certificates: [other.publicKey], proof: try other.sign(message: f.bootstrap.challenge.canonicalBytes())), token: f.token) }
}

@Test func lostEpochResponseRetriesWithFreshAuthorizationAndSameLeaf() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (first, _) = try await f.issue()
    let auth = try await f.authorization(.issueEpoch, payload: first.delegation.canonicalBytes())
    let repeated = try await f.authority.issueEpoch(IssueEpochRequest(delegation: first.delegation, authorization: auth))
    #expect(repeated == first)
    await #expect(throws: (any Error).self) { try await f.authority.issueEpoch(IssueEpochRequest(delegation: first.delegation, authorization: auth)) }
    await #expect(throws: (any Error).self) { try await f.issue() }
    f.clock.advance(Epoch.duration)
    await #expect(throws: (any Error).self) { try await f.issue() }
    let (next, _) = try await f.issue(previous: ProtocolCrypto.sha256(first.delegation.publicKey))
    #expect(next.delegation.epoch == first.delegation.epoch + 1)
}

@Test func concurrentWorkloadConsumesExactlyOnceAndInvalidSignatureDoesNotConsume() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, key) = try await f.issue()
    let request = try f.workload(credential, key: key)
    let bad = VerifyWorkloadRequest(credential: credential, workload: SignedWorkload(message: request.workload.message, signature: Data()))
    do { _ = try await f.authority.verifyWorkload(bad); Issue.record("Invalid signature accepted") }
    catch let error as AuthorityError { #expect(error.code == "invalidSignature") }
    let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
        for _ in 0..<20 { group.addTask { (try? await f.authority.verifyWorkload(request)) != nil } }
        var count = 0; for await valid in group { if valid { count += 1 } }; return count
    }
    #expect(accepted == 1)
    do { _ = try await f.authority.verifyWorkload(request); Issue.record("Replay accepted") }
    catch let error as AuthorityError { #expect(error.code == "replayedWorkload") }
    let persisted = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(persisted.workloadNonces.count == 1)
    #expect(persisted.issuedEpochCredentials[f.enrollment.deviceID] == credential)
}

@Test func pairingBindsExactKeyAndConfirmationRequiresApproval() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (candidate, key) = try await f.candidate()
    let confirmation = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: candidate.publicKey, operation: .enroll)
    await #expect(throws: (any Error).self) { try await f.authorization(.enroll, payload: confirmation.canonicalBytes(), deviceID: candidate.deviceID, key: key) }
    let mismatched = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: SoftwareSigningKey().publicKey, operation: .addDevice)
    let badAuth = try await f.authorization(.addDevice, payload: mismatched.canonicalBytes())
    await #expect(throws: (any Error).self) { try await f.authority.approvePairing(MembershipRequest(change: mismatched, authorization: badAuth)) }
    try await f.approve(candidate)
    let auth = try await f.authorization(.enroll, payload: confirmation.canonicalBytes(), deviceID: candidate.deviceID, key: key)
    let response = try await f.authority.confirmPairing(MembershipRequest(change: confirmation, authorization: auth))
    #expect(response.publicKey == candidate.publicKey)
    #expect(response.serverPublicKey == f.enrollment.serverPublicKey)
}

@Test func pairingCandidateRetryIsIdempotentAndCannotReplaceItsHardwareIdentity() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let invitation = try await f.authority.pairingChallenge(PairingChallengeRequest(accountID: f.enrollment.accountID))
    let key = SoftwareSigningKey()
    let request = EnrollRequest(challenge: invitation.challenge, certificates: [key.publicKey], proof: try key.sign(message: invitation.challenge.canonicalBytes()))
    let candidate = try await f.authority.pairingEnroll(request)
    let head = try await f.authority.status().ledgerHead.sequence
    #expect(try await f.authority.pairingEnroll(request).publicKey == candidate.publicKey)
    let other = SoftwareSigningKey()
    let replacement = EnrollRequest(challenge: invitation.challenge, certificates: [other.publicKey], proof: try other.sign(message: invitation.challenge.canonicalBytes()))
    await #expect(throws: (any Error).self) { try await f.authority.pairingEnroll(replacement) }
    await #expect(throws: (any Error).self) {
        try await f.authority.pairingEnroll(EnrollRequest(challenge: invitation.challenge, certificates: [key.publicKey], proof: Data()))
    }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
    try await f.approve(candidate)
    #expect(try await f.authority.devices(accountID: candidate.accountID).devices.contains { $0.deviceID == candidate.deviceID && $0.publicKey == key.publicKey })
}

@Test func concurrentPairingAttestationCannotReplaceTheCommittedCandidate() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let invitation = try await f.authority.pairingChallenge(PairingChallengeRequest(accountID: f.enrollment.accountID))
    let slowKey = SoftwareSigningKey(), winningKey = SoftwareSigningKey()
    await f.verifier.pauseVerification(for: slowKey.publicKey)
    let slowRequest = EnrollRequest(challenge: invitation.challenge, certificates: [slowKey.publicKey], proof: try slowKey.sign(message: invitation.challenge.canonicalBytes()))
    let inFlight = Task { try await f.authority.pairingEnroll(slowRequest) }
    await f.verifier.waitUntilStarted()
    let winner: PairingCandidate
    do {
        winner = try await f.authority.pairingEnroll(EnrollRequest(challenge: invitation.challenge, certificates: [winningKey.publicKey], proof: try winningKey.sign(message: invitation.challenge.canonicalBytes())))
    } catch { await f.verifier.resume(); _ = await inFlight.result; throw error }
    let head = try await f.authority.status().ledgerHead.sequence
    await f.verifier.resume()
    await #expect(throws: (any Error).self) { try await inFlight.value }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
    try await f.approve(winner)
}

@Test func candidateTrustIsRevalidatedBeforePairingOrRecoveryChangesMembership() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (lost, _) = try await f.candidate(); try await f.approve(lost)
    let (candidate, _) = try await f.candidate()
    let pairing = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: candidate.publicKey, operation: .addDevice)
    let pairingAuth = try await f.authorization(.addDevice, payload: pairing.canonicalBytes())
    let recovery = RecoveryChange(accountID: candidate.accountID, lostDeviceID: lost.deviceID, replacementDeviceID: candidate.deviceID, publicKey: candidate.publicKey)
    let recoveryAuth = try await f.authorization(.recoverDevice, payload: recovery.canonicalBytes())
    let head = try await f.authority.status().ledgerHead.sequence
    await f.verifier.revokeTrust(for: candidate.publicKey)
    do { _ = try await f.authority.approvePairing(MembershipRequest(change: pairing, authorization: pairingAuth)); Issue.record("Revoked candidate trust accepted during pairing") }
    catch let error as AuthorityError { #expect(error.code == "attestationRejected") }
    do { _ = try await f.authority.recover(RecoveryRequest(change: recovery, authorization: recoveryAuth)); Issue.record("Revoked candidate trust accepted during recovery") }
    catch let error as AuthorityError { #expect(error.code == "attestationRejected") }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
    let stored = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(stored.devices[candidate.deviceID] == nil && stored.devices[lost.deviceID]?.revoked == false)
    #expect(stored.candidates[candidate.deviceID] != nil)
    #expect(stored.challenges[pairingAuth.challenge.nonce.base64EncodedString()] != nil)
    #expect(stored.challenges[recoveryAuth.challenge.nonce.base64EncodedString()] != nil)
}

@Test(arguments: [false, true]) func pairingRechecksAuthorizerAfterCandidateTrustSuspends(revokeAuthorizer: Bool) async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (survivor, survivorKey) = try await f.candidate(); try await f.approve(survivor)
    let (candidate, _) = try await f.candidate()
    let change = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: candidate.publicKey, operation: .addDevice)
    let auth = try await f.authorization(.addDevice, payload: change.canonicalBytes())
    await f.verifier.pauseVerification(for: candidate.publicKey)
    let inFlight = Task { try await f.authority.approvePairing(MembershipRequest(change: change, authorization: auth)) }
    await f.verifier.waitUntilStarted()
    do {
        if revokeAuthorizer {
            let revoke = DeviceMembershipChange(accountID: candidate.accountID, deviceID: f.enrollment.deviceID, publicKey: nil, operation: .revokeDevice)
            let revokeAuth = try await f.authorization(.revokeDevice, payload: revoke.canonicalBytes(), deviceID: survivor.deviceID, key: survivorKey)
            _ = try await f.authority.revoke(MembershipRequest(change: revoke, authorization: revokeAuth))
        } else { _ = try await f.issue() }
    } catch { await f.verifier.resume(); _ = await inFlight.result; throw error }
    let head = try await f.authority.status().ledgerHead.sequence
    await f.verifier.resume()
    await #expect(throws: (any Error).self) { try await inFlight.value }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
    let stored = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(stored.devices[candidate.deviceID] == nil && stored.candidates[candidate.deviceID] != nil)
}

@Test func recoveryRechecksLostDeviceAfterCandidateTrustSuspends() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (lost, _) = try await f.candidate(); try await f.approve(lost)
    let (survivor, survivorKey) = try await f.candidate(); try await f.approve(survivor)
    let (candidate, _) = try await f.candidate()
    let change = RecoveryChange(accountID: candidate.accountID, lostDeviceID: lost.deviceID, replacementDeviceID: candidate.deviceID, publicKey: candidate.publicKey)
    let auth = try await f.authorization(.recoverDevice, payload: change.canonicalBytes())
    await f.verifier.pauseVerification(for: candidate.publicKey)
    let inFlight = Task { try await f.authority.recover(RecoveryRequest(change: change, authorization: auth)) }
    await f.verifier.waitUntilStarted()
    do {
        let revoke = DeviceMembershipChange(accountID: candidate.accountID, deviceID: lost.deviceID, publicKey: nil, operation: .revokeDevice)
        let revokeAuth = try await f.authorization(.revokeDevice, payload: revoke.canonicalBytes(), deviceID: survivor.deviceID, key: survivorKey)
        _ = try await f.authority.revoke(MembershipRequest(change: revoke, authorization: revokeAuth))
    } catch { await f.verifier.resume(); _ = await inFlight.result; throw error }
    let head = try await f.authority.status().ledgerHead.sequence
    await f.verifier.resume()
    do { _ = try await inFlight.value; Issue.record("Recovery committed after target was revoked") }
    catch let error as AuthorityError { #expect(error.code == "revokedDevice") }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
    let stored = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(stored.devices[candidate.deviceID] == nil && stored.candidates[candidate.deviceID] != nil)
}

@Test func revocationImmediatelyRejectsPreviouslyValidEpochCredential() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (candidate, key) = try await f.candidate(); try await f.approve(candidate)
    let (credential, leaf) = try await f.issue(deviceID: candidate.deviceID, rootKey: key)
    let request = try f.workload(credential, key: leaf)
    let change = DeviceMembershipChange(accountID: candidate.accountID, deviceID: candidate.deviceID, publicKey: nil, operation: .revokeDevice)
    let auth = try await f.authorization(.revokeDevice, payload: change.canonicalBytes())
    _ = try await f.authority.revoke(MembershipRequest(change: change, authorization: auth))
    do { _ = try await f.authority.verifyWorkload(request); Issue.record("Revoked device accepted") }
    catch let error as AuthorityError { #expect(error.code == "revokedDevice") }
}

@Test func recoveryAtomicallyAddsReplacementAndRevokesLostDevice() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (survivor, survivorKey) = try await f.candidate(); try await f.approve(survivor)
    let (replacement, replacementKey) = try await f.candidate()
    let change = RecoveryChange(accountID: f.enrollment.accountID, lostDeviceID: f.enrollment.deviceID, replacementDeviceID: replacement.deviceID, publicKey: replacement.publicKey)
    let auth = try await f.authorization(.recoverDevice, payload: change.canonicalBytes(), deviceID: survivor.deviceID, key: survivorKey)
    _ = try await f.authority.recover(RecoveryRequest(change: change, authorization: auth))
    await #expect(throws: (any Error).self) { try await f.issue() }
    _ = try await f.issue(deviceID: replacement.deviceID, rootKey: replacementKey)
    let stored = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(stored.devices[f.enrollment.deviceID]?.revoked == true)
    #expect(stored.devices[replacement.deviceID]?.revoked == false)
    #expect(stored.candidates[replacement.deviceID] == nil)
}

@Test func privateStateAndExclusiveProcessLock() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let attrs = try FileManager.default.attributesOfItem(atPath: f.directory.appendingPathComponent("authority.sqlite3").path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(throws: (any Error).self) { try SecureStateFile(directory: f.directory) }
}

@Test func registeredDeviceTrustIsCheckedAgainForWorkloadsAndMutations() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, leaf) = try await f.issue()
    let request = try f.workload(credential, key: leaf)
    let authorization = try await f.authorization(.issueEpoch, payload: credential.delegation.canonicalBytes())
    await f.verifier.revokeTrust()
    do { _ = try await f.authority.verifyWorkload(request); Issue.record("Revoked attestation trust accepted") }
    catch let error as AuthorityError { #expect(error.code == "attestationRejected") }
    await #expect(throws: (any Error).self) { try await f.authority.issueEpoch(IssueEpochRequest(delegation: credential.delegation, authorization: authorization)) }
}

@Test func securityPolicyCannotChangeOnRestart() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-policy-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stored = try storedSnapshot(f.directory)
    func copyState() throws { let store = try LedgerStore(directory: directory); try store.commit(state: stored, events: []) }
    try copyState()
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "another.application", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    #expect(throws: (any Error).self) { try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier()) }
}

@Test func workloadLedgerAndEpochReceiptSurviveRestart() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, key) = try await f.issue()
    let request = try f.workload(credential, key: key)
    _ = try await f.authority.verifyWorkload(request)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-restart-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stored = try storedSnapshot(f.directory)
    func copyState() throws { let store = try LedgerStore(directory: directory); try store.commit(state: stored, events: []) }
    try copyState()
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    let resumed = try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    #expect(await resumed.publicKey == f.enrollment.serverPublicKey)
    do { _ = try await resumed.verifyWorkload(request); Issue.record("Restart forgot nonce ledger") }
    catch let error as AuthorityError { #expect(error.code == "replayedWorkload") }
    let challenge = try await resumed.challenge(ChallengeRequest(accountID: f.enrollment.accountID, deviceID: f.enrollment.deviceID, operation: .issueEpoch, payloadHash: ProtocolCrypto.sha256(try credential.delegation.canonicalBytes())))
    let authorization = RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge, signature: try f.root.sign(message: challenge.canonicalBytes()))
    #expect(try await resumed.issueEpoch(IssueEpochRequest(delegation: credential.delegation, authorization: authorization)) == credential)
}

@Test func accountInvitationsAreIsolatedOneUseAndNeverListedAsSecrets() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let created = try await f.authority.createAccount(CreateAccountRequest(label: "Second account"))
    #expect(created.account.status == "pending")
    #expect(created.account.accountID != f.enrollment.accountID)
    let challenge = try await f.authority.bootstrapChallenge(token: created.enrollmentToken)
    #expect(challenge.challenge.accountID == created.account.accountID)
    let root = SoftwareSigningKey()
    let request = EnrollRequest(challenge: challenge.challenge, certificates: [root.publicKey], proof: try root.sign(message: challenge.challenge.canonicalBytes()))
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(request, token: f.token) }
    let enrollment = try await f.authority.bootstrapEnroll(request, token: created.enrollmentToken)
    #expect(enrollment.accountID == created.account.accountID)
    let repeated = try await f.authority.bootstrapEnroll(request, token: created.enrollmentToken)
    #expect(repeated.publicKey == root.publicKey)
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapChallenge(token: created.enrollmentToken) }
    let other = SoftwareSigningKey()
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(EnrollRequest(challenge: challenge.challenge, certificates: [other.publicKey], proof: try other.sign(message: challenge.challenge.canonicalBytes())), token: created.enrollmentToken) }
    let second = try await f.authority.account(id: enrollment.accountID)
    #expect(second.status == "active" && second.activeDeviceCount == 1)
    #expect(try await f.authority.listAccounts().accounts.count == 2)
    let visible = try await f.authority.ledger(accountID: second.accountID)
    #expect(visible.events.allSatisfy { $0.accountID == second.accountID })
    #expect(visible.events.filter { $0.kind == "device.enrolled" }.count == 1)
    let encoded = String(decoding: try JSONEncoder().encode(visible), as: UTF8.self)
    #expect(!encoded.contains(created.enrollmentToken))
    #expect(!encoded.contains("bootstrapTokenHash") && !encoded.contains("signingKey"))
    await #expect(throws: (any Error).self) { try await f.authority.challenge(ChallengeRequest(accountID: f.enrollment.accountID, deviceID: enrollment.deviceID, operation: .issueEpoch, payloadHash: Data(repeating: 0, count: 32))) }
}

@Test func expiredInvitationCannotGenerateOrEnrollAKey() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let created = try await f.authority.createAccount(CreateAccountRequest(label: "Expiring account"))
    let challenge = try await f.authority.bootstrapChallenge(token: created.enrollmentToken)
    let root = SoftwareSigningKey()
    f.clock.advance(900)
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapChallenge(token: created.enrollmentToken) }
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(EnrollRequest(challenge: challenge.challenge, certificates: [root.publicKey], proof: try root.sign(message: challenge.challenge.canonicalBytes())), token: created.enrollmentToken) }
    #expect(try await f.authority.account(id: created.account.accountID).deviceCount == 0)
}

@Test func reissuedInvitationInvalidatesOldTokenAndChallengeWithoutChangingAccount() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let created = try await f.authority.createAccount(CreateAccountRequest(label: "Replacement invitation"))
    let other = try await f.authority.createAccount(CreateAccountRequest(label: "Independent invitation"))
    let oldChallenge = try await f.authority.bootstrapChallenge(token: created.enrollmentToken)
    let oldKey = SoftwareSigningKey()
    let oldRequest = EnrollRequest(challenge: oldChallenge.challenge, certificates: [oldKey.publicKey], proof: try oldKey.sign(message: oldChallenge.challenge.canonicalBytes()))
    let head = try await f.authority.status().ledgerHead.sequence
    let replacement = try await f.authority.reissueEnrollmentInvitation(accountID: created.account.accountID)
    #expect(replacement.account.accountID == created.account.accountID)
    #expect(replacement.account.label == created.account.label && replacement.account.createdAt == created.account.createdAt)
    #expect(replacement.enrollmentToken != created.enrollmentToken)
    #expect(replacement.expiresAt == f.clock.now() + 900)
    do { _ = try await f.authority.bootstrapChallenge(token: created.enrollmentToken); Issue.record("Replaced token still issued a challenge") }
    catch let error as AuthorityError { #expect(error.code == "unauthorized") }
    do { _ = try await f.authority.bootstrapEnroll(oldRequest, token: created.enrollmentToken); Issue.record("Replaced token still enrolled a device") }
    catch let error as AuthorityError { #expect(error.code == "unauthorized") }
    await #expect(throws: (any Error).self) { try await f.authority.bootstrapEnroll(oldRequest, token: replacement.enrollmentToken) }
    let event = try #require(try await f.authority.ledger(after: head).events.first)
    #expect(event.kind == "enrollment.invited" && event.accountID == created.account.accountID)
    #expect(event.details == ["reason": "reissued", "expiresAt": String(replacement.expiresAt)])
    let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
    #expect(!encoded.contains(created.enrollmentToken) && !encoded.contains(replacement.enrollmentToken))
    let challenge = try await f.authority.bootstrapChallenge(token: replacement.enrollmentToken)
    #expect(challenge.challenge.deviceID != oldChallenge.challenge.deviceID)
    #expect(challenge.challenge.accountID == created.account.accountID)
    #expect(challenge.attestationChallenge != oldChallenge.attestationChallenge)
    let key = SoftwareSigningKey()
    let enrolled = try await f.authority.bootstrapEnroll(EnrollRequest(challenge: challenge.challenge, certificates: [key.publicKey], proof: try key.sign(message: challenge.challenge.canonicalBytes())), token: replacement.enrollmentToken)
    #expect(enrolled.deviceID == challenge.challenge.deviceID && enrolled.publicKey == key.publicKey)
    #expect(try await f.authority.account(id: created.account.accountID).deviceCount == 1)
    #expect(try await f.authority.bootstrapChallenge(token: other.enrollmentToken).challenge.accountID == other.account.accountID)
    let state = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    #expect(state.enrollmentInvitations?[hex(ProtocolCrypto.sha256(Data(created.enrollmentToken.utf8)))] == nil)
    let activeHead = try await f.authority.status().ledgerHead.sequence
    do { _ = try await f.authority.reissueEnrollmentInvitation(accountID: created.account.accountID); Issue.record("Active account was reset") }
    catch let error as AuthorityError { #expect(error.code == "accountNotPending") }
    #expect(try await f.authority.status().ledgerHead.sequence == activeHead)
}

@Test func expiredInvitationCanBeReissuedAndSurvivesRestart() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let created = try await f.authority.createAccount(CreateAccountRequest(label: "Expired invitation"))
    _ = try await f.authority.bootstrapChallenge(token: created.enrollmentToken)
    f.clock.advance(900)
    let replacement = try await f.authority.reissueEnrollmentInvitation(accountID: created.account.accountID)
    let saved = try storedSnapshot(f.directory)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-reissued-restart-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    func seed() throws { let store = try LedgerStore(directory: directory); try store.commit(state: saved, events: []) }
    try seed()
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    let resumed = try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    await #expect(throws: (any Error).self) { try await resumed.bootstrapChallenge(token: created.enrollmentToken) }
    let challenge = try await resumed.bootstrapChallenge(token: replacement.enrollmentToken)
    let key = SoftwareSigningKey()
    let enrolled = try await resumed.bootstrapEnroll(EnrollRequest(challenge: challenge.challenge, certificates: [key.publicKey], proof: try key.sign(message: challenge.challenge.canonicalBytes())), token: replacement.enrollmentToken)
    #expect(enrolled.accountID == created.account.accountID)
}

@Test func reissueRejectsRevokedOnlyAndInitialBootstrapAccounts() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    var revoked = try JSONDecoder().decode(PersistedState.self, from: storedSnapshot(f.directory))
    revoked.devices[f.enrollment.deviceID]?.revoked = true
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-reissue-revoked-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    func seed() throws { let store = try LedgerStore(directory: directory); try store.commit(state: JSONEncoder().encode(revoked), events: []) }
    try seed()
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    let authority = try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    #expect(try await authority.account(id: f.enrollment.accountID).activeDeviceCount == 0)
    #expect(try await authority.account(id: f.enrollment.accountID).status == "inactive")
    do { _ = try await authority.reissueEnrollmentInvitation(accountID: f.enrollment.accountID); Issue.record("Revoked-only account was reset") }
    catch let error as AuthorityError { #expect(error.code == "accountNotPending") }

    let initialDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-reissue-initial-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: initialDirectory) }
    let initialConfig = ServerConfiguration(stateDirectory: initialDirectory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    let initial = try Authority(configuration: initialConfig, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    let bootstrap = try await initial.bootstrapChallenge(token: f.token)
    let head = try await initial.status().ledgerHead.sequence
    do { _ = try await initial.reissueEnrollmentInvitation(accountID: bootstrap.challenge.accountID); Issue.record("Global bootstrap account gained a second provisioning authority") }
    catch let error as AuthorityError { #expect(error.code == "accountNotPending") }
    #expect(try await initial.status().ledgerHead.sequence == head)
    #expect(try await initial.bootstrapChallenge(token: f.token).challenge == bootstrap.challenge)
    do { _ = try await initial.reissueEnrollmentInvitation(accountID: UUID().uuidString); Issue.record("Unknown account accepted") }
    catch let error as AuthorityError { #expect(error.code == "notFound") }
}

@Test func reissueWinsAgainstAnEnrollmentAwaitingAttestation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-reissue-race-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    let verifier = PausingFixtureVerifier()
    let clock = TestClock()
    let authority = try Authority(configuration: config, bootstrapToken: String(repeating: "fixture-bootstrap", count: 3), verifier: verifier, clock: { clock.now() })
    let created = try await authority.createAccount(CreateAccountRequest(label: "Concurrent reissue"))
    let challenge = try await authority.bootstrapChallenge(token: created.enrollmentToken)
    let key = SoftwareSigningKey()
    let request = EnrollRequest(challenge: challenge.challenge, certificates: [key.publicKey], proof: try key.sign(message: challenge.challenge.canonicalBytes()))
    let inFlight = Task { try await authority.bootstrapEnroll(request, token: created.enrollmentToken) }
    await verifier.waitUntilStarted()
    let replacement: CreateAccountResponse
    do { replacement = try await authority.reissueEnrollmentInvitation(accountID: created.account.accountID) }
    catch { await verifier.resume(); _ = await inFlight.result; throw error }
    await verifier.resume()
    do { _ = try await inFlight.value; Issue.record("Invalidated invitation committed after attestation returned") }
    catch let error as AuthorityError { #expect(error.code == "unauthorized") }
    #expect(try await authority.account(id: created.account.accountID).deviceCount == 0)
    let newChallenge = try await authority.bootstrapChallenge(token: replacement.enrollmentToken)
    let newKey = SoftwareSigningKey()
    _ = try await authority.bootstrapEnroll(EnrollRequest(challenge: newChallenge.challenge, certificates: [newKey.publicKey], proof: try newKey.sign(message: newChallenge.challenge.canonicalBytes())), token: replacement.enrollmentToken)
    #expect(try await authority.account(id: created.account.accountID).deviceCount == 1)
}

@Test func fullEpochHistoryAndSignedLedgerHeadSurviveRotation() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (first, leaf) = try await f.issue()
    let oldRequest = try f.workload(first, key: leaf)
    _ = try await f.authority.verifyWorkload(oldRequest)
    f.clock.advance(Epoch.duration)
    let (second, _) = try await f.issue(previous: ProtocolCrypto.sha256(first.delegation.publicKey))
    await #expect(throws: (any Error).self) { try await f.authority.verifyWorkload(oldRequest) }
    let history = try await f.authority.epochs(accountID: f.enrollment.accountID).epochs
    #expect(history.count == 2)
    #expect(history[0].credential == second && history[0].status == "current")
    #expect(history[1].credential == first && history[1].status == "expired")
    let page = try await f.authority.ledger()
    #expect(page.events.filter { $0.kind == "epoch.issued" }.count == 2)
    #expect(page.events.filter { $0.kind == "workload.accepted" }.count == 1)
    #expect(ProtocolCrypto.verify(signature: page.head.signature, message: try page.head.signingBytes(), publicKey: f.enrollment.serverPublicKey))
    var previousHash = Data(repeating: 0, count: 32)
    for event in page.events {
        #expect(event.previousHash == previousHash)
        #expect(event.hash == ProtocolCrypto.sha256(try event.canonicalBytes()))
        previousHash = event.hash
    }
    #expect(page.head.hash == previousHash && page.head.sequence == UInt64(page.events.count))
    let firstPage = try await f.authority.ledger(limit: 2)
    let nextPage = try await f.authority.ledger(after: firstPage.nextAfter, limit: 2)
    #expect(firstPage.hasMore && nextPage.events.first?.sequence == firstPage.nextAfter + 1)
    #expect(try await f.authority.ledger(after: page.head.sequence).events.isEmpty)
    await #expect(throws: (any Error).self) { try await f.authority.ledger(limit: 201) }
    await #expect(throws: (any Error).self) { try await f.authority.ledger(after: UInt64.max) }
}

@Test func revocationAndRecoveryAreAtomicVisibleLedgerEvents() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (survivor, survivorKey) = try await f.candidate(); try await f.approve(survivor)
    let (replacement, _) = try await f.candidate()
    let change = RecoveryChange(accountID: f.enrollment.accountID, lostDeviceID: f.enrollment.deviceID, replacementDeviceID: replacement.deviceID, publicKey: replacement.publicKey)
    let auth = try await f.authorization(.recoverDevice, payload: change.canonicalBytes(), deviceID: survivor.deviceID, key: survivorKey)
    let before = try await f.authority.status().ledgerHead.sequence
    _ = try await f.authority.recover(RecoveryRequest(change: change, authorization: auth))
    let events = try await f.authority.ledger(after: before).events
    #expect(events.map(\.kind) == ["device.revoked", "device.recovered"])
    #expect(events.allSatisfy { $0.actorDeviceID == survivor.deviceID })
    let devices = try await f.authority.devices(accountID: f.enrollment.accountID).devices
    #expect(devices.first { $0.deviceID == f.enrollment.deviceID }?.status == "revoked")
    #expect(devices.first { $0.deviceID == replacement.deviceID }?.status == "active")
    let head = try await f.authority.status().ledgerHead.sequence
    await #expect(throws: (any Error).self) { try await f.authority.recover(RecoveryRequest(change: change, authorization: auth)) }
    #expect(try await f.authority.status().ledgerHead.sequence == head)
}

@Test func legacyImportPreservesKeysCredentialsAndReplayWithoutInventingHistory() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, leaf) = try await f.issue()
    let workload = try f.workload(credential, key: leaf)
    _ = try await f.authority.verifyWorkload(workload)
    var legacy = try JSONSerialization.jsonObject(with: storedSnapshot(f.directory)) as! [String: Any]
    legacy["formatVersion"] = 1
    legacy.removeValue(forKey: "accounts"); legacy.removeValue(forKey: "enrollmentInvitations"); legacy.removeValue(forKey: "epochHistory")
    let encoded = try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftkey-import-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    func saveLegacy() throws { let file = try SecureStateFile(directory: directory); try file.write(encoded, name: "authority.json") }
    try saveLegacy()
    let config = ServerConfiguration(stateDirectory: directory.path, androidPackage: "test.fixture", androidSigningCertificateSHA256: String(repeating: "00", count: 32))
    var imported: Authority? = try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    #expect(await imported!.publicKey == f.enrollment.serverPublicKey)
    #expect(try await imported!.account(id: f.enrollment.accountID).imported)
    #expect(try await imported!.epochs(accountID: f.enrollment.accountID).epochs.first?.credential == credential)
    await #expect(throws: (any Error).self) { try await imported!.verifyWorkload(workload) }
    #expect(try await imported!.ledger().events.map(\.kind) == ["authority.imported"])
    #expect(try Data(contentsOf: directory.appendingPathComponent("authority.json")) == encoded)
    imported = nil
    let resumed = try Authority(configuration: config, bootstrapToken: f.token, verifier: FixtureVerifier(), clock: { f.clock.now() })
    #expect(try await resumed.ledger().events.map(\.kind) == ["authority.imported"])
    #expect(try await resumed.status().schemaVersion == 2)
}

@Test func workspaceSnapshotHasAuthoritativeInvitationEligibility() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let pending = try await f.authority.createAccount(CreateAccountRequest(label: "Requested account"))
    let workspace = try await f.authority.workspace(WorkspaceQuery(accountID: pending.account.accountID))
    #expect(workspace.selectedAccountID == pending.account.accountID)
    #expect(workspace.devices.isEmpty)
    #expect(workspace.accounts.first(where: { $0.accountID == pending.account.accountID })?.canReissueInvitation == true)
    #expect(workspace.accounts.first(where: { $0.accountID == f.enrollment.accountID })?.canReissueInvitation == false)
    #expect(workspace.status.ledgerHead.sequence == workspace.ledger.head.sequence)
    #expect(workspace.ledger.events.allSatisfy { $0.accountID == pending.account.accountID })
}

@Test func readOnlyCredentialVerificationChecksTrustExpiryAndDoesNotConsumeWorkload() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, leaf) = try await f.issue()
    let before = try await f.authority.ledger().head
    let receipt = try await f.authority.verifyCredential(VerifyCredentialRequest(credential: credential))
    #expect(receipt.accountID == f.enrollment.accountID)
    #expect(receipt.credentialHash == ProtocolCrypto.sha256(try credential.canonicalBytes()))
    let after = try await f.authority.ledger().head
    #expect(before.sequence == after.sequence && before.hash == after.hash)
    #expect(try await f.authority.verifyWorkload(f.workload(credential, key: leaf)).accepted)
    await f.verifier.revokeTrust()
    await #expect(throws: (any Error).self) {
        try await f.authority.verifyCredential(VerifyCredentialRequest(credential: credential))
    }
}

@Test func expiredCredentialCannotPassReadOnlyAuthorityVerification() async throws {
    let f = try await Fixture.create()
    defer { try? FileManager.default.removeItem(at: f.directory) }
    let (credential, _) = try await f.issue()
    f.clock.advance(Epoch.duration)
    await #expect(throws: (any Error).self) {
        try await f.authority.verifyCredential(VerifyCredentialRequest(credential: credential))
    }
}
