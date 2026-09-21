import Foundation
import Testing
import SwiftKeyCore
@testable import SwiftKeyClient
@testable import SwiftKeyApplication

/// Signed software fixtures exercise presentation of already-verified values.
/// No fixture is an attestation verifier or a native trust adapter.
private struct NativeProjectionFixture {
    enum Failure: Error { case unexpectedPlatformCall }
    let authority = SoftwareSigningKey(), root = SoftwareSigningKey(), peer = SoftwareSigningKey()
    let localID = "00000000-0000-0000-0000-000000000001"
    let peerID = "00000000-0000-0000-0000-000000000002"
    let accountID = "00000000-0000-0000-0000-000000000010"
    let pairID = "00000000-0000-0000-0000-000000000020"
    let proposalID = "00000000-0000-0000-0000-000000000030"
    let origin = "https://projection.example"
    let hash = Data(repeating: 1, count: 32)
    var config: PairingClientConfiguration { .init(serverURL: origin, serverPublicKey: authority.publicKey) }
    func signed<T: PairingV2CanonicalRecord>(_ record: T) throws -> PairingV2.Signed<T> {
        try .sign(record, using: authority)
    }
    func identity(expires: UInt64 = 1900) throws -> PairingV2.Signed<PairingV2.DeviceTrustReceipt> {
        try signed(.init(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
            deviceID: localID, rootKind: .androidStrongBox, rootKeyEpoch: 3, rootPublicKey: root.publicKey,
            originalChallengeHash: hash, evidenceHash: hash, trustPolicyID: "projection-test-only",
            verifiedAt: 1000, leaseExpiresAt: expires))
    }
    func owners() throws -> [PairingV2.OwnerDescriptor] {
        [try identity().payload.ownerDescriptor(), .init(deviceID: peerID, rootKind: .androidStrongBox,
            rootKeyEpoch: 2, rootPublicKey: peer.publicKey, attestationReceiptHash: hash)]
    }
    func context() throws -> PairingV2.PairingContext {
        .init(purpose: .addOwner, existingAccount: .init(accountID: accountID, accountLabel: "Retained account",
            ownershipPolicyID: PairingV2.ownershipPolicy, membershipRevision: 1, existingOwners: try owners()))
    }
    func inspection(existing: Bool = false) throws -> PairingV2.Signed<PairingV2.PairingInspection> {
        try signed(.init(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
            pairingID: pairID, revision: 1, initiator: try owners()[1],
            context: existing ? context() : .init(purpose: .createAccount), issuedAt: 1050, expiresAt: 1170))
    }
    func response(_ state: PairingV2.OperationState,
                  inspection: PairingV2.Signed<PairingV2.PairingInspection>? = nil,
                  genesis: PairingV2.Signed<PairingV2.AccountGenesis>? = nil,
                  receipt: PairingV2.Signed<PairingV2.AccountReceipt>? = nil) throws -> PairingV2.OperationResponse {
        let header = PairingV2.SignedState(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
            scopeKind: state.scopeKind, scopeID: state.scopeID, revision: state.revision,
            payloadHash: try state.digest(), issuedAt: 1050, expiresAt: 1110)
        return .init(state: state, signedState: try signed(header), inspection: inspection, genesis: genesis, accountReceipt: receipt)
    }
    func committed() throws -> PairingV2.OperationResponse {
        let genesis = PairingV2.AccountGenesis(authorityID: config.authorityID, origin: origin, audience: PairingV2.audience,
            proposalID: proposalID, pairingID: pairID, pairTranscriptHash: hash, accountID: accountID,
            label: "Retained account", owners: try owners(), ownershipPolicyID: PairingV2.ownershipPolicy,
            initialMembershipRevision: 1, nonce: hash, issuedAt: 1000, expiresAt: 1300)
        let receipt = PairingV2.AccountReceipt(genesis: genesis, pairReceiptHash: hash, aApprovalDigest: hash,
            bApprovalDigest: hash, createdAt: 1050, membershipRevision: 1, ledgerFirstSequence: 1,
            ledgerLastSequence: 2, ledgerHeadHash: hash)
        let state = PairingV2.OperationState(scopeKind: .genesisProposal, scopeID: proposalID, revision: 5,
            status: .committed, objectHash: try genesis.digest(), approvedSignerIDs: [localID, peerID],
            phaseExpiresAt: genesis.expiresAt, receiptHash: try receipt.digest())
        return try response(state, genesis: signed(genesis), receipt: signed(receipt))
    }
    func cancelledAddition() throws -> PairingV2.OperationResponse {
        let invitation = try inspection(existing: true)
        let state = PairingV2.OperationState(scopeKind: .pairing, scopeID: pairID, revision: 2,
            status: .cancelled, objectHash: try invitation.payload.digest(), approvedSignerIDs: [], phaseExpiresAt: 1170)
        return try response(state, inspection: invitation)
    }
    func snapshot(identity: PairingV2.Signed<PairingV2.DeviceTrustReceipt>? = nil,
                  operation: PairingV2.OperationResponse? = nil, committed: PairingV2.OperationResponse? = nil,
                  inspection: PairingV2.Signed<PairingV2.PairingInspection>? = nil,
                  pending: String? = nil, admissionFailure: String? = nil, signedIn: Bool = false, now: UInt64 = 1100) -> PairingClientSnapshot {
        .init(configuration: config, identity: identity, operation: operation, committedOperation: committed,
            inspection: inspection, roster: nil, accountReceipt: committed?.accountReceipt,
            membershipReceipt: nil, pendingRequestID: pending, admissionFailure: admissionFailure, signedIn: signedIn, credential: nil,
            invitationAvailable: false, now: now)
    }
    func service() throws -> NativePhoneProtocolService {
        let platform = ClientPlatform(enroll: { _ in throw Failure.unexpectedPlatformCall },
            signRootMessage: { _ in throw Failure.unexpectedPlatformCall },
            post: { _, _, _ in throw Failure.unexpectedPlatformCall }, readState: { nil },
            writeState: { _ in throw Failure.unexpectedPlatformCall }, now: { 1100 })
        return NativePhoneProtocolService(client: try PairingClient(configuration: config, platform: platform))
    }
}

