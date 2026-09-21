import Foundation
import SwiftUICore
import SwiftKeyApplication

/// Public form values only. Secret manual entry belongs to a host-owned secure
/// sheet and is submitted as PhoneInvitationInput, never through this Binding.
public struct PhoneProtocolDrafts: Sendable, Equatable {
    public var accountLabel: String
    public init(accountLabel: String = "") { self.accountLabel = accountLabel }
}
public enum PhoneHostCapability: String, Sendable, Hashable, CaseIterable { case camera, manualImport, invitationPresentation }
/// The host obtains/presents the short-lived capability in a separate secure
/// surface. A generic serialized BrowserTree must never contain the QR/link.
public enum PhoneProtocolEffect: Sendable, Equatable {
    case scanInvitation, enterInvitation, presentInvitation(PhoneProtocolBinding), dismissInvitation
}

/// Reusable pairing-first surfaces; separate from the existing legacy workspace.
/// Pass a verified service projection, the current time and explicit host
/// capabilities. Rendering a page never signs or submits an approval.
public struct PhoneProtocolView: View {
    public let snapshot: PhoneProtocolSnapshot
    public let drafts: Binding<PhoneProtocolDrafts>
    public let now: UInt64
    public let effects: Set<PhoneHostCapability>
    public let onAction: (PhoneProtocolAction) -> Void
    public let onEffect: ((PhoneProtocolEffect) -> Void)?
    public init(snapshot: PhoneProtocolSnapshot, drafts: Binding<PhoneProtocolDrafts>, now: UInt64,
                effects: Set<PhoneHostCapability> = [], onAction: @escaping (PhoneProtocolAction) -> Void,
                onEffect: ((PhoneProtocolEffect) -> Void)? = nil) {
        self.snapshot = snapshot; self.drafts = drafts; self.now = now; self.effects = effects
        self.onAction = onAction; self.onEffect = onEffect
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SwiftKeyPageHeader(title)
                availability
                if snapshot.busy { Text("Contacting the authority… Please wait.").accessibilityIdentifier("phone.busy") }
                if let failure = snapshot.failure { PhoneNotice(failure.message).accessibilityIdentifier("phone.failure") }
                if isExpired && pendingReview {
                    PhoneNotice("This review has expired. Check the original operation before starting again.")
                        .accessibilityIdentifier("phone.deadline-passed")
                }
                phaseContent
                if let status = snapshot.credentialStatus, [.owners, .committed, .signIn].contains(snapshot.phase) {
                    PhonePanel {
                        Text("Epoch credential").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                        Text(status)
                    }.accessibilityIdentifier("phone.credential-status")
                }
                if snapshot.binding != nil { operationDetails }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(EdgeInsets(top: 28, leading: SwiftKeyAppearance.pageInset, bottom: 40, trailing: SwiftKeyAppearance.pageInset))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwiftKeyAppearance.canvas).foregroundColor(SwiftKeyAppearance.ink)
        .font(SwiftKeyAppearance.body()).lineHeight(28).tracking(0.3)
        .accessibilityIdentifier("phone.protocol.\(snapshot.phase.rawValue)")
    }
    private var isExpired: Bool { snapshot.binding.map { now >= $0.expiresAt } ?? false }
    private var pendingReview: Bool {
        [.invitation, .inspectInvitation, .comparePeers, .waitingForPairConsent, .paired, .reviewGenesis,
         .waitingForGenesisConsent, .reviewMembership, .waitingForMembershipConsent, .reviewRevocation].contains(snapshot.phase)
    }
    private var effectEnabled: Bool {
        snapshot.availability == .nativeReady && !snapshot.busy && !isExpired
            && ![.outcomeUnknown, .trustUnavailable, .revoked].contains(snapshot.phase)
    }
    private var title: String {
        switch snapshot.phase {
        case .introduction: "Pair another device"
        case .preparingIdentity: "Prepare this phone"
        case .invitation: "Invite the other phone"
        case .importingInvitation: "Scan a pairing invitation"
        case .inspectInvitation: "Review the invitation"
        case .comparePeers: "Compare both phones"
        case .waitingForPairConsent: "Waiting for both confirmations"
        case .paired: snapshot.change == nil ? "Your phones are paired" : "Prepare the owner change"
        case .reviewGenesis: "Review your new account"
        case .waitingForGenesisConsent: "Waiting for account approvals"
        case .committed: "Check the committed receipt"
        case .signIn: "Sign in with this phone"
        case .owners: "Account owners"
        case .chooseOwnerChange: "Add or replace an owner"
        case .reviewMembership: snapshot.change?.kind == .replace ? "Review owner replacement" : "Review the additional owner"
        case .waitingForMembershipConsent: "Waiting for owner change approvals"
        case .reviewRevocation: "Review owner removal"
        case .reviewPolicy: "Review the ownership policy"
        case .reviewBrowserLogin: "Review browser access"
        case .renewingTrust: "Renew hardware trust"
        case .trustUnavailable: "Hardware trust unavailable"
        case .revoked: "This phone’s ownership was revoked"
        case .cancelled: "Pairing cancelled"
        case .rejected: "The operation was rejected"
        case .invalidated: "A fresh review is required"
        case .expired: "The operation expired"
        case .outcomeUnknown: "Check the original operation"
        }
    }
    @ViewBuilder private var availability: some View {
        if snapshot.availability == .notImplemented {
            PhoneNotice("Protocol preview · The v2 signing and authority service is not connected. No account or phone is added here.")
                .accessibilityIdentifier("phone.service-unavailable")
        } else if snapshot.availability == .browserReadOnly {
            PhoneNotice("Browser view · Continue on your native phone to sign. This browser and its operator session cannot approve ownership.")
                .accessibilityIdentifier("phone.browser-read-only")
        }
    }
    @ViewBuilder private var phaseContent: some View {
        switch snapshot.phase {
        case .introduction: introduction
        case .preparingIdentity: preparing
        case .invitation: invitation
        case .importingInvitation: importControls
        case .inspectInvitation: inspection
        case .comparePeers: comparison
        case .waitingForPairConsent: waiting("Each phone must explicitly confirm this exact pairing. Scanning the code is not consent.")
        case .paired: paired
        case .reviewGenesis: genesis
        case .waitingForGenesisConsent: waiting("The account exists only after both owners approve the same proposal and the authority commits it atomically.")
        case .committed: committed
        case .signIn: signIn
        case .owners, .chooseOwnerChange: ownerManagement
        case .reviewMembership: membership
        case .waitingForMembershipConsent: waiting("The current owner and candidate must approve the exact account, revision, policy and resulting roster. No owner is active before the atomic commit.")
        case .reviewRevocation: revocation
        case .reviewPolicy: policyReview
        case .reviewBrowserLogin: browserReview
        case .renewingTrust, .trustUnavailable: trust
        case .revoked: revoked
        case .cancelled, .rejected, .invalidated, .expired: terminal
        case .outcomeUnknown: unknown
        }
    }
    private var introduction: some View {
        PhonePanel {
            Text("Use two compatible native phones. Each keeps its own hardware identity; both become equal owners after they approve account creation.")
            Text("Have both phones nearby, online, and able to display the same peer details. An existing account uses Add or Replace from its owner list.")
            Text("No account exists during preparation or pairing.").foregroundColor(SwiftKeyAppearance.muted)
            PhoneNotice("Existing v1 accounts remain legacy. They cannot use this flow to bypass a v2 owner policy; a separately implemented upgrade is required.")
                .accessibilityIdentifier("phone.legacy-account")
            action("Prepare this phone", id: "prepare", .prepareIdentity)
            importControls
        }
    }
    private var preparing: some View {
        PhonePanel {
            Text("Creating or loading this phone’s final hardware root, checking the authority and validating attestation.")
            Text("Keep the app open. The app must retain this same root across restarts; preparing again must not silently replace it.")
            if let identity = snapshot.localIdentity { PhoneIdentityCard(identity: identity) }
            action("Check preparation", id: "refresh", .refresh)
        }
    }
    private var invitation: some View {
        PhonePanel {
            Text("The invitation joins a rendezvous. It grants no account access and does not approve the other phone.")
            if let identity = snapshot.localIdentity { PhoneIdentityCard(identity: identity) }
            if let binding = snapshot.binding {
                PhonePanel {
                    Text("Private QR / pairing link").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                    Text("Open the secure invitation surface on this phone. It presents the real short-lived QR and link outside shared snapshots and browser page data.")
                    if effects.contains(.invitationPresentation), onEffect != nil {
                        PhoneButton("Show QR and pairing link", id: "phone.show-invitation", disabled: !effectEnabled) {
                            if effectEnabled { onEffect?(.presentInvitation(binding)) }
                        }
                        PhoneButton("Hide invitation", id: "phone.hide-invitation", disabled: snapshot.busy) { onEffect?(.dismissInvitation) }
                    } else {
                        Text("Secure QR and link presentation is unavailable on this host.").foregroundColor(SwiftKeyAppearance.muted)
                    }
                }.accessibilityIdentifier("phone.invitation-surface")
                action("Check for the other phone", id: "refresh", .refresh)
                action("Rotate unused invitation", id: "rotate-invitation", .rotateUnjoinedSecret(binding))
                Text("Rotation is allowed only after the authority confirms nobody has joined. It invalidates the previous QR and link.")
                cancel
            } else {
                action("Create pairing invitation", id: "create-invitation", .createPairing)
            }
            importControls
        }
    }
    private var importControls: some View {
        PhonePanel {
            Text("Open an invitation from the other phone").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
            Text("Scan its QR or paste its link into the secure native import sheet. Verify the authority before joining; importing never confirms a peer.")
            if effects.contains(.camera), onEffect != nil {
                PhoneButton("Scan QR with camera", id: "phone.scan", disabled: !effectEnabled) {
                    if effectEnabled { onEffect?(.scanInvitation) }
                }
            } else { Text("Camera scanning is unavailable on this host.").foregroundColor(SwiftKeyAppearance.muted) }
            if effects.contains(.manualImport), onEffect != nil {
                PhoneButton("Enter pairing link", id: "phone.manual-import", disabled: !effectEnabled) {
                    if effectEnabled { onEffect?(.enterInvitation) }
                }
            } else { Text("Secure manual import is unavailable on this host.").foregroundColor(SwiftKeyAppearance.muted) }
        }
    }
    private var inspection: some View {
        PhonePanel {
            authority
            if snapshot.localIdentity == nil {
                Text("Prepare this phone’s final hardware identity before displaying peer fingerprints or joining. Importing the link has not approved anything.")
                action("Prepare this phone before joining", id: "prepare-import", .prepareIdentity)
            } else if let peer = snapshot.peer { PhoneIdentityCard(identity: peer) }
            context
            if snapshot.change != nil && snapshot.localIdentity != nil {
                roster(snapshot.owners)
                policy
                if let targetID = snapshot.change?.targetOwnerID,
                   let target = snapshot.owners.first(where: { $0.id == targetID }) {
                    PhoneValue("Exact lost root epoch", String(target.rootKeyEpoch))
                }
            }
            Text("Joining fixes the two participants. You will compare both phones and separately confirm before they are paired.")
            if let binding = snapshot.binding { action("Join this pairing", id: "join", .join(binding)) }
            cancel
        }
    }
    private var comparison: some View {
        PhonePanel {
            authority
            context
            Text("Compare the complete fingerprints, identities, authority and transcript hash on both physical phones. Confirm only if all details match.")
            if let local = snapshot.localIdentity { PhoneIdentityCard(identity: local) }
            if let peer = snapshot.peer { PhoneIdentityCard(identity: peer) }
            if let binding = snapshot.binding {
                if let code = Self.comparisonCode(binding.digest) {
                    PhoneValue("Comparison code · check all five groups", code)
                        .accessibilityIdentifier("phone.comparison-code")
                }
                PhoneValue("Transcript hash", binding.digest)
                action("The details match — confirm this pair", id: "confirm-peers", .confirmPeers(binding))
                action("They do not match — reject pairing", id: "reject-peers", .rejectPeers(binding))
            }
            Text("A QR scan and a short code alone are not approval.").foregroundColor(SwiftKeyAppearance.muted)
        }
    }
    private func waiting(_ explanation: String) -> some View {
        PhonePanel {
            Text(explanation)
            Text(snapshot.progress.localAccepted ? "This phone: consent accepted" : "This phone: awaiting consent")
            Text(snapshot.progress.peerAccepted ? "Other phone: consent accepted" : "Other phone: awaiting consent")
            context
            action("Check approval status", id: "refresh", .refresh)
            proposalRevisionControls
            cancel
        }
    }
    private var paired: some View {
        PhonePanel {
            authority
            if let local = snapshot.localIdentity { PhoneIdentityCard(identity: local) }
            if let peer = snapshot.peer { PhoneIdentityCard(identity: peer) }
            policy
            if let binding = snapshot.binding {
                if snapshot.change != nil {
                    context
                    Text("Pairing is complete. Both phones must still approve the immutable owner change before membership changes.")
                    action("Prepare owner change for review", id: "propose-membership", .proposeMembership(binding))
                } else {
                    Text("Choose a shared name. Both phones will review the same fixed label, owner set and policy before creating the account.")
                    TextField("Account name", text: labelBinding).accessibilityIdentifier("phone.account-label")
                        .disabled(snapshot.busy || isExpired || snapshot.availability != .nativeReady)
                    action("Prepare account proposal", id: "propose-account",
                           .proposeAccount(binding, label: drafts.wrappedValue.accountLabel, policy: snapshot.policy))
                }
            }
            cancel
        }
    }
    private var genesis: some View {
        PhonePanel {
            authority
            PhoneValue("Account name", snapshot.accountLabel)
            PhoneValue("Reserved account ID", snapshot.accountID ?? "Unavailable")
            Text("The name and owners below are fixed for this proposal. Changing them requires a new review and new approvals.")
            roster(snapshot.owners)
            policy
            if let binding = snapshot.binding {
                action("Create account with these two owners", id: "approve-genesis", .approveGenesis(binding))
            }
            proposalRevisionControls
            cancel
        }
    }
    private var committed: some View {
        PhonePanel {
            if let receipt = snapshot.receipt, snapshot.hasVerifiedReceipt {
                Text("Receipt verified by the native protocol adapter").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                PhoneValue("Account", receipt.accountID)
                PhoneValue("Original operation", receipt.operationID)
                PhoneValue("Approved proposal", receipt.proposalDigest)
                PhoneValue("Ledger sequence", String(receipt.ledgerSequence))
                PhoneValue("Signed ledger hash", receipt.ledgerHash)
                roster(snapshot.owners)
                Text("This historical receipt proves the reported commit. Current account access still requires a fresh membership and trust check.")
                    .accessibilityIdentifier("phone.receipt-detail")
                Text("Each owner signs in independently with its retained hardware root. A committed receipt is not a login session or epoch credential.")
                signInButton
            } else {
                PhoneNotice("Receipt verification is incomplete. Do not treat this phone as an owner yet.")
                resume
            }
        }
    }
    private var signIn: some View {
        PhonePanel {
            authority
            PhoneValue("Account", snapshot.accountID ?? "Unavailable")
            if let local = snapshot.localIdentity { PhoneIdentityCard(identity: local) }
            Text("Sign a fresh account- and origin-bound challenge using this phone’s hardware root. The authority checks current membership and trust before issuing a scoped session.")
            Text("An owner session and an epoch signing credential are separate. The browser cannot sign this challenge.")
            if snapshot.receipt != nil {
                Text("If sign-in fails, keep the verified account receipt and retry authentication. Do not create the account again.")
                    .accessibilityIdentifier("phone.sign-in-retry")
            }
            signInButton
        }
    }
    @ViewBuilder private var signInButton: some View {
        if let accountID = snapshot.accountID {
            action("Sign in with this hardware identity", id: "sign-in", .signIn(accountID: accountID, membershipRevision: snapshot.membershipRevision))
        }
    }
    private var ownerManagement: some View {
        PhonePanel {
            authority
            context
            roster(snapshot.owners)
            policy
            if let accountID = snapshot.accountID {
                action("Refresh sign-in and epoch credential", id: "refresh-sign-in", .signIn(accountID: accountID, membershipRevision: snapshot.membershipRevision))
                action("Add another owner", id: "add-owner", .beginOwnerChange(.add, accountID: accountID, membershipRevision: snapshot.membershipRevision, targetOwnerID: nil))
                ForEach(snapshot.owners.filter { !$0.isCurrent && !$0.revoked }, id: { $0.id }) { owner in
                    PhonePanel {
                        Text(owner.label).font(SwiftKeyAppearance.heading(18)).lineHeight(27).tracking(-0.3)
                        PhoneValue("Exact owner target", owner.id)
                        action("Replace this lost owner", id: "replace.\(owner.id)", .beginOwnerChange(.replace, accountID: accountID, membershipRevision: snapshot.membershipRevision, targetOwnerID: owner.id))
                        action("Review removal of this owner", id: "revoke.\(owner.id)", .beginOwnerChange(.revoke, accountID: accountID, membershipRevision: snapshot.membershipRevision, targetOwnerID: owner.id))
                    }
                }
            }
            if snapshot.owners.filter({ !$0.revoked }).count <= 2 {
                PhoneNotice("Two owners must remain. To remove a lost phone, pair its replacement and commit replacement atomically.")
            }
            PhoneNotice("Standalone owner revocation is unavailable until its v2 wire profile is implemented. Replacement revokes the lost root only in the same atomic commit that adds its replacement.")
            action("Refresh current membership", id: "refresh", .refresh)
        }
    }
    private var membership: some View {
        PhonePanel {
            authority
            context
            Text("Current owners").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
            roster(snapshot.owners)
            if let change = snapshot.change {
                if let target = change.targetOwnerID { PhoneValue("Owner to revoke in the same transaction", target) }
                if let candidate = change.candidate { PhoneIdentityCard(identity: candidate) }
                Text("Owners after commit").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                roster(change.resultingOwners)
            }
            policy
            PhoneNotice("The initiating owner and candidate must approve this exact proposal. Any membership revision change invalidates its consent and requires a fresh review.")
            if let binding = snapshot.binding {
                action(snapshot.localIdentity?.id == snapshot.change?.candidate?.id ? "Join this account as an owner" :
                       (snapshot.change?.kind == .replace ? "Approve atomic owner replacement" : "Approve adding this owner"),
                       id: "approve-membership", .approveMembership(binding))
                action("Reject this owner change", id: "reject-proposal", .rejectProposal(binding))
            }
            cancel
        }
    }
    private var revocation: some View {
        PhonePanel {
            context
            if let change = snapshot.change {
                PhoneValue("Owner to revoke", change.targetOwnerID ?? "Unavailable")
                Text("Owners remaining after removal").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                roster(change.resultingOwners)
            }
            PhoneNotice("Standalone revocation is not implemented. No removal can be submitted from this review.")
            PhoneNotice("Removal rejects this root’s sessions and currently valid epoch credentials online. At least two active owners must remain.")
            if let binding = snapshot.binding { action("Revoke this owner", id: "approve-revocation", .approveRevocation(binding)) }
            cancel
        }
    }
    private var policyReview: some View {
        PhonePanel {
            context
            policy
            roster(snapshot.owners)
            PhoneNotice("Policy changes require every current owner’s consent under the old policy. No policy-change signing adapter is connected; this surface cannot submit a change.")
            Text("An account policy cannot lower the authority’s hardware trust requirements.")
        }
    }
    private var browserReview: some View {
        PhonePanel {
            PhoneValue("Account", snapshot.accountID ?? "Unavailable")
            if let request = snapshot.browserRequest {
                PhoneValue("Requesting browser origin", request.origin)
                PhoneValue("Requested scopes", request.scopes.joined(separator: ", "))
                PhoneValue("Session expires", String(request.expiresAt))
            }
            PhoneNotice("Browser authorization is unavailable until its origin-bound grant protocol is implemented. No login grant is signed here.")
            Text("A browser session does not make the browser an owner. Ownership changes still require native hardware-root consent.")
        }
    }
    private var trust: some View {
        PhonePanel {
            if let identity = snapshot.localIdentity {
                PhoneIdentityCard(identity: identity)
                Text("The authority must validate the retained hardware evidence, current revocation status and a fresh root-bound proof. Your existing root must be preserved.")
                PhoneNotice("Do not approve ownership while required trust material is unavailable. Renew using this same retained root; the authority must recheck its hardware evidence and revocation status.")
                action("Renew trust with this hardware identity", id: "renew-identity", .renewIdentity)
            } else {
                PhoneNotice("This phone’s hardware identity could not be admitted. No account ownership was granted. Preserve any root already created; this screen does not reset or replace it.")
                    .accessibilityIdentifier("phone.admission-unavailable")
                Text("Trust renewal is available only after identity admission. Check the preparation result and device compatibility before starting another preparation.")
            }
            Text("If this identity is already owned or reserved elsewhere, or its preparation record is missing, reconcile the original operation. An unsupported root requires a compatible phone; do not regenerate a key silently.")
                .accessibilityIdentifier("phone.identity-conflict")
            action("Check trust status", id: "refresh", .refresh)
            resume
        }
    }
    private var revoked: some View {
        PhonePanel {
            Text("This root can no longer sign in, approve ownership changes or use epoch credentials online for this account. Local keys are retained; this view does not erase them.")
            Text("Use another currently trusted owner to review the account and pair a new phone. Losing every owner has no administrative recovery under this policy.")
                .accessibilityIdentifier("phone.recovery-unavailable")
            action("Check membership status", id: "refresh", .refresh)
        }
    }
    private var terminal: some View {
        PhonePanel {
            if snapshot.phase == .invalidated {
                PhoneNotice("Membership, policy or a root changed. Previous consent is invalid. Start a fresh pairing and review the current roster before approving.")
            }
            Text("A cancelled or expired operation cannot accept more consent. An already committed operation remains committed.")
            Text("Check the original result before beginning a new ceremony. This does not delete either phone’s hardware identity.")
            resume
            action("Start a new ceremony", id: "restart", .restart)
        }
    }
    private var unknown: some View {
        PhonePanel {
            PhoneNotice("The connection ended without a verified result. The authority may already have committed. Do not repeat approval, reset the identity, or start another operation.")
            if let id = snapshot.lastRequestID { PhoneValue("Original request", id) }
            resume
        }
    }
    @ViewBuilder private var resume: some View {
        if let requestID = snapshot.lastRequestID { action("Recover original operation result", id: "recover", .recover(requestID: requestID)) }
        else if let binding = snapshot.binding { action("Check original operation result", id: "resume", .resume(binding)) }
        else { action("Refresh protocol state", id: "refresh", .refresh) }
    }
    @ViewBuilder private var cancel: some View {
        if let binding = snapshot.binding {
            action(snapshot.phase == .inspectInvitation ? "Decline invitation on this phone" : "Cancel this operation",
                   id: "cancel", .cancel(binding))
        }
    }
    private var authority: some View {
        VStack(alignment: .leading, spacing: 6) {
            PhoneValue("Authority", snapshot.authorityID.isEmpty ? "Not connected" : snapshot.authorityID)
            PhoneValue("Origin", snapshot.origin.isEmpty ? "Not verified" : snapshot.origin)
            PhoneValue("Audience", snapshot.audience.isEmpty ? "Not verified" : snapshot.audience)
        }
    }
    private var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let account = snapshot.accountID {
                PhoneValue("Account", account)
                PhoneValue("Account name", snapshot.accountLabel)
                PhoneValue("Membership revision", String(snapshot.membershipRevision))
            }
            if let authorizer = snapshot.authorizingOwnerID { PhoneValue("Authorizing current owner", authorizer) }
            if let change = snapshot.change {
                PhoneValue("Operation", change.kind.rawValue.capitalized)
                if let target = change.targetOwnerID {
                    PhoneValue("Exact target owner", target)
                    if let descriptor = snapshot.owners.first(where: { $0.id == target }) {
                        PhoneValue("Target root epoch", String(descriptor.rootKeyEpoch))
                        PhoneValue("Target fingerprint", descriptor.fingerprint)
                    }
                }
            }
        }
    }
    private var policy: some View {
        PhonePanel {
            PhoneValue("Ownership policy", snapshot.policy.rawValue)
            Text(snapshot.policy.warning)
        }.accessibilityIdentifier("phone.policy")
    }
    private var operationDetails: some View {
        PhonePanel {
            if let binding = snapshot.binding {
                PhoneValue("Operation ID", binding.objectID)
                PhoneValue("Review revision", String(binding.revision))
                PhoneValue("Immutable digest", binding.digest)
                PhoneValue("Deadline (Unix seconds)", String(binding.expiresAt))
                if snapshot.hasVerifiedReceipt && !pendingReview {
                    Text("Historical review deadline · account access requires current membership and trust checks")
                        .foregroundColor(SwiftKeyAppearance.muted)
                } else {
                    Text(isExpired ? "Review deadline reached" : "\(binding.expiresAt - now) seconds remaining")
                        .foregroundColor(SwiftKeyAppearance.muted)
                }
            }
        }.accessibilityIdentifier("phone.operation-binding")
    }
    private func roster(_ owners: [PhoneIdentity]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if owners.isEmpty { Text("Owner roster unavailable. Approval is blocked.") }
            ForEach(owners, id: { $0.id }) { PhoneIdentityCard(identity: $0) }
        }
    }
    private func action(_ title: String, id: String, _ action: PhoneProtocolAction) -> some View {
        let failure = snapshot.rejection(for: action, now: now)
        return PhoneButton(title, id: "phone.\(id)", disabled: failure != nil) {
            if snapshot.rejection(for: action, now: now) == nil { onAction(action) }
        }
    }
    @ViewBuilder private var proposalRevisionControls: some View {
        if [.reviewGenesis, .waitingForGenesisConsent].contains(snapshot.phase), let binding = snapshot.binding {
            PhonePanel {
                Text("Change the proposed account name").font(SwiftKeyAppearance.heading(18)).lineHeight(27).tracking(-0.3)
                Text("Replacing this proposal invalidates both old approvals. Both phones must review and approve the new proposal.")
                TextField("Replacement account name", text: labelBinding).accessibilityIdentifier("phone.replacement-label")
                    .disabled(snapshot.busy || isExpired || snapshot.availability != .nativeReady)
                action("Replace proposal and review again", id: "replace-genesis",
                       .replaceGenesis(binding, label: drafts.wrappedValue.accountLabel, policy: snapshot.policy))
                action("Reject this account proposal", id: "reject-proposal", .rejectProposal(binding))
            }
        }
    }
    public static func comparisonCode(_ digest: String) -> String? {
        guard digest.count == 64, digest.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let characters = Array(digest.prefix(20).uppercased())
        return stride(from: 0, to: 20, by: 4).map { String(characters[$0..<($0 + 4)]) }.joined(separator: " ")
    }
    private var labelBinding: Binding<String> {
        Binding(get: { drafts.wrappedValue.accountLabel }, set: { value in
            var next = drafts.wrappedValue; next.accountLabel = value; drafts.wrappedValue = next
        })
    }
}

