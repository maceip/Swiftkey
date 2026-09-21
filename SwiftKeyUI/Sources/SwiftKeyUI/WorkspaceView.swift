import Foundation
import SwiftUICore
import SwiftKeyApplication
import SwiftKeyCore

/// Host-owned presentation state. It contains no authentication or invitation
/// secrets. A host retains this value across rendered revisions.
public struct WorkspaceDrafts: Sendable, Equatable {
    public var accountLabel: String
    public var accountFilter: String
    public var selectedSection: String

    public init(accountLabel: String = "", accountFilter: String = "", selectedSection: String = "accounts") {
        self.accountLabel = accountLabel
        self.accountFilter = accountFilter
        self.selectedSection = selectedSection
    }
}

/// The host implements these platform effects; it never decides which account
/// operation to perform. Unsupported effects have no visible action button.
public enum WorkspaceUIEffect: Sendable, Equatable {
    case copyPublicKey(Data)
    case copyInvitation(CreateAccountResponse)
    case exportCredential(EpochCredential)
    case exportLedger(LedgerPage)
}

/// Shared native/web composition. The application store owns service calls,
/// authorization results, and operation state; this view owns their presentation.
public struct WorkspaceView: View {
    public let snapshot: WorkspaceSnapshot
    public let drafts: Binding<WorkspaceDrafts>
    public let invitation: CreateAccountResponse?
    public let onAction: (WorkspaceAction) -> Void
    public let onEffect: ((WorkspaceUIEffect) -> Void)?

    public init(snapshot: WorkspaceSnapshot, drafts: Binding<WorkspaceDrafts>,
                invitation: CreateAccountResponse? = nil,
                onAction: @escaping (WorkspaceAction) -> Void,
                onEffect: ((WorkspaceUIEffect) -> Void)? = nil) {
        self.snapshot = snapshot; self.drafts = drafts; self.invitation = invitation
        self.onAction = onAction; self.onEffect = onEffect
    }

    private var busy: Bool { snapshot.operation != nil || snapshot.phase == .loading }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                connectionState
                if let failure = snapshot.error {
                    WorkspacePanel {
                        WorkspaceHeading("Couldn’t complete the request", size: 20)
                        Text(failure.message).foregroundColor(SwiftKeyAppearance.ink)
                        WorkspaceCode(failure.code)
                    }
                    .accessibilityIdentifier("swiftkey.error")
                }
                if let invitation {
                    InvitationPanel(invitation: invitation, busy: busy, onAction: onAction, onEffect: onEffect)
                }
                if let workspace = snapshot.workspace {
                    workspaceContent(workspace)
                } else {
                    WorkspacePanel {
                        WorkspaceHeading("Your identity workspace", size: 24)
                        Text("Load the authority to see its accounts, device roots, credentials, and ledger.")
                            .foregroundColor(SwiftKeyAppearance.muted)
                        WorkspaceButton("Load workspace", id: "swiftkey.load", disabled: busy) { onAction(.refresh) }
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(EdgeInsets(top: 28, leading: SwiftKeyAppearance.pageInset, bottom: 48, trailing: SwiftKeyAppearance.pageInset))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwiftKeyAppearance.canvas)
        .foregroundColor(SwiftKeyAppearance.ink)
        .font(SwiftKeyAppearance.body()).lineHeight(28).tracking(0.3)
        .accessibilityIdentifier("swiftkey.workspace")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            SwiftKeyPageHeader("Identity, in your hands.", subtitle: "Accounts · devices · credentials")
            WorkspaceButton(busy ? "Updating…" : "Refresh", id: "swiftkey.refresh", disabled: busy) { onAction(.refresh) }
        }
    }

    private var connectionState: some View {
        SwiftKeyStatusLabel(phaseText)
            .accessibilityIdentifier("swiftkey.connection-state")
    }

    private var phaseText: String {
        switch snapshot.phase {
        case .idle: return "Workspace not loaded"
        case .loading: return "Loading authority records…"
        case .ready:
            if let time = snapshot.workspace?.status.unixTime { return "Authority checked at \(WorkspaceFormatting.timestamp(time))" }
            return "Authority records loaded"
        case .stale: return "Showing the last loaded records · the latest request did not complete"
        case .failed: return "Workspace could not be loaded"
        }
    }

    @ViewBuilder private func workspaceContent(_ workspace: WorkspaceOverview) -> some View {
        WorkspacePanel {
            Text("\(workspace.status.accountCount) accounts · \(workspace.status.activeDeviceCount) active devices")
                .font(SwiftKeyAppearance.heading(18)).lineHeight(27).tracking(-0.3)
            Text("Epoch \(workspace.status.epoch) · \(workspace.status.credentialCount) credentials issued")
                .font(SwiftKeyAppearance.body(14)).lineHeight(24.5).foregroundColor(SwiftKeyAppearance.muted)
            Picker("Workspace section", selection: stringBinding(\.selectedSection)) {
                Text("Accounts").tag("accounts")
                Text("Devices").tag("devices")
                Text("Credentials").tag("epochs")
                Text("Ledger").tag("ledger")
                Text("Authority").tag("authority")
            }
            .accessibilityIdentifier("swiftkey.section")
        }
        if drafts.wrappedValue.selectedSection == "devices" {
            DevicesPanel(workspace: workspace, busy: busy, onAction: onAction, onEffect: onEffect)
        } else if drafts.wrappedValue.selectedSection == "epochs" {
            EpochsPanel(workspace: workspace, verification: snapshot.verification, busy: busy, onAction: onAction, onEffect: onEffect)
        } else if drafts.wrappedValue.selectedSection == "ledger" {
            LedgerPanel(workspace: workspace, canGoBack: snapshot.canGoBack, busy: busy, onAction: onAction, onEffect: onEffect)
        } else if drafts.wrappedValue.selectedSection == "authority" {
            AuthorityPanel(workspace: workspace, onEffect: onEffect)
        } else {
            AccountsPanel(workspace: workspace, label: stringBinding(\.accountLabel), filter: stringBinding(\.accountFilter),
                          busy: busy, onAction: { action in
                if case .selectAccount = action {
                    var next = drafts.wrappedValue; next.selectedSection = "devices"; drafts.wrappedValue = next
                }
                onAction(action)
            })
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<WorkspaceDrafts, String>) -> Binding<String> {
        Binding(get: { drafts.wrappedValue[keyPath: keyPath] }, set: { value in
            var next = drafts.wrappedValue; next[keyPath: keyPath] = value; drafts.wrappedValue = next
        })
    }
}