@Test func nativeProjectionKeepsAccountAfterCancelledAdditionIsRestarted() async throws {
    let f = NativeProjectionFixture(), service = try f.service(), identity = try f.identity(), committed = try f.committed()
    let cancelled = try await service.project(f.snapshot(identity: identity, operation: f.cancelledAddition(), committed: committed, signedIn: true))
    #expect(cancelled.phase == .cancelled && cancelled.accountID == f.accountID)
    #expect(cancelled.lastRequestID == nil && cancelled.rejection(for: .restart, now: 1100) == nil)
    let restarted = try await service.project(f.snapshot(identity: identity, committed: committed, signedIn: true))
    #expect(restarted.phase == .owners && restarted.accountID == f.accountID)
    #expect(restarted.hasVerifiedReceipt && restarted.owners.count == 2)
    #expect(restarted.rejection(for: .beginOwnerChange(.add, accountID: f.accountID, membershipRevision: 1, targetOwnerID: nil), now: 1100) == nil)
}

@Test func nativeInspectionAndLocalDeclineDoNotInventAnIdentityOrCommit() async throws {
    let f = NativeProjectionFixture(), service = try f.service(), inspection = try f.inspection(existing: true)
    let reviewed = try await service.project(f.snapshot(inspection: inspection))
    #expect(reviewed.phase == .inspectInvitation && reviewed.localIdentity == nil)
    #expect(reviewed.owners.count == 2 && reviewed.accountID == f.accountID && reviewed.change?.kind == .add)
    #expect(reviewed.rejection(for: .prepareIdentity, now: 1100) == nil)
    #expect(reviewed.rejection(for: .join(try #require(reviewed.binding)), now: 1100) == .invalidAction)
    let declined = try await service.project(f.snapshot())
    #expect(declined.phase == .introduction && declined.binding == nil && declined.accountID == nil && declined.lastRequestID == nil)
    let preparedDecline = try await service.project(f.snapshot(identity: f.identity()))
    #expect(preparedDecline.phase == .invitation && preparedDecline.localIdentity != nil && preparedDecline.binding == nil)
}

