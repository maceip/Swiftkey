import Foundation
import Testing
@testable import SwiftKeyApplication

// Presentation-only fixture: no software identity is accepted by a live service.
private actor PhoneServiceFixture: PhoneProtocolService {
    struct Call: Sendable { let action: PhoneProtocolAction; let requestID: String }
    enum Failure: Error { case transportContainingPrivateDetails }
    private var projection: PhoneProtocolSnapshot
    private var failNext = false
    private var pauseNext = false
    private var entered = false
    private var started: CheckedContinuation<Void, Never>?
    private var paused: CheckedContinuation<Void, Never>?
    private var calls: [Call] = []
    init(_ projection: PhoneProtocolSnapshot) { self.projection = projection }
    func set(_ projection: PhoneProtocolSnapshot) { self.projection = projection }
    func fail() { failNext = true }
    func pause() { pauseNext = true; entered = false }
    func requests() -> [Call] { calls }
    func waitUntilStarted() async {
        if entered { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { paused?.resume(); paused = nil }
    func perform(_ action: PhoneProtocolAction, requestID: String) async throws -> PhoneProtocolSnapshot {
        calls.append(Call(action: action, requestID: requestID))
        let response = projection, failure = failNext
        failNext = false
        if pauseNext {
            pauseNext = false; entered = true; started?.resume(); started = nil
            await withCheckedContinuation { paused = $0 }
        }
        if failure { throw Failure.transportContainingPrivateDetails }
        return response
    }
}

private let phoneNow: UInt64 = 10_000
private let phoneBinding = PhoneProtocolBinding(objectID: "proposal-1", revision: 2,
    digest: String(repeating: "a", count: 64), expiresAt: phoneNow + 300)
private let ownerA = PhoneIdentity(id: "owner-a", label: "This phone", fingerprint: String(repeating: "1", count: 64),
    trust: "Verified", isCurrent: true)
private let ownerB = PhoneIdentity(id: "owner-b", label: "Other phone", fingerprint: String(repeating: "2", count: 64), trust: "Verified")
private let ownerC = PhoneIdentity(id: "owner-c", label: "New phone", fingerprint: String(repeating: "3", count: 64), trust: "Verified")

private func phoneReview(_ phase: PhoneProtocolPhase = .reviewGenesis) -> PhoneProtocolSnapshot {
    PhoneProtocolSnapshot(phase: phase, availability: .nativeReady, binding: phoneBinding,
        authorityID: "pinned-authority", origin: "https://authority.example", audience: "phone.test",
        accountID: "account-1", accountLabel: "Personal", membershipRevision: 2, authorizingOwnerID: ownerA.id,
        localIdentity: ownerA, peer: ownerB, owners: [ownerA, ownerB])
}
private func phoneCommitted() -> PhoneProtocolSnapshot {
    var result = phoneReview(.committed)
    result.receipt = PhoneCommitReceipt(operationID: phoneBinding.objectID, accountID: "account-1", proposalDigest: phoneBinding.digest,
        ledgerSequence: 12, ledgerHash: String(repeating: "f", count: 64), verified: true)
    return result
}

@Test func phoneProtocolWithoutAdapterCannotStartOrPretendToRefresh() async {
    let store = PhoneProtocolStore(clock: { phoneNow })
    for action in [PhoneProtocolAction.prepareIdentity, .refresh, .createPairing] {
        let response = await store.send(action)
        #expect(response.failure == .unavailable)
        #expect(response.availability == .notImplemented && response.phase == .introduction)
    }
    #expect(await store.snapshot().receipt == nil)
}

@Test func browserProjectionCanReadButCannotAuthorizeThroughSharedStore() async {
    var projection = phoneReview(.comparePeers)
    projection.availability = .browserReadOnly
    projection.lastRequestID = "original-request"
    let service = PhoneServiceFixture(projection)
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    #expect(await store.send(.confirmPeers(phoneBinding)).failure == .unavailable)
    #expect(await service.requests().count == 1)
    #expect(await store.send(.resume(phoneBinding)).failure == .unavailable)
    #expect(await store.send(.recover(requestID: "original-request")).failure == .unavailable)
    #expect(await service.requests().count == 1)
    #expect(await store.send(.refresh).failure == nil)
    #expect(await service.requests().count == 2)
}

@Test func consentRequiresExactDisplayedObjectRevisionDigestAndDeadline() {
    let projection = phoneReview()
    #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneNow) == nil)
    var altered = [phoneBinding, phoneBinding, phoneBinding, phoneBinding]
    altered[0].objectID = "another-proposal"
    altered[1].revision += 1
    altered[2].digest = String(repeating: "b", count: 64)
    altered[3].expiresAt += 1
    for binding in altered {
        #expect(projection.rejection(for: .approveGenesis(binding), now: phoneNow) == .staleBinding)
    }
    #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneBinding.expiresAt) == .expired)
    #expect(projection.rejection(for: .resume(phoneBinding), now: phoneBinding.expiresAt + 1) == nil)
}

@Test func genesisConsentRejectsUnrelatedRevokedOrDuplicateHardwareOwners() {
    var projection = phoneReview()
    projection.owners[1] = ownerC
    #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneNow) == .invalidAction)
    projection = phoneReview(); projection.owners[1].revoked = true
    #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneNow) == .invalidAction)
    projection = phoneReview(); projection.owners[1].fingerprint = ownerA.fingerprint
    projection.peer = projection.owners[1]
    #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneNow) == .invalidAction)
}

@Test func membershipConsentRejectsSilentRootSubstitutionAndChangedCandidate() {
    var projection = phoneReview(.reviewMembership)
    projection.peer = ownerC
    projection.change = PhoneMembershipChange(kind: .add, candidate: ownerC, resultingOwners: [ownerA, ownerB, ownerC])
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == nil)
    projection.change?.resultingOwners[1].fingerprint = String(repeating: "4", count: 64)
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
    projection.change?.resultingOwners = [ownerA, ownerB, ownerC]
    projection.change?.resultingOwners[2].rootKind = "Unverified software key"
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
    projection.change?.resultingOwners = [ownerA, ownerB, ownerC]
    projection.change?.resultingOwners[1].rootKeyEpoch += 1
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
    projection.change?.resultingOwners = [ownerA, ownerB, ownerC]
    projection.change?.candidate?.fingerprint = ownerA.fingerprint
    projection.change?.resultingOwners[2].fingerprint = ownerA.fingerprint
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
}

@Test func membershipApprovalRequiresExactAuthorizerAndCandidatePairInEitherDirection() {
    var projection = phoneReview(.reviewMembership)
    projection.peer = ownerC
    projection.change = PhoneMembershipChange(kind: .add, candidate: ownerC, resultingOwners: [ownerA, ownerB, ownerC])
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == nil)
    projection.localIdentity = ownerC; projection.peer = ownerA
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == nil)
    projection.localIdentity = ownerA; projection.peer = ownerB
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
    projection.localIdentity = ownerB; projection.peer = ownerC
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
    projection.localIdentity = ownerA; projection.peer = ownerC
    projection.localIdentity?.rootKeyEpoch += 1
    #expect(projection.rejection(for: .approveMembership(phoneBinding), now: phoneNow) == .invalidAction)
}