private struct AccountsPanel: View {
    let workspace: WorkspaceOverview
    let label: Binding<String>
    let filter: Binding<String>
    let busy: Bool
    let onAction: (WorkspaceAction) -> Void

    private var visibleAccounts: [AccountSummary] {
        let query = filter.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspace.accounts.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) || $0.accountID.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading("Accounts")
            WorkspacePanel {
                if workspace.status.legacyProvisioningAllowed == false {
                    WorkspaceHeading("Create an account on your phones", size: 20)
                    Text("Pair two phones in the native app to create an account")
                        .accessibilityIdentifier("swiftkey.native-account-creation")
                } else {
                    WorkspaceHeading("Create an account", size: 20)
                    Text("Create a fresh account and a one-use enrollment invitation.")
                        .foregroundColor(SwiftKeyAppearance.muted)
                    TextField("Account name", text: label).accessibilityIdentifier("swiftkey.account-label")
                        .accessibilityLabel("Account name").disabled(busy)
                    WorkspaceButton("Create account", id: "swiftkey.create-account", disabled: busy) {
                        guard !busy, workspace.status.legacyProvisioningAllowed != false else { return }
                        onAction(.createAccount(label.wrappedValue))
                    }
                }
            }
            TextField("Find by name or account ID", text: filter)
                .accessibilityLabel("Find accounts").accessibilityIdentifier("swiftkey.account-filter")
            Text("Press Return to apply the filter.").font(SwiftKeyAppearance.body(13)).lineHeight(22.75)
                .foregroundColor(SwiftKeyAppearance.muted)
            if workspace.accounts.isEmpty {
                WorkspaceEmpty("No accounts yet", detail: workspace.status.legacyProvisioningAllowed == false
                    ? "Accounts appear here after both phones approve their shared account."
                    : "Create an account to prepare its first device enrollment.")
            } else if visibleAccounts.isEmpty {
                WorkspaceEmpty("No matching accounts", detail: "Try another name or account ID.")
            }
            ForEach(visibleAccounts, id: { $0.accountID }) { account in
                Button {
                    onAction(.selectAccount(account.accountID))
                } label: {
                    WorkspacePanel {
                        Text(account.label).font(SwiftKeyAppearance.heading(23)).lineHeight(34.5).tracking(-0.3)
                        Text("\(account.status.capitalized) · \(account.activeDeviceCount) of \(account.deviceCount) devices active")
                            .foregroundColor(SwiftKeyAppearance.muted)
                        WorkspaceCode(account.accountID)
                        Text("Open account →").font(SwiftKeyAppearance.heading(14)).lineHeight(21).tracking(-0.3)
                            .foregroundColor(SwiftKeyAppearance.forest)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityIdentifier("swiftkey.account.\(account.accountID)")
            }
        }
        .accessibilityIdentifier("swiftkey.accounts")
    }
}

