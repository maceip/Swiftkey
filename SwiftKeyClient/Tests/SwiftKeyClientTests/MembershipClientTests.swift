import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyClient

@Test func pairingRequiresApprovalAndPinnedConfirmationBeforeBecomingEnrolled() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let newClient = try fixture.client(newcomer) // No bootstrap token.
    let invitation = try await ownerClient.requestPairing()
    let candidate = try await newClient.preparePairing(invitation)
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
    #expect(try fixture.saved(newcomer)?.pairingCandidate?.publicKey == newcomer.key.publicKey)
    await #expect(throws: ClientError.serverRejected("unknownDevice")) { try await newClient.completePairing() }
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
    #expect(try await ownerClient.approvePairing(candidate).accepted)
    let enrolled = try await newClient.completePairing()
    #expect(enrolled.deviceID == candidate.deviceID)
    #expect(enrolled.publicKey == newcomer.key.publicKey)
    #expect(try fixture.saved(newcomer)?.enrollment?.deviceID == candidate.deviceID)
    #expect(try fixture.saved(newcomer)?.pendingPairing == nil)
    let restarted = try fixture.client(newcomer)
    #expect(try await restarted.enroll().deviceID == candidate.deviceID)
    #expect(fixture.generationCount(newcomer) == 1)
    let changes = fixture.inspect { $0.memberships }
    #expect(changes.map(\.change.operation) == [.addDevice, .enroll])
    #expect(changes[0].change.publicKey == candidate.publicKey)
    #expect(changes[0].authorization.challenge.deviceID == "owner")
    #expect(changes[1].authorization.challenge.deviceID == candidate.deviceID)
}

@Test func pairingRetryRestoresInvitationAndEvidenceWithoutGeneratingAgain() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let invitation = try await ownerClient.requestPairing()
    let first = try fixture.client(newcomer)
    fixture.change { $0.loseCandidateResponse = true }
    await #expect(throws: SoftwareOnlyMembershipFixture.Failure.transport) { try await first.preparePairing(invitation) }
    #expect(try fixture.saved(newcomer)?.pendingPairingEvidence?.publicKey == newcomer.key.publicKey)
    let restarted = try fixture.client(newcomer)
    let candidate = try await restarted.preparePairing(invitation)
    #expect(candidate.deviceID == invitation.challenge.deviceID)
    #expect(fixture.generationCount(newcomer) == 1)
    let changedInvitation = try await ownerClient.requestPairing()
    await #expect(throws: ClientError.storedStateMismatch) { try await restarted.preparePairing(changedInvitation) }
    #expect(fixture.generationCount(newcomer) == 1)
    await #expect(throws: ClientError.storedStateMismatch) { try await restarted.enroll() }
    #expect(fixture.inspect { $0.requests["/v1/bootstrap/challenge"] } == nil)
}

@Test(arguments: [SoftwareOnlyMembershipFixture.WriteStage.invitation, .evidence, .candidate])
func pairingPersistenceFailuresRemainRetryable(_ stage: SoftwareOnlyMembershipFixture.WriteStage) async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let invitation = try await ownerClient.requestPairing()
    let client = try fixture.client(newcomer)
    fixture.failWrite(newcomer, at: stage)
    await #expect(throws: SoftwareOnlyMembershipFixture.Failure.persistence) { try await client.preparePairing(invitation) }
    if stage == .invitation { #expect(fixture.generationCount(newcomer) == 0) }
    let candidate = try await client.preparePairing(invitation)
    #expect(try fixture.saved(newcomer)?.pairingCandidate?.deviceID == candidate.deviceID)
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
}

