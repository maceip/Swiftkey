import Foundation
import Testing
import SwiftUICore
import SwiftKeyCore
import SwiftKeyApplication
@testable import SwiftKeyUI

@Suite @MainActor struct WorkspaceTests {
    @Test func pairingCutoverRemovesLegacyCreationControls() throws {
        for allowed in [nil, true, false] as [Bool?] {
            let fixture = try Fixture(legacyProvisioningAllowed: allowed)
            let harness = Harness(snapshot: fixture.snapshot()), tree = harness.host().evaluate()
            #expect(allNodes(tree).contains { semanticID($0) == "swiftkey.create-account" } == (allowed != false))
            #expect(allNodes(tree).contains { semanticID($0) == "swiftkey.account-label" } == (allowed != false))
            #expect(textValues(tree).contains("Pair two phones in the native app to create an account") == (allowed == false))
            #expect(harness.actions.isEmpty)
        }
    }
    @Test func accountFormAndSelectionDispatchTypedActions() throws {
        let fixture = try Fixture()
        let harness = Harness(snapshot: fixture.snapshot())
        let host = harness.host()
        var tree = host.evaluate()
        host.callbacks.invokeString(try callback(tree, "swiftkey.account-label", "onChange"), "Actual account request")
        #expect(harness.drafts.accountLabel == "Actual account request")
        tree = host.evaluate()
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.create-account", "onTap"))
        #expect(harness.actions == [.createAccount("Actual account request")])
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.account.\(fixture.account.accountID)", "onTap"))
        #expect(harness.actions.last == .selectAccount(fixture.account.accountID))
        #expect(harness.drafts.selectedSection == "devices")
    }

    @Test func filteringIsSwiftOwnedAndHasNoSyntheticFallback() throws {
        let fixture = try Fixture()
        let harness = Harness(snapshot: fixture.snapshot())
        let host = harness.host()
        let initial = host.evaluate()
        host.callbacks.invokeString(try callback(initial, "swiftkey.account-filter", "onChange"), "does-not-match")
        let texts = textValues(host.evaluate())
        #expect(texts.contains("No matching accounts"))
        #expect(!texts.contains(fixture.account.label))
        #expect(!texts.contains(fixture.account.accountID))

        let empty = Harness(snapshot: WorkspaceSnapshot()).host().evaluate()
        #expect(textValues(empty).contains("Workspace not loaded"))
        #expect(!allNodes(empty).contains { semanticID($0)?.hasPrefix("swiftkey.account.") == true })
    }

    @Test func devicesUseCompleteSharedPublicKeyAndServerReissueCapability() throws {
        let fixture = try Fixture()
        let harness = Harness(snapshot: fixture.snapshot())
        harness.drafts.selectedSection = "devices"
        let host = harness.host(), tree = host.evaluate()
        #expect(textValues(tree).contains(SwiftKeyPublicKeyView.groupedHex(fixture.publicKey)))
        #expect(!allNodes(tree).contains { semanticID($0) == "swiftkey.reissue-invitation" })
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.copy-root.device-test", "onTap"))
        #expect(harness.effects == [.copyPublicKey(fixture.publicKey)])

        let pending = AccountSummary(accountID: "pending-test", label: "Pending test", createdAt: 100,
            status: "pending", deviceCount: 0, activeDeviceCount: 0, imported: false, canReissueInvitation: true)
        let pendingHarness = Harness(snapshot: fixture.snapshot(account: pending))
        pendingHarness.drafts.selectedSection = "devices"
        let pendingHost = pendingHarness.host(), pendingTree = pendingHost.evaluate()
        pendingHost.callbacks.invokeVoid(try callback(pendingTree, "swiftkey.reissue-invitation", "onTap"))
        #expect(pendingHarness.actions == [.reissueInvitation("pending-test")])
    }

    @Test func credentialVerificationDispatchesExactCredentialAndChecksReceiptHash() throws {
        let fixture = try Fixture()
        let harness = Harness(snapshot: fixture.snapshot())
        harness.drafts.selectedSection = "epochs"
        let host = harness.host(), tree = host.evaluate()
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.verify.device-test.1", "onTap"))
        #expect(harness.actions == [.verifyCredential(fixture.credential)])
        #expect(!textValues(tree).contains { $0.hasPrefix("Verified by authority") })

        let valid = CredentialVerificationResponse(accountID: "account-test", deviceID: "device-test", epoch: 1,
            checkedAt: 120, validUntil: 600, credentialHash: ProtocolCrypto.sha256(try fixture.credential.canonicalBytes()))
        let verified = Harness(snapshot: fixture.snapshot(verification: valid))
        verified.drafts.selectedSection = "epochs"
        #expect(textValues(verified.host().evaluate()).contains { $0.hasPrefix("Verified by authority") })
        let wrong = CredentialVerificationResponse(accountID: "account-test", deviceID: "device-test", epoch: 1,
            checkedAt: 120, validUntil: 600, credentialHash: Data(repeating: 0, count: 32))
        let unverified = Harness(snapshot: fixture.snapshot(verification: wrong))
        unverified.drafts.selectedSection = "epochs"
        #expect(!textValues(unverified.host().evaluate()).contains { $0.hasPrefix("Verified by authority") })
    }

