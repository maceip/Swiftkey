import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyClient

@Test func explicitCredentialIssuanceDoesNotSubmitWorkloadAndRotatesOnDemand() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let client = try fixture.client()
    let first = try await client.ensureCurrentCredential()
    #expect(try fixture.storedState().epochSnapshot?.credential == first)
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
    #expect(try await client.ensureCurrentCredential() == first)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    fixture.change { $0.now = (first.delegation.epoch + 1) * Epoch.duration }
    let next = try await client.ensureCurrentCredential()
    #expect(next.delegation.epoch == first.delegation.epoch + 1)
    #expect(next.delegation.publicKey != first.delegation.publicKey)
    #expect(next.delegation.previousPublicKeyHash == ProtocolCrypto.sha256(first.delegation.publicKey))
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
    #expect(fixture.inspect { $0.generatedWithChallenges.count } == 1)
}

@Test func explicitCredentialDoesNotReturnBeforeDurableReceipt() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.failNextCredentialWrite = true }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.storageUnavailable) {
        try await client.ensureCurrentCredential()
    }
    #expect(try fixture.storedState().epochSnapshot?.credential == nil)
    let receipt = try await client.ensureCurrentCredential()
    #expect(try fixture.storedState().epochSnapshot?.credential == receipt)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
}

@Test func enrollmentBundleAccountBindingRejectsWrongChallengeAndStoredIdentity() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let mismatch = ClientConfiguration(serverURL: fixture.serverURL, bootstrapToken: fixture.configuration.bootstrapToken,
        serverPublicKey: fixture.server.publicKey, audience: fixture.audience, expectedAccountID: "another-account")
    let client = try ProtocolClient(configuration: mismatch, platform: fixture.platform)
    await #expect(throws: ClientError.invalidServerResponse) { try await client.enroll() }
    #expect(fixture.inspect { $0.generatedWithChallenges.isEmpty })
    #expect(fixture.inspect { $0.persisted == nil })
    let matching = ClientConfiguration(serverURL: fixture.serverURL, bootstrapToken: fixture.configuration.bootstrapToken,
        serverPublicKey: fixture.server.publicKey, audience: fixture.audience, expectedAccountID: fixture.accountID)
    let valid = try ProtocolClient(configuration: matching, platform: fixture.platform)
    #expect(try await valid.enroll().accountID == fixture.accountID)
    #expect(throws: ClientError.storedStateMismatch) { try ProtocolClient(configuration: mismatch, platform: fixture.platform) }
    // Previous configuration JSON remains decodable; newly exported bundles bind it.
    let legacy = try JSONEncoder().encode(fixture.configuration)
    #expect(try JSONDecoder().decode(ClientConfiguration.self, from: legacy).expectedAccountID == nil)
}

@Test func rejectsNonLoopbackCleartextConfiguration() throws {
    let server = SoftwareSigningKey()
    let configuration = ClientConfiguration(serverURL: "http://example.com:8080",
        bootstrapToken: "test-token", serverPublicKey: server.publicKey, audience: "test-audience")
    let platform = ClientPlatform(
        enroll: { _ in throw ClientError.unsupportedHardware },
        signRootMessage: { _ in throw ClientError.unsupportedHardware },
        post: { _, _, _ in throw ClientError.invalidServerResponse },
        readState: { nil }, writeState: { _ in })
    #expect(throws: ClientError.invalidConfiguration) {
        try ProtocolClient(configuration: configuration, platform: platform)
    }
}

@Test func enrollmentPersistsChallengeBeforeHardwareAndReusesPendingChallengeAfterRestart() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.enrollmentTransportFailuresRemaining = 1 }
    let firstClient = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.transportUnavailable) {
        try await firstClient.enroll()
    }
    let pending = try #require(fixture.storedState().pendingBootstrap)
    #expect(fixture.inspect { $0.generatedWithChallenges } == [pending.attestationChallenge])
    #expect(try fixture.storedState().pendingEvidence?.publicKey == fixture.root.publicKey)
    fixture.change { $0.now = pending.challenge.expiresAt + 1 }
    let secondClient = try fixture.client()
    let enrolled = try await secondClient.enroll()
    #expect(enrolled.publicKey == fixture.root.publicKey)
    #expect(fixture.inspect { $0.requests["/v1/bootstrap/challenge"] } == 1)
    #expect(fixture.inspect { $0.generatedWithChallenges } == [pending.attestationChallenge])
    #expect(fixture.inspect { $0.rootMessages } == Array(repeating: try pending.challenge.canonicalBytes(), count: 2))
    #expect(try fixture.storedState().pendingBootstrap == nil)
    #expect(try fixture.storedState().enrollment?.publicKey == fixture.root.publicKey)
    let events = fixture.inspect { $0.events }
    #expect(try #require(events.firstIndex(of: "writeState")) < #require(events.firstIndex(of: "hardwareEnrollment")))
}