public struct PhoneIdentityCard: View {
    public let identity: PhoneIdentity
    public init(identity: PhoneIdentity) { self.identity = identity }
    public var body: some View {
        PhonePanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(identity.label).font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                if identity.isCurrent { SwiftKeyStatusLabel("This phone") }
            }
            PhoneValue("Identity", identity.id)
            PhoneValue("Full root fingerprint", identity.fingerprint)
            PhoneValue("Hardware root", identity.rootKind)
            PhoneValue("Root key epoch", String(identity.rootKeyEpoch))
            PhoneValue("Trust", identity.trust)
            if identity.revoked { Text("Revoked").font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).foregroundColor(SwiftKeyAppearance.danger) }
        }.accessibilityIdentifier("phone.identity.\(identity.id)")
    }
}
private struct PhonePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        SwiftKeyCard { content }
    }
}
private struct PhoneNotice: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message).font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(24).padding(16)
            .foregroundColor(SwiftKeyAppearance.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SwiftKeyAppearance.emphasis).cornerRadius(SwiftKeyAppearance.controlRadius)
    }
}
private struct PhoneValue: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).foregroundColor(SwiftKeyAppearance.muted)
            Text(value).font(SwiftKeyAppearance.technical(13)).lineHeight(21).tracking(0)
                .foregroundColor(SwiftKeyAppearance.ink).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct PhoneButton: View {
    let title: String
    let id: String
    let disabled: Bool
    let onTap: () -> Void
    init(_ title: String, id: String, disabled: Bool, onTap: @escaping () -> Void) {
        self.title = title; self.id = id; self.disabled = disabled; self.onTap = onTap
    }
    var body: some View {
        Button(action: onTap) {
            SwiftKeyActionLabel(title: title, secondary: id.contains("cancel") || id.contains("reject")
                || id.hasSuffix("refresh") || id.hasSuffix("resume") || id.hasSuffix("hide-invitation"))
        }.buttonStyle(.plain).disabled(disabled).accessibilityIdentifier(id)
    }
}
