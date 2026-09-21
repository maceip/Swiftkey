import Foundation
import Testing
import SwiftUICore
import SwiftKeyApplication
@testable import SwiftKeyUI

private let viewNow: UInt64 = 100
private let viewBinding = PhoneProtocolBinding(objectID: "operation-ui-test", revision: 3,
    digest: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", expiresAt: 500)
private let viewLocal = PhoneIdentity(id: "local", label: "Current phone", fingerprint: String(repeating: "1", count: 64),
    trust: "Verified test projection", rootKeyEpoch: 7, isCurrent: true)
private let viewPeer = PhoneIdentity(id: "peer", label: "Other phone", fingerprint: String(repeating: "2", count: 64), trust: "Verified test projection")
private let viewCandidate = PhoneIdentity(id: "candidate", label: "New phone", fingerprint: String(repeating: "3", count: 64), trust: "Verified test projection")
private func viewSnapshot(_ phase: PhoneProtocolPhase) -> PhoneProtocolSnapshot {
    PhoneProtocolSnapshot(phase: phase, availability: .nativeReady, binding: viewBinding,
        authorityID: "authority-test", origin: "https://authority.example", audience: "native-test",
        accountID: "account-test", accountLabel: "Personal", membershipRevision: 9, authorizingOwnerID: viewLocal.id,
        localIdentity: viewLocal, peer: viewPeer, owners: [viewLocal, viewPeer])
}

@Suite @MainActor struct PhoneProtocolViewTests {
    @Test func fullFlowUsesOnlyPortablePrimitivesAndNeverPerformsAnActionOnRender() {
        let allowed: Set<String> = ["Text", "VStack", "HStack", "ScrollView", "Spacer", "Shape", "Button", "TextField", "Group", "EmptyView"]
        for phase in PhoneProtocolPhase.allCases {
            let harness = PhoneHarness(viewSnapshot(phase))
            let tree = harness.host().evaluate()
            #expect(Set(allNodes(tree).map(\.type)).isSubset(of: allowed))
            #expect(harness.actions.isEmpty && harness.effects.isEmpty)
            #expect(allNodes(tree).contains { phoneSemanticID($0) == "phone.protocol.\(phase.rawValue)" })
        }
    }
    @Test func comparisonDisplaysFullFingerprintsAndCodeThenDispatchesExactBinding() throws {
        let harness = PhoneHarness(viewSnapshot(.comparePeers))
        let rendered = harness.host(), tree = rendered.evaluate()
        let texts = phoneTexts(tree)
        #expect(texts.contains(viewLocal.fingerprint) && texts.contains(viewPeer.fingerprint))
        #expect(texts.contains("0123 4567 89AB CDEF 0123"))
        #expect(texts.contains(viewBinding.digest))
        rendered.callbacks.invokeVoid(try phoneCallback(tree, "phone.confirm-peers"))
        rendered.callbacks.invokeVoid(try phoneCallback(tree, "phone.reject-peers"))
        #expect(harness.actions == [.confirmPeers(viewBinding), .rejectPeers(viewBinding)])
    }
    @Test func expiredBusyAndBrowserApprovalsCannotDispatchEvenIfCallbackIsInvoked() throws {
        var states = [viewSnapshot(.comparePeers), viewSnapshot(.comparePeers), viewSnapshot(.comparePeers)]
        states[0].binding?.expiresAt = viewNow
        states[1].busy = true
        states[2].availability = .browserReadOnly
        for state in states {
            let harness = PhoneHarness(state), host = harness.host(), tree = host.evaluate()
            let button = try phoneNode(tree, "phone.confirm-peers")
            #expect(button.modifiers.contains(ModifierNode(kind: "disabled", args: ["value": .bool(true)])))
            host.callbacks.invokeVoid(try phoneCallback(tree, "phone.confirm-peers"))
            #expect(harness.actions.isEmpty)
        }
    }
    @Test func invitationEffectsAreExplicitAndDoNotExposeCapabilityInSnapshotOrTree() throws {
        let harness = PhoneHarness(viewSnapshot(.invitation)), host = harness.host(), tree = host.evaluate()
        #expect(harness.effects.isEmpty)
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.show-invitation"))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.scan"))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.manual-import"))
        #expect(harness.effects == [.presentInvitation(viewBinding), .scanInvitation, .enterInvitation])
        #expect(harness.actions.isEmpty)
        #expect(!phoneTexts(tree).contains { $0.contains("#secret") })
        let encoded = String(decoding: try JSONEncoder().encode(harness.snapshot), as: UTF8.self)
        #expect(!encoded.contains("secretLink") && !encoded.contains("bootstrapToken"))
        let absent = harness.host(capabilities: []).evaluate()
        #expect(!allNodes(absent).contains { phoneSemanticID($0) == "phone.show-invitation" })
        #expect(phoneTexts(absent).contains("Secure QR and link presentation is unavailable on this host."))
    }
    @Test func nameProposalAndReplacementBindBothLabelAndCurrentObject() throws {
        var snapshot = viewSnapshot(.paired); snapshot.accountID = nil
        let harness = PhoneHarness(snapshot), host = harness.host()
        var tree = host.evaluate()
        host.callbacks.invokeString(try phoneCallback(tree, "phone.account-label", "onChange"), "Shared account")
        tree = host.evaluate()
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.propose-account"))
        #expect(harness.actions == [.proposeAccount(viewBinding, label: "Shared account", policy: .survivor)])
        let replace = PhoneHarness(viewSnapshot(.reviewGenesis)); replace.drafts.accountLabel = "New label"
        let replaceHost = replace.host(), replaceTree = replaceHost.evaluate()
        replaceHost.callbacks.invokeVoid(try phoneCallback(replaceTree, "phone.replace-genesis"))
        #expect(replace.actions == [.replaceGenesis(viewBinding, label: "New label", policy: .survivor)])
    }
    @Test func importingBeforePreparationRequiresExplicitFinalRootBeforeJoin() throws {
        var state = viewSnapshot(.inspectInvitation); state.localIdentity = nil
        let harness = PhoneHarness(state), host = harness.host(), tree = host.evaluate()
        #expect(!phoneTexts(tree).contains(viewPeer.fingerprint))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.prepare-import"))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.join"))
        #expect(harness.actions == [.prepareIdentity])
    }
    @Test func existingAccountInspectionShowsRosterPolicyAndExactLostRootBeforeJoin() {
        var state = viewSnapshot(.inspectInvitation)
        state.peer = viewCandidate
        state.change = PhoneMembershipChange(kind: .replace, targetOwnerID: viewPeer.id, candidate: viewCandidate,
            resultingOwners: [viewLocal, viewCandidate])
        let texts = phoneTexts(PhoneHarness(state).host().evaluate())
        #expect(texts.contains(viewPeer.fingerprint))
        #expect(texts.contains("Exact lost root epoch"))
        #expect(texts.contains("9"))
        #expect(texts.contains(PhoneOwnershipPolicy.survivor.warning))
        #expect(texts.contains("Authorizing current owner"))
    }
    @Test func ownerAndCandidateGetDistinctExplicitMembershipApprovals() throws {
        var state = viewSnapshot(.reviewMembership)
        state.peer = viewCandidate
        state.change = PhoneMembershipChange(kind: .replace, targetOwnerID: viewPeer.id, candidate: viewCandidate,
            resultingOwners: [viewLocal, viewCandidate])
        let owner = PhoneHarness(state), ownerHost = owner.host(), ownerTree = ownerHost.evaluate()
        #expect(phoneTexts(ownerTree).contains("Approve atomic owner replacement"))
        ownerHost.callbacks.invokeVoid(try phoneCallback(ownerTree, "phone.approve-membership"))
        #expect(owner.actions == [.approveMembership(viewBinding)])
        state.localIdentity = viewCandidate; state.peer = viewLocal
        let candidate = PhoneHarness(state), candidateHost = candidate.host(), candidateTree = candidateHost.evaluate()
        #expect(phoneTexts(candidateTree).contains("Join this account as an owner"))
        candidateHost.callbacks.invokeVoid(try phoneCallback(candidateTree, "phone.approve-membership"))
        #expect(candidate.actions == [.approveMembership(viewBinding)])
    }
    @Test func committedReceiptDeadlineDoesNotMarkOwnerAccessExpired() {
        var state = viewSnapshot(.owners)
        state.binding?.expiresAt = 50
        state.receipt = PhoneCommitReceipt(operationID: viewBinding.objectID, accountID: "account-test", proposalDigest: viewBinding.digest,
            ledgerSequence: 4, ledgerHash: "test-ledger-hash", verified: true)
        let tree = PhoneHarness(state).host().evaluate()
        #expect(!allNodes(tree).contains { phoneSemanticID($0) == "phone.deadline-passed" })
        #expect(phoneTexts(tree).contains("Historical review deadline · account access requires current membership and trust checks"))
    }
    @Test func expiredLeaseCanExplicitlyRenewRetainedIdentityWithoutApprovingOwnership() throws {
        let state = viewSnapshot(.trustUnavailable)
        let harness = PhoneHarness(state), host = harness.host(), tree = host.evaluate()
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.renew-identity"))
        #expect(harness.actions == [.renewIdentity])
        #expect(state.rejection(for: .approveGenesis(viewBinding), now: viewNow) == .trustUnavailable)
    }
    @Test func failedAdmissionCannotRenewAnIdentityThatWasNeverAdmitted() {
        var state = viewSnapshot(.trustUnavailable)
        state.localIdentity = nil; state.binding = nil; state.accountID = nil
        let tree = PhoneHarness(state).host().evaluate()
        #expect(allNodes(tree).contains { phoneSemanticID($0) == "phone.admission-unavailable" })
        #expect(!allNodes(tree).contains { phoneSemanticID($0) == "phone.renew-identity" })
        #expect(!allNodes(tree).contains { phoneSemanticID($0) == "phone.prepare" })
    }
    @Test func ownerSurfacesShowCredentialStatusSeparatelyFromAccountReceipt() {
        var state = viewSnapshot(.owners)
        state.credentialStatus = "No current epoch credential"
        let tree = PhoneHarness(state).host().evaluate()
        #expect(phoneTexts(tree).contains("No current epoch credential"))
        #expect(allNodes(tree).contains { phoneSemanticID($0) == "phone.credential-status" })
    }
    @Test func ownerCanRetrySignInAndCredentialWithoutRecreatingCommittedAccount() throws {
        var state = viewSnapshot(.owners)
        state.credentialStatus = "No current epoch credential"
        state.receipt = PhoneCommitReceipt(operationID: viewBinding.objectID, accountID: "account-test", proposalDigest: viewBinding.digest,
            ledgerSequence: 4, ledgerHash: "test-ledger-hash", verified: true)
        let harness = PhoneHarness(state), host = harness.host(), tree = host.evaluate()
        #expect(phoneTexts(tree).contains("Refresh sign-in and epoch credential"))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.refresh-sign-in"))
        #expect(harness.actions == [.signIn(accountID: "account-test", membershipRevision: 9)])
    }
    @Test func decliningUnjoinedInvitationClearlyDescribesLocalEffect() throws {
        let harness = PhoneHarness(viewSnapshot(.inspectInvitation)), host = harness.host(), tree = host.evaluate()
        #expect(phoneTexts(tree).contains("Decline invitation on this phone"))
        #expect(!phoneTexts(tree).contains("Cancel this operation"))
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.cancel"))
        #expect(harness.actions == [.cancel(viewBinding)])
    }
    @Test func receiptMismatchNeverClaimsVerifiedOrOffersSignIn() {
        var state = viewSnapshot(.committed)
        state.receipt = PhoneCommitReceipt(operationID: "different-operation", accountID: "account-test", proposalDigest: viewBinding.digest,
            ledgerSequence: 4, ledgerHash: "test-ledger-hash", verified: true)
        let tree = PhoneHarness(state).host().evaluate()
        #expect(!phoneTexts(tree).contains("Receipt verified by the native protocol adapter"))
        #expect(!allNodes(tree).contains { phoneSemanticID($0) == "phone.sign-in" })
    }
    @Test func unknownOutcomeOnlyRecoversOriginalRequestAndUnsupportedWorkStaysUnavailable() throws {
        var state = viewSnapshot(.outcomeUnknown); state.lastRequestID = "original-request"
        let harness = PhoneHarness(state), host = harness.host(), tree = host.evaluate()
        host.callbacks.invokeVoid(try phoneCallback(tree, "phone.recover"))
        #expect(harness.actions == [.recover(requestID: "original-request")])
        #expect(!allNodes(tree).contains { phoneSemanticID($0) == "phone.restart" })
        for phase in [PhoneProtocolPhase.reviewBrowserLogin, .reviewPolicy] {
            let preview = PhoneHarness(viewSnapshot(phase)).host().evaluate()
            #expect(!allNodes(preview).contains { $0.type == "Button" })
        }
        let revoke = PhoneHarness(viewSnapshot(.reviewRevocation)), revokeHost = revoke.host(), revokeTree = revokeHost.evaluate()
        revokeHost.callbacks.invokeVoid(try phoneCallback(revokeTree, "phone.approve-revocation"))
        #expect(revoke.actions.isEmpty)
    }
}