@Test func pairingRejectsWrongCandidateKeyAndWrongServerConfirmationPin() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let invitation = try await ownerClient.requestPairing()
    let client = try fixture.client(newcomer)
    fixture.change { $0.wrongCandidateKey = true }
    await #expect(throws: ClientError.enrollmentIdentityMismatch) { try await client.preparePairing(invitation) }
    #expect(try fixture.saved(newcomer)?.pairingCandidate == nil)
    fixture.change { $0.wrongCandidateKey = false }
    let candidate = try await client.preparePairing(invitation)
    _ = try await ownerClient.approvePairing(candidate)
    fixture.change { $0.wrongConfirmationPin = true }
    await #expect(throws: ClientError.serverIdentityMismatch) { try await client.completePairing() }
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
    fixture.change { $0.wrongConfirmationPin = false; $0.wrongConfirmationDevice = true }
    await #expect(throws: ClientError.enrollmentIdentityMismatch) { try await client.completePairing() }
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
}

@Test func approvedPairingCanConfirmAfterCandidateExpiryAndLostConfirmationResponse() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let client = try fixture.client(newcomer)
    let candidate = try await client.preparePairing(ownerClient.requestPairing())
    _ = try await ownerClient.approvePairing(candidate)
    fixture.change { $0.now = candidate.expiresAt + 1; $0.loseConfirmationResponse = true }
    await #expect(throws: SoftwareOnlyMembershipFixture.Failure.transport) { try await client.completePairing() }
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
    let restarted = try fixture.client(newcomer)
    let enrolled = try await restarted.completePairing()
    #expect(enrolled.deviceID == candidate.deviceID)
    let confirmations = fixture.inspect { $0.memberships.filter { $0.change.operation == .enroll } }
    #expect(confirmations.count == 2)
    #expect(confirmations[1].authorization.challenge.sequence == confirmations[0].authorization.challenge.sequence + 1)
    #expect(fixture.generationCount(newcomer) == 1)
}

@Test func failedPairingConfirmationPersistenceCannotCacheUnsavedEnrollment() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let client = try fixture.client(newcomer)
    let candidate = try await client.preparePairing(ownerClient.requestPairing())
    _ = try await ownerClient.approvePairing(candidate)
    fixture.failWrite(newcomer, at: .enrollment)
    await #expect(throws: SoftwareOnlyMembershipFixture.Failure.persistence) { try await client.completePairing() }
    #expect(try fixture.saved(newcomer)?.enrollment == nil)
    let enrolled = try await client.completePairing()
    #expect(try fixture.saved(newcomer)?.enrollment?.deviceID == enrolled.deviceID)
}

@Test func revocationBindsExactTargetAndRevokedDeviceCannotAuthorizeAnotherOperation() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let target = try fixture.makeDevice("target", enrolled: true)
    let client = try fixture.client(owner)
    #expect(try await client.revokeDevice("target").accepted)
    let request = try #require(fixture.inspect { $0.memberships.last })
    #expect(request.change.deviceID == "target")
    #expect(request.change.publicKey == nil)
    #expect(request.change.operation == .revokeDevice)
    #expect(request.authorization.challenge.payloadHash == ProtocolCrypto.sha256(try request.change.canonicalBytes()))
    #expect(fixture.inspect { $0.members["target"]?.active } == false)
    let revokedClient = try fixture.client(target)
    await #expect(throws: ClientError.serverRejected("revokedDevice")) { try await revokedClient.revokeDevice("owner") }
    await #expect(throws: ProtocolError.invalidField("deviceID")) { try await client.revokeDevice("owner") }
}

@Test func recoveryBindsLostAndReplacementRootsAndRequiresReplacementConfirmation() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    _ = try fixture.makeDevice("lost", enrolled: true)
    let replacement = try fixture.makeDevice("replacement")
    let ownerClient = try fixture.client(owner)
    let replacementClient = try fixture.client(replacement)
    let candidate = try await replacementClient.preparePairing(ownerClient.requestPairing())
    #expect(try await ownerClient.recover(lostDeviceID: "lost", replacementCandidate: candidate).accepted)
    let request = try #require(fixture.inspect { $0.recoveries.first })
    #expect(request.change.lostDeviceID == "lost")
    #expect(request.change.replacementDeviceID == candidate.deviceID)
    #expect(request.change.publicKey == replacement.key.publicKey)
    #expect(request.authorization.challenge.payloadHash == ProtocolCrypto.sha256(try request.change.canonicalBytes()))
    #expect(fixture.inspect { $0.members["lost"]?.active } == false)
    #expect(fixture.inspect { $0.members[candidate.deviceID]?.active } == true)
    #expect(try fixture.saved(replacement)?.enrollment == nil)
    #expect(try await replacementClient.completePairing().publicKey == replacement.key.publicKey)
}

