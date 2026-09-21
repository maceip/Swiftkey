import Foundation
import SwiftKeyCore

/// Implemented by an in-process authority or an authenticated HTTP adapter.
/// No method may substitute fixtures for unavailable operations in production.
public protocol WorkspaceService: Sendable {
    func loadWorkspace(_ query: WorkspaceQuery) async throws -> WorkspaceOverview
    func createAccount(_ request: CreateAccountRequest) async throws -> CreateAccountResponse
    func reissueEnrollmentInvitation(accountID: String) async throws -> CreateAccountResponse
    func verifyCredential(_ request: VerifyCredentialRequest) async throws -> CredentialVerificationResponse
}

public enum WorkspacePhase: String, Codable, Sendable { case idle, loading, ready, stale, failed }
public enum WorkspaceOperation: String, Codable, Sendable {
    case refresh, selectAccount, createAccount, reissueInvitation, paginate, verifyCredential
}

public struct WorkspaceFailure: Error, Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}

/// Safe to render or encode: only public records and operation state. It never
/// contains admin credentials, enrollment tokens or client private key state.
public struct WorkspaceSnapshot: Codable, Sendable, Equatable {
    public let phase: WorkspacePhase
    public let workspace: WorkspaceOverview?
    public let operation: WorkspaceOperation?
    public let error: WorkspaceFailure?
    public let verification: CredentialVerificationResponse?
    public let canGoBack: Bool
    public init(phase: WorkspacePhase = .idle, workspace: WorkspaceOverview? = nil, operation: WorkspaceOperation? = nil, error: WorkspaceFailure? = nil, verification: CredentialVerificationResponse? = nil, canGoBack: Bool = false) {
        self.phase = phase; self.workspace = workspace; self.operation = operation
        self.error = error; self.verification = verification; self.canGoBack = canGoBack
    }
}

public enum WorkspaceAction: Sendable, Equatable {
    case refresh
    case selectAccount(String)
    case createAccount(String)
    case reissueInvitation(String)
    case firstLedgerPage
    case nextLedgerPage
    case previousLedgerPage
    case verifyCredential(EpochCredential)
    case dismissInvitation
    case exportEnrollmentBundle
}

/// Secret values appear only after an explicit provisioning/export action.
/// Do not persist or log this result as a workspace snapshot.
public struct WorkspaceActionResult: Sendable {
    public let snapshot: WorkspaceSnapshot
    public let invitation: CreateAccountResponse?
    public let enrollmentBundle: EnrollmentBundle?
    /// A create/reissue request completed at the authority. A later read failure
    /// does not undo it and must never trigger an automatic mutation retry.
    public let operationCommitted: Bool
    public init(snapshot: WorkspaceSnapshot, invitation: CreateAccountResponse? = nil, enrollmentBundle: EnrollmentBundle? = nil, operationCommitted: Bool = false) {
        self.snapshot = snapshot; self.invitation = invitation; self.enrollmentBundle = enrollmentBundle
        self.operationCommitted = operationCommitted
    }
}