private final class PhoneHarness {
    var drafts = PhoneProtocolDrafts()
    let snapshot: PhoneProtocolSnapshot
    var actions: [PhoneProtocolAction] = []
    var effects: [PhoneProtocolEffect] = []
    init(_ snapshot: PhoneProtocolSnapshot) { self.snapshot = snapshot }
    func host(capabilities: Set<PhoneHostCapability> = Set(PhoneHostCapability.allCases)) -> ViewHost {
        ViewHost(PhoneProtocolView(snapshot: snapshot, drafts: Binding(get: { self.drafts }, set: { self.drafts = $0 }), now: viewNow,
            effects: capabilities, onAction: { self.actions.append($0) }, onEffect: { self.effects.append($0) }))
    }
}
private func phoneSemanticID(_ node: RenderNode) -> String? {
    for modifier in node.modifiers where modifier.kind == "accessibilityIdentifier" {
        if case .string(let id) = modifier.args["id"] { return id }
    }
    return nil
}
private func phoneNode(_ tree: RenderNode, _ id: String) throws -> RenderNode {
    try #require(allNodes(tree).first { phoneSemanticID($0) == id })
}
private func phoneCallback(_ tree: RenderNode, _ id: String, _ property: String = "onTap") throws -> Int64 {
    let node = try phoneNode(tree, id)
    guard case .int(let value) = node.props[property] else { throw PhoneTestError.callbackMissing }
    return Int64(value)
}
private enum PhoneTestError: Error { case callbackMissing }
private func phoneTexts(_ tree: RenderNode) -> [String] {
    allNodes(tree).compactMap { if case .string(let value) = $0.props["text"] { value } else { nil } }
}