@Test func membershipRejectsCrossAccountExpiredAndSelfRecoveryCandidates() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let client = try fixture.client(owner)
    let newClient = try fixture.client(newcomer)
    let candidate = try await newClient.preparePairing(client.requestPairing())
    let otherAccount = PairingCandidate(accountID: "other-account", deviceID: candidate.deviceID,
        publicKey: candidate.publicKey, expiresAt: candidate.expiresAt)
    await #expect(throws: ClientError.enrollmentIdentityMismatch) { try await client.approvePairing(otherAccount) }
    await #expect(throws: ProtocolError.invalidField("lostDeviceID")) {
        try await client.recover(lostDeviceID: "owner", replacementCandidate: candidate)
    }
    fixture.change { $0.now = candidate.expiresAt }
    await #expect(throws: ProtocolError.challengeExpired) { try await client.approvePairing(candidate) }
    #expect(fixture.inspect { $0.requests["/v1/challenges"] } == nil)
}

@Test func invitationRejectsBootstrapPurposeAndExpiredChallengeBeforeHardware() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    let newcomer = try fixture.makeDevice("newcomer")
    let ownerClient = try fixture.client(owner)
    let client = try fixture.client(newcomer)
    let invitation = try await ownerClient.requestPairing()
    let challenge = invitation.challenge
    let bootstrap = ChallengeEnvelope(accountID: challenge.accountID, deviceID: challenge.deviceID,
        operation: .enroll, sequence: challenge.sequence, nonce: challenge.nonce, expiresAt: challenge.expiresAt,
        payloadHash: ProtocolCrypto.sha256(Data("swiftkey-bootstrap-v1".utf8)))
    let wrongPurpose = BootstrapChallengeResponse(challenge: bootstrap,
        attestationChallenge: ProtocolCrypto.sha256(try bootstrap.canonicalBytes()))
    await #expect(throws: ClientError.invalidServerResponse) { try await client.preparePairing(wrongPurpose) }
    fixture.change { $0.now = invitation.challenge.expiresAt }
    await #expect(throws: ProtocolError.challengeExpired) { try await client.preparePairing(invitation) }
    #expect(fixture.generationCount(newcomer) == 0)
    #expect(try fixture.saved(newcomer) == nil)
}

@Test func negativeMembershipAcknowledgementIsNotSuccess() async throws {
    let fixture = SoftwareOnlyMembershipFixture()
    let owner = try fixture.makeDevice("owner", enrolled: true)
    _ = try fixture.makeDevice("target", enrolled: true)
    let client = try fixture.client(owner)
    fixture.change { $0.rejectMutation = true }
    await #expect(throws: ClientError.invalidServerResponse) { try await client.revokeDevice("target") }
    #expect(fixture.inspect { $0.members["target"]?.active } == true)
}

@Test func pendingBootstrapCannotBeReplacedByPairingInvitation() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.failHardware = true }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.hardwareUnavailable) { try await client.enroll() }
    let pending = try #require(fixture.storedState().pendingBootstrap)
    let challenge = ChallengeEnvelope(accountID: pending.challenge.accountID, deviceID: "pairing-device",
        operation: .enroll, sequence: 1, nonce: ProtocolCrypto.randomNonce(),
        expiresAt: pending.challenge.expiresAt,
        payloadHash: ProtocolCrypto.sha256(Data("swiftkey-pairing-v1".utf8)))
    let invitation = BootstrapChallengeResponse(challenge: challenge,
        attestationChallenge: ProtocolCrypto.sha256(try challenge.canonicalBytes()))
    await #expect(throws: ClientError.storedStateMismatch) { try await client.preparePairing(invitation) }
    #expect(try fixture.storedState().pendingBootstrap?.challenge == pending.challenge)
    #expect(try fixture.storedState().pendingPairing == nil)
}