private struct SelectedAccountHeading: View {
    let workspace: WorkspaceOverview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let account = workspace.accounts.first(where: { $0.accountID == workspace.selectedAccountID }) {
                Text(account.label).font(SwiftKeyAppearance.heading(22)).lineHeight(33).tracking(-0.3)
                WorkspaceCode(account.accountID)
            } else {
                Text("Select an account from Accounts.").foregroundColor(SwiftKeyAppearance.muted)
            }
        }
    }
}

private struct DevicesPanel: View {
    let workspace: WorkspaceOverview
    let busy: Bool
    let onAction: (WorkspaceAction) -> Void
    let onEffect: ((WorkspaceUIEffect) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading("Device roots")
            SelectedAccountHeading(workspace: workspace)
            if let account = workspace.accounts.first(where: { $0.accountID == workspace.selectedAccountID }), account.canReissueInvitation {
                WorkspacePanel {
                    Text("Ready for a first device").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                    Text("A new enrollment invitation replaces any earlier unused invitation.")
                        .foregroundColor(SwiftKeyAppearance.muted)
                    WorkspaceButton("New enrollment invitation", id: "swiftkey.reissue-invitation", disabled: busy) {
                        onAction(.reissueInvitation(account.accountID))
                    }
                }
            }
            if workspace.selectedAccountID != nil && workspace.devices.isEmpty {
                WorkspaceEmpty("No enrolled devices", detail: "Device roots appear here after enrollment is verified by the authority.")
            }
            ForEach(workspace.devices, id: { $0.deviceID }) { device in
                WorkspacePanel {
                    Text(device.status.capitalized).font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
                    WorkspaceCode(device.deviceID)
                    Text("Membership sequence \(device.sequence)").foregroundColor(SwiftKeyAppearance.muted)
                    if let enrolled = device.enrolledAt { WorkspaceFact("Enrolled", WorkspaceFormatting.timestamp(enrolled)) }
                    if let revoked = device.revokedAt { WorkspaceFact("Revoked", WorkspaceFormatting.timestamp(revoked)) }
                    if let epoch = device.lastEpoch { WorkspaceFact("Latest issued epoch", String(epoch)) }
                    Text("Root public key · X9.63").font(SwiftKeyAppearance.heading(14)).lineHeight(21).tracking(-0.3)
                    SwiftKeyPublicKeyView(publicKey: device.publicKey, compact: true)
                    if let onEffect {
                        WorkspaceButton("Copy public key", id: "swiftkey.copy-root.\(device.deviceID)") {
                            onEffect(.copyPublicKey(device.publicKey))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("swiftkey.devices")
    }
}

private struct EpochsPanel: View {
    let workspace: WorkspaceOverview
    let verification: CredentialVerificationResponse?
    let busy: Bool
    let onAction: (WorkspaceAction) -> Void
    let onEffect: ((WorkspaceUIEffect) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading("Epoch credentials")
            SelectedAccountHeading(workspace: workspace)
            Text("Verify a credential against the authority’s current membership and attestation policy.")
                .foregroundColor(SwiftKeyAppearance.muted)
            if workspace.selectedAccountID != nil && workspace.epochs.isEmpty {
                WorkspaceEmpty("No issued credentials", detail: "Credentials appear when an enrolled device requests an epoch key.")
            }
            ForEach(workspace.epochs, id: { "\($0.deviceID):\($0.epoch)" }) { epoch in
                WorkspacePanel {
                    Text("Epoch \(epoch.epoch) · \(epoch.status)").font(SwiftKeyAppearance.heading(22)).lineHeight(33).tracking(-0.3)
                    WorkspaceCode(epoch.deviceID)
                    WorkspaceFact("Valid from", WorkspaceFormatting.timestamp(epoch.validFrom))
                    WorkspaceFact("Valid until", WorkspaceFormatting.timestamp(epoch.validUntil))
                    if let issued = epoch.issuedAt { WorkspaceFact("Issued", WorkspaceFormatting.timestamp(issued)) }
                    Text("Epoch public key · X9.63").font(SwiftKeyAppearance.heading(14)).lineHeight(21).tracking(-0.3)
                    SwiftKeyPublicKeyView(publicKey: epoch.publicKey, compact: true)
                    if let previous = epoch.previousPublicKeyHash {
                        WorkspaceFact("Previous public key hash", SwiftKeyPublicKeyView.groupedHex(previous))
                    }
                    WorkspaceButton("Verify credential", id: "swiftkey.verify.\(epoch.deviceID).\(epoch.epoch)", disabled: busy) {
                        onAction(.verifyCredential(epoch.credential))
                    }
                    if let verified = matchingVerification(epoch.credential) {
                        Text("Verified by authority at \(WorkspaceFormatting.timestamp(verified.checkedAt))")
                            .font(SwiftKeyAppearance.heading(14)).lineHeight(21).foregroundColor(SwiftKeyAppearance.forest).tracking(-0.3)
                        Text("This is a point-in-time check. Later workload requests are verified separately.")
                            .font(SwiftKeyAppearance.body(13)).lineHeight(22.75).foregroundColor(SwiftKeyAppearance.muted)
                    }
                    if let onEffect {
                        WorkspaceButton("Copy epoch public key", id: "swiftkey.copy-epoch.\(epoch.deviceID).\(epoch.epoch)") {
                            onEffect(.copyPublicKey(epoch.publicKey))
                        }
                        WorkspaceButton("Export credential", id: "swiftkey.export-credential.\(epoch.deviceID).\(epoch.epoch)") {
                            onEffect(.exportCredential(epoch.credential))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("swiftkey.epochs")
    }

    private func matchingVerification(_ credential: EpochCredential) -> CredentialVerificationResponse? {
        guard let verification, let bytes = try? credential.canonicalBytes(),
              verification.credentialHash == ProtocolCrypto.sha256(bytes) else { return nil }
        return verification
    }
}

private struct LedgerPanel: View {
    let workspace: WorkspaceOverview
    let canGoBack: Bool
    let busy: Bool
    let onAction: (WorkspaceAction) -> Void
    let onEffect: ((WorkspaceUIEffect) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading("Authority ledger")
            Text("Public event metadata, in sequence.").foregroundColor(SwiftKeyAppearance.muted)
            if let selected = workspace.selectedAccountID { WorkspaceFact("Account filter", selected) }
            WorkspacePanel {
                WorkspaceFact("Signed head", "Sequence \(workspace.ledger.head.sequence)")
                WorkspaceCode(SwiftKeyPublicKeyView.groupedHex(workspace.ledger.head.hash))
                Text("Retain an exported head separately to compare with a later checkpoint.")
                    .foregroundColor(SwiftKeyAppearance.muted)
                if let onEffect {
                    WorkspaceButton("Export ledger page", id: "swiftkey.export-ledger") { onEffect(.exportLedger(workspace.ledger)) }
                }
            }
            if workspace.ledger.events.isEmpty {
                WorkspaceEmpty("No events on this page", detail: "Refresh or return to the first page to load available records.")
            }
            ForEach(workspace.ledger.events, id: { $0.sequence }) { event in
                LedgerEventView(event: event)
            }
            VStack(alignment: .leading, spacing: 10) {
                WorkspaceButton("First page", id: "swiftkey.ledger-first", disabled: busy) { onAction(.firstLedgerPage) }
                WorkspaceButton("Previous page", id: "swiftkey.ledger-previous", disabled: busy || !canGoBack) { onAction(.previousLedgerPage) }
                WorkspaceButton("Next page", id: "swiftkey.ledger-next", disabled: busy || !workspace.ledger.hasMore) { onAction(.nextLedgerPage) }
            }
        }
        .accessibilityIdentifier("swiftkey.ledger")
    }
}

private struct LedgerEventView: View {
    let event: LedgerEvent
    var body: some View {
        WorkspacePanel {
            Text("\(event.sequence) · \(event.kind)").font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
            Text(WorkspaceFormatting.timestamp(event.timestamp)).foregroundColor(SwiftKeyAppearance.muted)
            if let account = event.accountID { WorkspaceFact("Account", account) }
            if let device = event.deviceID { WorkspaceFact("Device", device) }
            if let actor = event.actorDeviceID { WorkspaceFact("Acting device", actor) }
            DisclosureGroup("Event details and hashes") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(event.details.keys.sorted(), id: \.self) { key in
                        WorkspaceFact(key, event.details[key] ?? "")
                    }
                    WorkspaceFact("Previous hash", SwiftKeyPublicKeyView.groupedHex(event.previousHash))
                    WorkspaceFact("Event hash", SwiftKeyPublicKeyView.groupedHex(event.hash))
                }
                .padding(EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }
}

private struct AuthorityPanel: View {
    let workspace: WorkspaceOverview
    let onEffect: ((WorkspaceUIEffect) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading("Authority")
            WorkspacePanel {
                WorkspaceFact("Server", workspace.serverURL)
                WorkspaceFact("Audience", workspace.audience)
                WorkspaceFact("Workload domain", workspace.workloadDomain)
                WorkspaceFact("Epoch", String(workspace.status.epoch))
                WorkspaceFact("Epoch starts", WorkspaceFormatting.timestamp(workspace.status.epochStart))
                WorkspaceFact("Epoch ends", WorkspaceFormatting.timestamp(workspace.status.epochEnd))
                WorkspaceFact("Storage", "\(workspace.status.storage) · schema \(workspace.status.schemaVersion)")
                WorkspaceFact("Revoked devices", String(workspace.status.revokedDeviceCount))
                Text("Authority public key · X9.63").font(SwiftKeyAppearance.heading(14)).lineHeight(21).tracking(-0.3)
                SwiftKeyPublicKeyView(publicKey: workspace.status.serverPublicKey, compact: true)
                if let onEffect {
                    WorkspaceButton("Copy authority public key", id: "swiftkey.copy-authority") { onEffect(.copyPublicKey(workspace.status.serverPublicKey)) }
                }
            }
        }
        .accessibilityIdentifier("swiftkey.authority")
    }
}

private struct InvitationPanel: View {
    let invitation: CreateAccountResponse
    let busy: Bool
    let onAction: (WorkspaceAction) -> Void
    let onEffect: ((WorkspaceUIEffect) -> Void)?
    var body: some View {
        WorkspacePanel {
            WorkspaceHeading("Enroll the first device", size: 24)
            Text(invitation.account.label).font(SwiftKeyAppearance.heading(20)).lineHeight(30).tracking(-0.3)
            WorkspaceCode(invitation.account.accountID)
            Text("This invitation can be used once. Keep it private until the device is enrolled.")
                .foregroundColor(SwiftKeyAppearance.muted)
            WorkspaceFact("Expires", WorkspaceFormatting.timestamp(invitation.expiresAt))
            WorkspaceFact("Enrollment token", invitation.enrollmentToken)
            if let onEffect {
                WorkspaceButton("Copy invitation token", id: "swiftkey.copy-invitation") { onEffect(.copyInvitation(invitation)) }
            }
            WorkspaceButton("Export enrollment bundle", id: "swiftkey.export-enrollment", disabled: busy) { onAction(.exportEnrollmentBundle) }
            WorkspaceButton("Dismiss invitation", id: "swiftkey.dismiss-invitation", disabled: busy) { onAction(.dismissInvitation) }
        }
        .accessibilityIdentifier("swiftkey.invitation")
    }
}

private struct WorkspacePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        SwiftKeyCard { content }
    }
}

private struct WorkspaceHeading: View {
    let text: String
    let size: Double
    init(_ text: String, size: Double = 24) { self.text = text; self.size = size }
    var body: some View {
        Text(text).font(SwiftKeyAppearance.heading(size)).lineHeight(size * 1.5).tracking(-0.3)
            .foregroundColor(SwiftKeyAppearance.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct WorkspaceButton: View {
    let title: String
    let id: String
    let disabled: Bool
    let action: () -> Void
    init(_ title: String, id: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.id = id; self.disabled = disabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            SwiftKeyActionLabel(title: title, secondary: id.contains("copy") || id.contains("export")
                || id.contains("dismiss") || id.contains("refresh") || id.contains("ledger-"))
        }
        .buttonStyle(.plain).disabled(disabled).accessibilityIdentifier(id)
    }
}

private struct WorkspaceFact: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).foregroundColor(SwiftKeyAppearance.muted)
            WorkspaceCode(value)
        }
    }
}

private struct WorkspaceCode: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View {
        Text(value).font(SwiftKeyAppearance.technical(13)).lineHeight(21).foregroundColor(SwiftKeyAppearance.ink).tracking(0)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceEmpty: View {
    let title: String
    let detail: String
    init(_ title: String, detail: String) { self.title = title; self.detail = detail }
    var body: some View {
        WorkspacePanel {
            WorkspaceHeading(title, size: 20)
            Text(detail).foregroundColor(SwiftKeyAppearance.muted)
        }
    }
}

private enum WorkspaceFormatting {
    static func timestamp(_ unixTime: UInt64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unixTime)))
    }
}