@Test func accountActionsRequireMatchingActiveLocalRootAndProtectSelfDespiteDisplayFlags() {
    var projection = phoneCommitted(); projection.phase = .owners
    projection.localIdentity = ownerC
    #expect(projection.rejection(for: .signIn(accountID: "account-1", membershipRevision: 2), now: phoneNow) == .invalidAction)
    #expect(projection.rejection(for: .beginOwnerChange(.add, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: nil), now: phoneNow) == .invalidAction)
    projection.localIdentity = ownerA; projection.localIdentity?.revoked = true
    #expect(projection.rejection(for: .signIn(accountID: "account-1", membershipRevision: 2), now: phoneNow) == .invalidAction)
    projection.localIdentity = ownerB
    projection.owners[0].isCurrent = false; projection.owners[1].isCurrent = false
    #expect(projection.rejection(for: .beginOwnerChange(.replace, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: ownerB.id), now: phoneNow) == .invalidAction)
}

@Test func ownerChangesProtectSelfAndTwoOwnerMinimum() {
    var projection = phoneCommitted(); projection.phase = .owners
    #expect(projection.rejection(for: .beginOwnerChange(.replace, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: ownerA.id), now: phoneNow) == .invalidAction)
    #expect(projection.rejection(for: .beginOwnerChange(.revoke, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: ownerB.id), now: phoneNow) == .unavailable)
    #expect(projection.rejection(for: .beginOwnerChange(.replace, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: ownerB.id), now: phoneNow) == nil)
    #expect(projection.rejection(for: .beginOwnerChange(.add, accountID: "account-1", membershipRevision: 1,
        targetOwnerID: nil), now: phoneNow) == .staleBinding)
}