@Test func nativeTrustRenewalRetainsIdentityReceiptAndAccountContext() async throws {
    let f = NativeProjectionFixture(), service = try f.service(), committed = try f.committed()
    let expired = try await service.project(f.snapshot(identity: f.identity(expires: 1100), committed: committed, signedIn: true))
    #expect(expired.phase == .trustUnavailable && expired.accountID == f.accountID && expired.hasVerifiedReceipt)
    #expect(expired.rejection(for: .renewIdentity, now: 1100) == nil)
    #expect(expired.rejection(for: .signIn(accountID: f.accountID, membershipRevision: 1), now: 1100) == .trustUnavailable)
    let renewed = try await service.project(f.snapshot(identity: f.identity(), committed: committed, signedIn: true))
    #expect(renewed.phase == .owners && renewed.hasVerifiedReceipt)
    #expect(renewed.localIdentity?.id == expired.localIdentity?.id)
    #expect(renewed.localIdentity?.fingerprint == expired.localIdentity?.fingerprint)
    #expect(renewed.localIdentity?.rootKeyEpoch == expired.localIdentity?.rootKeyEpoch)
}

@Test func nativeUnknownResultOverridesTrustAndCommitButRetainsHistoricalEvidence() async throws {
    let f = NativeProjectionFixture(), service = try f.service()
    let state = try await service.project(f.snapshot(identity: f.identity(expires: 1100), committed: f.committed(), pending: "original-sign-in", signedIn: true))
    #expect(state.phase == .outcomeUnknown && state.failure == .outcomeUnknown)
    #expect(state.lastRequestID == "original-sign-in" && state.hasVerifiedReceipt && state.accountID == f.accountID)
    #expect(state.rejection(for: .recover(requestID: "original-sign-in"), now: 1100) == nil)
    #expect(state.rejection(for: .renewIdentity, now: 1100) == .outcomeUnknown)
}

@Test func nativeSignInOrEpochFailureDoesNotReopenAccountCreation() async throws {
    let f = NativeProjectionFixture(), service = try f.service(), committed = try f.committed(), identity = try f.identity()
    for signedIn in [false, true] {
        let state = try await service.project(f.snapshot(identity: identity, committed: committed, signedIn: signedIn))
        #expect(state.phase == (signedIn ? .owners : .committed))
        #expect(state.hasVerifiedReceipt && state.credentialStatus == "No current epoch credential")
        #expect(state.rejection(for: .signIn(accountID: f.accountID, membershipRevision: 1), now: 1100) == nil)
        #expect(state.rejection(for: .createPairing, now: 1100) == .invalidAction)
        #expect(state.rejection(for: .restart, now: 1100) == .invalidAction)
    }
}

@Test func nativeServiceKnownPreSubmitRejectionRemainsKnown() async throws {
    let service = try NativeProjectionFixture().service()
    let result = try await service.perform(.renewIdentity, requestID: "never-sent")
    #expect(result.phase == .introduction && result.lastRequestID == nil && result.failure == .invalidAction)
}

@Test func nativeDefinitivelyFailedAdmissionIsUnavailableRatherThanUnknown() async throws {
    let f = NativeProjectionFixture(), service = try f.service()
    let result = try await service.project(f.snapshot(admissionFailure: "unsupportedHardware"))
    #expect(result.phase == .trustUnavailable && result.failure == .trustUnavailable)
    #expect(result.localIdentity == nil && result.lastRequestID == nil && result.accountID == nil)
    #expect(result.rejection(for: .renewIdentity, now: 1100) == .invalidAction)
    #expect(result.rejection(for: .prepareIdentity, now: 1100) == .trustUnavailable)
    #expect(result.rejection(for: .refresh, now: 1100) == nil)
}
