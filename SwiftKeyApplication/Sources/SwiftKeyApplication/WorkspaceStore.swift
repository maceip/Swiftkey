import Foundation
import SwiftKeyCore

/// Shared application behavior. Views render snapshots and send actions; service
/// adapters own authentication, transport and the actual authority operations.
public actor WorkspaceStore {
    private let service: any WorkspaceService
    private let pageSize: Int
    private let clock: @Sendable () -> UInt64
    private var value = WorkspaceSnapshot()
    private var after: UInt64 = 0
    private var previousPages: [UInt64] = []
    private var active: UUID?
    private var generation: UInt64 = 0
    private var pendingInvitation: CreateAccountResponse?
    private var pendingBundle: EnrollmentBundle?

    public init(service: any WorkspaceService, pageSize: Int = 25, clock: @escaping @Sendable () -> UInt64 = { UInt64(max(0, Date().timeIntervalSince1970)) }) {
        self.service = service; self.pageSize = min(200, max(1, pageSize))
        self.clock = clock
    }
    public func snapshot() -> WorkspaceSnapshot { value }
    public func invitation() -> CreateAccountResponse? { pendingInvitation }
    public func enrollmentBundle() -> EnrollmentBundle? { pendingBundle }
    public func send(_ action: WorkspaceAction) async -> WorkspaceActionResult { await perform(action) }

    /// Clears only this presentation session, never a hardware identity or server
    /// record. Responses from earlier in-flight actions cannot repopulate it.
    public func clearSession() {
        generation &+= 1; active = nil; value = WorkspaceSnapshot()
        after = 0; previousPages = []; pendingInvitation = nil; pendingBundle = nil
    }

    public func perform(_ action: WorkspaceAction) async -> WorkspaceActionResult {
        if action == .dismissInvitation {
            pendingInvitation = nil; pendingBundle = nil
            return WorkspaceActionResult(snapshot: value)
        }
        if active != nil {
            return WorkspaceActionResult(snapshot: WorkspaceSnapshot(phase: value.phase, workspace: value.workspace,
                operation: value.operation, error: WorkspaceFailure(code: "operationInProgress", message: "Wait for the current operation to finish."),
                verification: value.verification, canGoBack: value.canGoBack))
        }
        if action == .exportEnrollmentBundle {
            guard let pendingBundle else {
                fail(WorkspaceFailure(code: "invitationUnavailable", message: "No enrollment invitation is available in this session."))
                return WorkspaceActionResult(snapshot: value)
            }
            guard clock() < pendingBundle.expiresAt else {
                pendingInvitation = nil; self.pendingBundle = nil
                fail(failure("invitationExpired", "This enrollment invitation has expired. Refresh the account to check whether a replacement can be issued."))
                return WorkspaceActionResult(snapshot: value)
            }
            return WorkspaceActionResult(snapshot: value, enrollmentBundle: pendingBundle)
        }
        let run = UUID(), session = generation
        active = run
        let operation = operation(for: action)
        value = WorkspaceSnapshot(phase: .loading, workspace: value.workspace, operation: operation,
                                  verification: action.isVerification ? nil : value.verification, canGoBack: !previousPages.isEmpty)
        var revealed: CreateAccountResponse?
        var bundle: EnrollmentBundle?
        var operationCommitted = false
        defer { if active == run { active = nil } }
        do {
            switch action {
            case .refresh:
                let workspace = try await load(accountID: value.workspace?.selectedAccountID, after: 0, session: session)
                after = 0; previousPages = []; ready(workspace)
            case .selectAccount(let id):
                let current = try requireWorkspace()
                guard current.accounts.contains(where: { $0.accountID == id }) else { throw failure("notFound", "Select an existing account.") }
                if id != current.selectedAccountID { pendingInvitation = nil; pendingBundle = nil }
                let workspace = try await load(accountID: id, after: 0, session: session)
                after = 0; previousPages = []; ready(workspace, verification: nil)
            case .createAccount(let label):
                let current = try requireWorkspace()
                guard current.status.legacyProvisioningAllowed != false else {
                    throw failure("legacyProvisioningDisabled", "Pair two phones in the native app to create an account.")
                }
                let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
                guard !normalized.isEmpty, normalized.utf8.count <= 120,
                      !normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw failure("invalidRequest", "Account names must contain 1 to 120 UTF-8 bytes without control characters.")
                }
                let invitation = try await service.createAccount(CreateAccountRequest(label: normalized))
                operationCommitted = true
                try checkSession(session)
                let exported = try makeBundle(invitation, workspace: current)
                pendingInvitation = invitation; pendingBundle = exported; revealed = invitation; bundle = exported
                let workspace = try await load(accountID: invitation.account.accountID, after: 0, session: session)
                after = 0; previousPages = []; ready(workspace, verification: nil)
            case .reissueInvitation(let id):
                let current = try requireWorkspace()
                guard let account = current.accounts.first(where: { $0.accountID == id }) else { throw failure("notFound", "Select an existing account.") }
                guard account.canReissueInvitation else { throw failure("accountNotPending", "This account cannot receive a replacement enrollment invitation.") }
                let invitation = try await service.reissueEnrollmentInvitation(accountID: id)
                operationCommitted = true
                try checkSession(session)
                guard invitation.account.accountID == id else { throw failure("invalidResponse", "The authority returned an invitation for a different account.") }
                let exported = try makeBundle(invitation, workspace: current)
                pendingInvitation = invitation; pendingBundle = exported; revealed = invitation; bundle = exported
                let workspace = try await load(accountID: id, after: 0, session: session)
                after = 0; previousPages = []; ready(workspace, verification: nil)
            case .firstLedgerPage:
                let current = try requireWorkspace()
                let workspace = try await load(accountID: current.selectedAccountID, after: 0, session: session)
                after = 0; previousPages = []; ready(workspace)
            case .nextLedgerPage:
                let current = try requireWorkspace()
                guard current.ledger.hasMore, current.ledger.nextAfter > after else { throw failure("noNextPage", "There are no more ledger events.") }
                let next = current.ledger.nextAfter
                let workspace = try await load(accountID: current.selectedAccountID, after: next, session: session)
                previousPages.append(after); after = next; ready(workspace)
            case .previousLedgerPage:
                let current = try requireWorkspace()
                guard let previous = previousPages.last else { throw failure("noPreviousPage", "This is the first ledger page.") }
                let workspace = try await load(accountID: current.selectedAccountID, after: previous, session: session)
                previousPages.removeLast(); after = previous; ready(workspace)
            case .verifyCredential(let credential):
                let current = try requireWorkspace()
                let receipt = try await service.verifyCredential(VerifyCredentialRequest(credential: credential))
                try checkSession(session)
                let delegation = credential.delegation, bounds = try Epoch.bounds(for: delegation.epoch)
                guard receipt.accountID == delegation.accountID, receipt.deviceID == delegation.deviceID,
                      receipt.epoch == delegation.epoch, receipt.validUntil == bounds.end,
                      receipt.checkedAt >= bounds.start, receipt.checkedAt < bounds.end,
                      receipt.credentialHash == ProtocolCrypto.sha256(try credential.canonicalBytes()) else {
                    throw failure("invalidResponse", "The verification receipt does not match this credential.")
                }
                ready(current, verification: receipt)
            case .dismissInvitation, .exportEnrollmentBundle: break
            }
        } catch {
            guard session == generation else { return WorkspaceActionResult(snapshot: value) }
            let error = (error as? WorkspaceFailure) ?? failure("serviceUnavailable", "The authority operation could not be completed. Refresh before retrying.")
            if error.code == "unauthorized" {
                clearSession()
                value = WorkspaceSnapshot(phase: .failed, error: error)
                return WorkspaceActionResult(snapshot: value, operationCommitted: operationCommitted)
            }
            if revealed != nil {
                let committed = operation == .createAccount ? "Account created" : "Invitation reissued"
                fail(failure("refreshAfterMutationFailed", "\(committed); refreshing failed. Save the enrollment bundle and refresh the workspace. The operation has already completed."))
            } else { fail(error) }
        }
        return WorkspaceActionResult(snapshot: value, invitation: revealed, enrollmentBundle: bundle, operationCommitted: operationCommitted)
    }

    private func load(accountID: String?, after: UInt64, session: UInt64) async throws -> WorkspaceOverview {
        let result = try await service.loadWorkspace(WorkspaceQuery(accountID: accountID, after: after, limit: pageSize))
        try checkSession(session)
        let ids = Set(result.accounts.map(\.accountID))
        guard ids.count == result.accounts.count,
              accountID == nil || accountID == result.selectedAccountID,
              result.selectedAccountID.map({ ids.contains($0) }) ?? (result.devices.isEmpty && result.epochs.isEmpty),
              result.devices.allSatisfy({ $0.accountID == result.selectedAccountID }),
              result.epochs.allSatisfy({ $0.accountID == result.selectedAccountID }),
              result.status.ledgerHead.sequence == result.ledger.head.sequence,
              result.status.ledgerHead.hash == result.ledger.head.hash,
              result.ledger.events.count <= pageSize,
              !result.ledger.hasMore || (result.ledger.nextAfter > after && !result.ledger.events.isEmpty) else {
            throw failure("invalidResponse", "The authority returned an inconsistent workspace snapshot.")
        }
        return result
    }
    private func checkSession(_ session: UInt64) throws {
        guard session == generation else { throw CancellationError() }
    }
    private func requireWorkspace() throws -> WorkspaceOverview {
        guard let workspace = value.workspace else { throw failure("workspaceNotLoaded", "Load the workspace before performing this action.") }
        return workspace
    }
    private func makeBundle(_ invitation: CreateAccountResponse, workspace: WorkspaceOverview) throws -> EnrollmentBundle {
        guard !invitation.account.accountID.isEmpty, invitation.enrollmentToken.utf8.count >= 32,
              invitation.expiresAt > max(workspace.status.unixTime, clock()),
              let url = URLComponents(string: workspace.serverURL), url.url != nil,
              url.scheme == "https" || (url.scheme == "http" && url.host == "127.0.0.1"),
              url.host?.isEmpty == false, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", !workspace.audience.isEmpty else {
            throw failure("invalidResponse", "The authority returned an invalid enrollment handoff.")
        }
        try ProtocolCrypto.validatePublicKey(workspace.status.serverPublicKey)
        return EnrollmentBundle(accountID: invitation.account.accountID, label: invitation.account.label,
            expiresAt: invitation.expiresAt, configuration: EnrollmentConfiguration(serverURL: workspace.serverURL,
                bootstrapToken: invitation.enrollmentToken, serverPublicKey: workspace.status.serverPublicKey, audience: workspace.audience,
                expectedAccountID: invitation.account.accountID))
    }
    private func ready(_ workspace: WorkspaceOverview, verification: CredentialVerificationResponse? = nil) {
        value = WorkspaceSnapshot(phase: .ready, workspace: workspace, verification: verification, canGoBack: !previousPages.isEmpty)
    }
    private func fail(_ error: WorkspaceFailure) {
        value = WorkspaceSnapshot(phase: value.workspace == nil ? .failed : .stale, workspace: value.workspace,
                                  error: error, verification: nil, canGoBack: !previousPages.isEmpty)
    }
    private func failure(_ code: String, _ message: String) -> WorkspaceFailure { WorkspaceFailure(code: code, message: message) }
    private func operation(for action: WorkspaceAction) -> WorkspaceOperation? {
        switch action {
        case .refresh: .refresh
        case .selectAccount: .selectAccount
        case .createAccount: .createAccount
        case .reissueInvitation: .reissueInvitation
        case .firstLedgerPage, .nextLedgerPage, .previousLedgerPage: .paginate
        case .verifyCredential: .verifyCredential
        case .dismissInvitation, .exportEnrollmentBundle: nil
        }
    }
}

private extension WorkspaceAction {
    var isVerification: Bool { if case .verifyCredential = self { true } else { false } }
}