@Test func failedPersistenceNeverAllowsHardwareGenerationIncludingSameActorRetry() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.writeFailuresRemaining = 1 }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.storageUnavailable) {
        try await client.enroll()
    }
    #expect(fixture.inspect { $0.generatedWithChallenges.isEmpty })
    _ = try await client.enroll()
    #expect(fixture.inspect { $0.generatedWithChallenges.count } == 1)
    #expect(try fixture.storedState().enrollment != nil)
}

@Test func expiredPendingBootstrapDoesNotGenerateHardware() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.failHardware = true }
    let first = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.hardwareUnavailable) { try await first.enroll() }
    let pending = try #require(fixture.storedState().pendingBootstrap)
    fixture.change { $0.failHardware = false; $0.now = pending.challenge.expiresAt }
    let restarted = try fixture.client()
    await #expect(throws: ProtocolError.challengeExpired) { try await restarted.enroll() }
    #expect(fixture.inspect { $0.generatedWithChallenges.isEmpty })
}

@Test func enrollmentRejectsUnpinnedServerIdentity() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.wrongEnrollmentServerKey = true }
    let client = try fixture.client()
    await #expect(throws: ClientError.serverIdentityMismatch) { try await client.enroll() }
    #expect(try fixture.storedState().enrollment == nil)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == nil)
}

@Test func enrollmentVerifiesRootProofLocallyBeforeSendingIt() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.badRootSignatureAt = 1 }
    let client = try fixture.client()
    await #expect(throws: ClientError.enrollmentIdentityMismatch) { try await client.enroll() }
    #expect(fixture.inspect { $0.requests["/v1/bootstrap/enroll"] } == nil)
}

@Test func epochAuthorizationVerifiesRootProofLocallyBeforeIssuance() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.badRootSignatureAt = 2 }
    let client = try fixture.client()
    await #expect(throws: ProtocolError.invalidSignature) {
        try await client.runDemonstration(payload: Data("test payload".utf8))
    }
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == nil)
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
}

@Test func signedWorkloadRoundTripAndExplicitReplayRejection() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let client = try fixture.client()
    let payload = Data("test payload".utf8)
    let result = try await client.runDemonstration(payload: payload)
    #expect(result.workloadAccepted)
    #expect(result.replayRejected)
    #expect(result.accountID == fixture.accountID)
    #expect(result.deviceID == fixture.deviceID)
    #expect(result.rootPublicKey == fixture.root.publicKey)
    #expect(result.epochPublicKey != result.rootPublicKey)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == 2)
    let accepted = try #require(fixture.inspect { $0.acceptedWorkloads.first })
    #expect(accepted.workload.message.payload == payload)
    #expect(ProtocolCrypto.verify(signature: accepted.workload.signature,
        message: try accepted.workload.message.canonicalBytes(), publicKey: result.epochPublicKey))
    #expect(ProtocolCrypto.verify(signature: accepted.credential.serverSignature,
        message: try accepted.credential.unsignedCanonicalBytes(), publicKey: fixture.server.publicKey))
}

@Test func restartReusesCredentialEvenAfterIssuanceChallengeExpires() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let initial = try fixture.client()
    let first = try await initial.runDemonstration(payload: Data("first".utf8))
    let originalSnapshot = try #require(fixture.storedState().epochSnapshot)
    fixture.change { $0.now += 600 }
    let restarted = try fixture.client()
    let second = try await restarted.runDemonstration(payload: Data("second".utf8))
    #expect(second.epochPublicKey == first.epochPublicKey)
    #expect(second.epoch == first.epoch)
    #expect(fixture.inspect { $0.rootMessages.count } == 2)
    #expect(fixture.inspect { $0.generatedWithChallenges.count } == 1)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    #expect(try fixture.storedState().epochSnapshot == originalSnapshot)
}