    @Test func invitationSecretsAppearOnlyFromTransientResultAndExportIsExplicit() throws {
        let fixture = try Fixture()
        let invitation = CreateAccountResponse(account: fixture.account, enrollmentToken: "test-only-enrollment-secret", expiresAt: 500)
        let harness = Harness(snapshot: fixture.snapshot(), invitation: invitation)
        let host = harness.host(), tree = host.evaluate()
        #expect(harness.actions.isEmpty && harness.effects.isEmpty)
        #expect(textValues(tree).contains(invitation.enrollmentToken))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.export-enrollment", "onTap"))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.copy-invitation", "onTap"))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.dismiss-invitation", "onTap"))
        #expect(harness.actions == [.exportEnrollmentBundle, .dismissInvitation])
        #expect(harness.effects == [.copyInvitation(invitation)])
        #expect(!textValues(Harness(snapshot: fixture.snapshot()).host().evaluate()).contains(invitation.enrollmentToken))
    }

    @Test func ledgerActionsUseRealPageAndUnsupportedEffectsAreHidden() throws {
        let fixture = try Fixture()
        let harness = Harness(snapshot: fixture.snapshot())
        harness.drafts.selectedSection = "ledger"
        let host = harness.host(), tree = host.evaluate()
        #expect(textValues(tree).contains("1 · device.enrolled"))
        #expect(textValues(tree).contains(SwiftKeyPublicKeyView.groupedHex(fixture.ledger.head.hash)))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.ledger-first", "onTap"))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.ledger-next", "onTap"))
        host.callbacks.invokeVoid(try callback(tree, "swiftkey.export-ledger", "onTap"))
        #expect(harness.actions == [.firstLedgerPage, .nextLedgerPage])
        #expect(harness.effects == [.exportLedger(fixture.ledger)])
        #expect(try node(tree, "swiftkey.ledger-previous").modifiers.contains(ModifierNode(kind: "disabled", args: ["value": .bool(true)])))
        let withoutEffects = harness.host(supportsEffects: false).evaluate()
        #expect(!allNodes(withoutEffects).contains { semanticID($0) == "swiftkey.export-ledger" })
    }

    @Test func allSectionsStayWithinThePortableRendererContract() throws {
        let fixture = try Fixture()
        let allowed: Set<String> = ["Text", "VStack", "HStack", "ScrollView", "Spacer", "Shape", "Button", "TextField", "Picker", "DisclosureGroup", "Group", "EmptyView"]
        for section in ["accounts", "devices", "epochs", "ledger", "authority"] {
            let harness = Harness(snapshot: fixture.snapshot())
            harness.drafts.selectedSection = section
            let tree = harness.host().evaluate()
            #expect(Set(allNodes(tree).map(\.type)).isSubset(of: allowed))
            #expect(allNodes(tree).filter { $0.type == "Shape" }.allSatisfy { $0.props["shape"] == .string("rectangle") })
        }
    }

    @Test func staleRecordsAreNotPresentedAsOnline() throws {
        let fixture = try Fixture()
        let failed = WorkspaceSnapshot(phase: .stale, workspace: fixture.overview(),
            error: WorkspaceFailure(code: "networkUnavailable", message: "Unable to contact authority."))
        let texts = textValues(Harness(snapshot: failed).host().evaluate())
        #expect(texts.contains("Showing the last loaded records · the latest request did not complete"))
        #expect(texts.contains("Unable to contact authority."))
        #expect(!texts.contains { $0.hasPrefix("Authority checked at") })
    }
}