@Test func committedAccountOutlivesProposalDeadlineButRequiresVerifiedReceiptForSignIn() {
    var projection = phoneCommitted()
    #expect(projection.rejection(for: .signIn(accountID: "account-1", membershipRevision: 2), now: phoneBinding.expiresAt + 1) == nil)
    projection.phase = .owners
    #expect(projection.rejection(for: .beginOwnerChange(.add, accountID: "account-1", membershipRevision: 2,
        targetOwnerID: nil), now: phoneBinding.expiresAt + 1) == nil)
    projection.receipt = nil
    #expect(projection.rejection(for: .signIn(accountID: "account-1", membershipRevision: 2), now: phoneNow) == .invalidAction)
    projection.receipt = phoneCommitted().receipt; projection.receipt?.verified = false
    #expect(projection.rejection(for: .signIn(accountID: "account-1", membershipRevision: 2), now: phoneNow) == .invalidAction)
}

@Test func trustFailureAndUnknownOutcomeNeverOfferAnotherApproval() {
    var projection = phoneReview()
    for phase in [PhoneProtocolPhase.trustUnavailable, .revoked, .outcomeUnknown] {
        projection.phase = phase
        #expect(projection.rejection(for: .approveGenesis(phoneBinding), now: phoneNow) != nil)
        #expect(projection.rejection(for: .refresh, now: phoneNow) == nil)
    }
    projection.lastRequestID = "original-request"
    #expect(projection.rejection(for: .recover(requestID: "original-request"), now: phoneNow) == nil)
    #expect(projection.rejection(for: .recover(requestID: "different-request"), now: phoneNow) == .staleBinding)
}

@Test func lostMutationResponseRetainsOriginalRequestAndOnlyRecoversThatOutcome() async throws {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    await service.fail()
    let unknown = await store.send(.approveGenesis(phoneBinding))
    let requestID = try #require(unknown.lastRequestID)
    #expect(unknown.phase == .outcomeUnknown && unknown.failure == .outcomeUnknown)
    #expect(await service.requests().last?.requestID == requestID)
    #expect(await store.send(.approveGenesis(phoneBinding)).failure == .outcomeUnknown)
    #expect(await store.send(.recover(requestID: "wrong-request")).failure == .staleBinding)
    #expect(await service.requests().count == 2)
    await service.set(phoneCommitted())
    let recovered = await store.send(.recover(requestID: requestID))
    #expect(recovered.phase == .committed && recovered.receipt?.verified == true)
    #expect(recovered.lastRequestID == nil)
    #expect(await service.requests().last?.requestID == requestID)
    #expect(await service.requests().filter { !$0.action.isReadOnly }.count == 1)
}

@Test func knownSuccessfulAndRejectedResultsDoNotInventARecoverableRequest() async {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    var cancelled = phoneReview(.cancelled)
    await service.set(cancelled)
    let terminal = await store.send(.cancel(phoneBinding))
    #expect(terminal.phase == .cancelled && terminal.lastRequestID == nil)
    #expect(terminal.rejection(for: .resume(phoneBinding), now: phoneNow) == nil)
    cancelled.phase = .trustUnavailable; cancelled.failure = .trustUnavailable
    await service.set(cancelled)
    let rejected = await store.send(.restart)
    #expect(rejected.phase == .trustUnavailable && rejected.lastRequestID == nil)
    #expect(rejected.failure == .trustUnavailable)
}