@Test func expiredSnapshotRotatesAfterRestartAndLinksPreviousPublicKey() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let client = try fixture.client()
    let first = try await client.runDemonstration(payload: Data("first".utf8))
    fixture.change { $0.now = (first.epoch + 1) * Epoch.duration }
    let restarted = try fixture.client()
    let second = try await restarted.runDemonstration(payload: Data("next epoch".utf8))
    #expect(second.epoch == first.epoch + 1)
    #expect(second.epochPublicKey != first.epochPublicKey)
    let snapshot = try #require(fixture.storedState().epochSnapshot)
    #expect(snapshot.delegation.previousPublicKeyHash == ProtocolCrypto.sha256(first.epochPublicKey))
    #expect(snapshot.previousPublicKeyHash == snapshot.delegation.previousPublicKeyHash)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 2)
    #expect(fixture.inspect { $0.generatedWithChallenges.count } == 1)
}

@Test func replayNetworkFailureDoesNotCountAsRejection() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.replayBehavior = .transportFailure }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.transportUnavailable) {
        try await client.runDemonstration(payload: Data("test".utf8))
    }
    #expect(fixture.inspect { $0.acceptedWorkloads.count } == 1)
}

@Test func unrelatedServerRejectionDoesNotCountAsReplayProof() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.replayBehavior = .unrelatedRejection }
    let client = try fixture.client()
    await #expect(throws: ClientError.serverRejected("revokedDevice")) {
        try await client.runDemonstration(payload: Data("test".utf8))
    }
}

@Test func acceptedReplayFailsTheDemonstration() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.replayBehavior = .accept }
    let client = try fixture.client()
    await #expect(throws: ClientError.replayUnexpectedlyAccepted) {
        try await client.runDemonstration(payload: Data("test".utf8))
    }
}

@Test func wrongCredentialSignerIsRejectedBeforeAnyWorkloadSubmission() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.wrongCredentialSigner = true }
    let client = try fixture.client()
    await #expect(throws: ProtocolError.invalidSignature) {
        try await client.runDemonstration(payload: Data("test".utf8))
    }
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
    #expect(try fixture.storedState().epochSnapshot?.credential == nil)
}

@Test func mismatchedWorkloadReceiptIsNotReportedAsAcceptance() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.wrongWorkloadReceipt = true }
    let client = try fixture.client()
    await #expect(throws: ClientError.invalidServerResponse) {
        try await client.runDemonstration(payload: Data("test".utf8))
    }
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == 1)
}

@Test func savedStateCannotMoveToDifferentServerPin() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    let client = try fixture.client()
    _ = try await client.enroll()
    let differentServer = SoftwareSigningKey()
    let config = ClientConfiguration(serverURL: fixture.serverURL,
        bootstrapToken: "test-token", serverPublicKey: differentServer.publicKey, audience: fixture.audience)
    #expect(throws: ClientError.storedStateMismatch) {
        try ProtocolClient(configuration: config, platform: fixture.platform)
    }
}

@Test func failedCredentialPersistenceIsRetriedBeforeAnyWorkloadLeavesClient() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.failNextCredentialWrite = true }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.storageUnavailable) {
        try await client.runDemonstration(payload: Data("first attempt".utf8))
    }
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    #expect(fixture.inspect { $0.requests["/v1/workloads"] } == nil)
    #expect(try fixture.storedState().epochSnapshot?.credential == nil)
    let result = try await client.runDemonstration(payload: Data("retry".utf8))
    #expect(result.workloadAccepted && result.replayRejected)
    #expect(fixture.inspect { $0.requests["/v1/epochs"] } == 1)
    #expect(try fixture.storedState().epochSnapshot?.credential != nil)
}

@Test func failedCompletedEnrollmentPersistenceDoesNotCreateUnsavedSuccessCache() async throws {
    let fixture = SoftwareOnlyProtocolFixture()
    fixture.change { $0.failCompletedEnrollmentWrite = true }
    let client = try fixture.client()
    await #expect(throws: SoftwareOnlyProtocolFixture.Failure.storageUnavailable) {
        try await client.enroll()
    }
    #expect(try fixture.storedState().enrollment == nil)
    let enrolled = try await client.enroll()
    #expect(try fixture.storedState().enrollment?.deviceID == enrolled.deviceID)
    #expect(fixture.inspect { $0.generatedWithChallenges.count } == 1)
    #expect(fixture.inspect { $0.requests["/v1/bootstrap/challenge"] } == 1)
}