private final class Harness {
    var drafts = WorkspaceDrafts()
    var actions: [WorkspaceAction] = []
    var effects: [WorkspaceUIEffect] = []
    let snapshot: WorkspaceSnapshot
    let invitation: CreateAccountResponse?
    init(snapshot: WorkspaceSnapshot, invitation: CreateAccountResponse? = nil) {
        self.snapshot = snapshot; self.invitation = invitation
    }
    func host(supportsEffects: Bool = true) -> ViewHost {
        ViewHost(WorkspaceView(snapshot: snapshot,
            drafts: Binding(get: { self.drafts }, set: { self.drafts = $0 }), invitation: invitation,
            onAction: { self.actions.append($0) }, onEffect: supportsEffects ? { self.effects.append($0) } : nil))
    }
}

private struct Fixture {
    let publicKey: Data
    let account: AccountSummary
    let credential: EpochCredential
    let ledger: LedgerPage
    let status: AuthorityStatus

    init(legacyProvisioningAllowed: Bool? = nil) throws {
        // Explicit test fixture. No real attestation or production authority is
        // involved; signatures here exist only to exercise presentation.
        publicKey = SoftwareSigningKey().publicKey
        account = AccountSummary(accountID: "account-test", label: "Test account", createdAt: 100,
            status: "active", deviceCount: 1, activeDeviceCount: 1, imported: false)
        let delegation = EpochDelegation(accountID: "account-test", deviceID: "device-test", epoch: 1, publicKey: publicKey)
        let challenge = ChallengeEnvelope(accountID: "account-test", deviceID: "device-test", operation: .issueEpoch,
            sequence: 0, nonce: Data(repeating: 1, count: 32), expiresAt: 600, payloadHash: ProtocolCrypto.sha256(try delegation.canonicalBytes()))
        credential = EpochCredential(delegation: delegation,
            authorization: RootAuthorization(kind: .androidStrongBoxP256, challenge: challenge, signature: Data([1, 2])), serverSignature: Data([3, 4]))
        let head = SignedLedgerHead(sequence: 1, hash: Data(repeating: 5, count: 32), signature: Data([6]))
        let event = LedgerEvent(sequence: 1, timestamp: 100, kind: "device.enrolled", accountID: "account-test",
            deviceID: "device-test", actorDeviceID: nil, details: ["platform": "test-fixture"],
            previousHash: Data(repeating: 0, count: 32), hash: head.hash)
        ledger = LedgerPage(events: [event], nextAfter: 1, hasMore: true, head: head)
        status = AuthorityStatus(serverPublicKey: publicKey, unixTime: 120, epoch: 1, epochStart: 100, epochEnd: 600,
            accountCount: 1, activeDeviceCount: 1, revokedDeviceCount: 0, credentialCount: 1, ledgerHead: head, storage: "sqlite", schemaVersion: 2,
            legacyProvisioningAllowed: legacyProvisioningAllowed)
    }
    func overview(account selected: AccountSummary? = nil) -> WorkspaceOverview {
        let selected = selected ?? account
        let device = DeviceSummary(accountID: selected.accountID, deviceID: "device-test", publicKey: publicKey,
            sequence: 1, status: "active", enrolledAt: 100, revokedAt: nil, lastEpoch: 1)
        let epoch = EpochSummary(accountID: selected.accountID, deviceID: "device-test", epoch: 1, publicKey: publicKey,
            previousPublicKeyHash: nil, validFrom: 100, validUntil: 600, issuedAt: 100, status: "current", credential: credential)
        return WorkspaceOverview(status: status, accounts: [selected], selectedAccountID: selected.accountID,
            devices: selected.deviceCount > 0 ? [device] : [], epochs: selected.deviceCount > 0 ? [epoch] : [], ledger: ledger,
            serverURL: "http://127.0.0.1:8080", audience: "test.audience", workloadDomain: "test.workload")
    }
    func snapshot(account: AccountSummary? = nil, verification: CredentialVerificationResponse? = nil) -> WorkspaceSnapshot {
        WorkspaceSnapshot(phase: .ready, workspace: overview(account: account), verification: verification)
    }
}

private func semanticID(_ node: RenderNode) -> String? {
    for modifier in node.modifiers where modifier.kind == "accessibilityIdentifier" {
        if case .string(let id) = modifier.args["id"] { return id }
    }
    return nil
}
private func node(_ tree: RenderNode, _ id: String) throws -> RenderNode {
    try #require(allNodes(tree).first { semanticID($0) == id })
}
private func callback(_ tree: RenderNode, _ id: String, _ property: String) throws -> Int64 {
    let target = try node(tree, id)
    guard case .int(let value) = target.props[property] else { throw TestFailure.missingCallback }
    return Int64(value)
}
private enum TestFailure: Error { case missingCallback }
private func textValues(_ tree: RenderNode) -> [String] {
    allNodes(tree).compactMap { if case .string(let text) = $0.props["text"] { text } else { nil } }
}