@Test func serviceReportedUnknownOutcomeCannotEraseLocallyTrackedRequestID() async throws {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    var response = phoneReview(.outcomeUnknown); response.lastRequestID = nil
    await service.set(response)
    let unknown = await store.send(.approveGenesis(phoneBinding))
    let requestID = try #require(unknown.lastRequestID)
    let requests = await service.requests()
    #expect(requestID == requests.last?.requestID)
    #expect(unknown.rejection(for: .recover(requestID: requestID), now: phoneNow) == nil)
}

@Test func concurrentPhoneActionsAreRejectedUntilOriginalRequestCompletes() async {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    await service.pause()
    let first = Task { await store.send(.approveGenesis(phoneBinding)) }
    await service.waitUntilStarted()
    #expect(await store.snapshot().busy)
    #expect(await store.send(.approveGenesis(phoneBinding)).failure == .busy)
    #expect(await store.send(.refresh).failure == .busy)
    #expect(await service.requests().count == 2)
    await service.resume(); _ = await first.value
    #expect(await store.snapshot().busy == false)
}

@Test func clearPhoneSessionDropsLateMutationResponseWithoutOverwritingNewSession() async {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    await service.set(phoneCommitted())
    await service.pause()
    let oldRequest = Task { await store.send(.approveGenesis(phoneBinding)) }
    await service.waitUntilStarted()
    await store.clearSession()
    #expect(await store.snapshot().availability == .notImplemented)
    var newSession = PhoneProtocolSnapshot(availability: .browserReadOnly)
    newSession.authorityID = "new-session-authority"
    await service.set(newSession)
    _ = await store.send(.refresh)
    await service.resume(); _ = await oldRequest.value
    let current = await store.snapshot()
    #expect(current == newSession)
    #expect(current.receipt == nil && current.lastRequestID == nil && !current.busy)
}

@Test(arguments: ["unverified", "account", "digest", "operation", "sequence", "hash"])
func malformedCommitProjectionCannotReplaceLastVerifiedState(fault: String) async {
    let service = PhoneServiceFixture(phoneReview())
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    var response = phoneCommitted()
    switch fault {
    case "unverified": response.receipt?.verified = false
    case "account": response.receipt?.accountID = "another-account"
    case "digest": response.receipt?.proposalDigest = "another-digest"
    case "operation": response.receipt?.operationID = "another-operation"
    case "sequence": response.receipt?.ledgerSequence = 0
    default: response.receipt?.ledgerHash = ""
    }
    await service.set(response)
    let rejected = await store.send(.refresh)
    #expect(rejected.failure == .invalidProjection)
    #expect(rejected.phase == .reviewGenesis && rejected.receipt == nil)
}

@Test func invitationDescriptionsDoNotExposeTransientSecret() {
    let secret = "https://authority.example/pair#private-pairing-secret"
    let input = PhoneInvitationInput(secretLink: secret)
    #expect(!String(describing: input).contains(secret))
    #expect(!String(reflecting: input).contains(secret))
}

@Test(arguments: ["membership", "bindingRevision", "bindingDigest"])
func refreshedPhoneProjectionCannotRollBackVerifiedMembershipOrRebindSameRevision(fault: String) async {
    let original = phoneReview()
    let service = PhoneServiceFixture(original)
    let store = PhoneProtocolStore(service: service, clock: { phoneNow })
    _ = await store.send(.refresh)
    var stale = original
    switch fault {
    case "membership": stale.membershipRevision -= 1; stale.binding?.objectID = "different-proposal"
    case "bindingRevision": stale.binding?.revision -= 1
    default: stale.binding?.digest = String(repeating: "b", count: 64)
    }
    await service.set(stale)
    let result = await store.send(.refresh)
    #expect(result.failure == .invalidProjection)
    #expect(result.binding == original.binding && result.membershipRevision == original.membershipRevision)
}
