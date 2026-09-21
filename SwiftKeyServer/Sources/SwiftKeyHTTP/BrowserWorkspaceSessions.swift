import Foundation
import SwiftKeyCore
import SwiftKeyAuthority
import SwiftKeyApplication
import SwiftKeyUI
import SwiftUICore

struct AuthorityWorkspaceService: WorkspaceService {
    let authority: Authority
    func loadWorkspace(_ query: WorkspaceQuery) async throws -> WorkspaceOverview {
        try await translate { try await authority.workspace(query) }
    }
    func createAccount(_ request: CreateAccountRequest) async throws -> CreateAccountResponse {
        try await translate { try await authority.createAccount(request) }
    }
    func reissueEnrollmentInvitation(accountID: String) async throws -> CreateAccountResponse {
        try await translate { try await authority.reissueEnrollmentInvitation(accountID: accountID) }
    }
    func verifyCredential(_ request: VerifyCredentialRequest) async throws -> CredentialVerificationResponse {
        try await translate { try await authority.verifyCredential(request) }
    }
    private func translate<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let error as AuthorityError { throw WorkspaceFailure(code: error.code, message: error.description) }
        catch is ProtocolError { throw WorkspaceFailure(code: "invalidCredential", message: "The credential is expired or failed cryptographic validation.") }
        catch { throw WorkspaceFailure(code: "unavailable", message: "The authority could not complete this operation.") }
    }
}

/// Every tab owns a separate Swift store, view tree and callback registry.
/// ViewHost is main-thread confined; this boundary serializes all evaluation
/// and dispatch. Authority/network work awaits without accepting overlapping
/// actions for a session. There is no global Compose runtime on the server.
@MainActor public final class BrowserWorkspaceSessions: Sendable {
    private let authority: Authority
    private var sessions: [String: Session] = [:]
    private let lifetime: TimeInterval = 1_800
    private let maximumSessions = 16

    public nonisolated init(authority: Authority) { self.authority = authority }

    @MainActor private final class Session {
        let id = UUID().uuidString.lowercased()
        let store: WorkspaceStore
        var drafts = WorkspaceDrafts()
        var host: ViewHost?
        var revision: UInt64 = 0
        var lastUsed = Date()
        var busy = false
        var callbacks: [Int64: String] = [:]
        var actions: [WorkspaceAction] = []
        var effects: [WorkspaceUIEffect] = []
        init(authority: Authority) { store = WorkspaceStore(service: AuthorityWorkspaceService(authority: authority)) }
    }

    public func create() async throws -> BrowserWorkspaceResponse {
        expireSessions()
        guard sessions.count < maximumSessions else { throw failure("sessionLimit", "Close another workspace session before opening a new one.") }
        let session = Session(authority: authority)
        sessions[session.id] = session
        session.busy = true
        defer { session.busy = false }
        _ = await session.store.send(.refresh)
        return try await render(session, effects: [])
    }

    public func disconnect(id: String) async {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.host = nil; session.callbacks.removeAll()
        await session.store.clearSession()
    }

    public func dispatch(id: String, request: BrowserEventRequest) async throws -> BrowserWorkspaceResponse {
        expireSessions()
        guard let session = sessions[id], let host = session.host else { throw failure("notFound", "Workspace session expired. Reconnect to the authority.") }
        guard !session.busy else { throw failure("sessionBusy", "A workspace operation is still in progress.") }
        guard request.revision == session.revision else { throw failure("staleView", "The view changed. Reconnect before submitting another action.") }
        guard (1...128).contains(request.events.count), request.events.filter({ $0.kind == "void" }).count <= 1 else {
            throw failure("invalidRequest", "Invalid workspace event batch.")
        }
        // Validate the entire batch before changing even a draft field. An old,
        // invented, wrong-type or disabled callback must never invoke a closure.
        for event in request.events {
            guard let callbackID = Int64(event.id), String(callbackID) == event.id,
                  session.callbacks[callbackID] == event.kind,
                  let callback = host.callbacks.callback(for: callbackID),
                  callbackKind(callback) == event.kind,
                  (event.value?.utf8.count ?? 0) <= 16_384 else {
                throw failure("invalidRequest", "The event is not an enabled control in the current view.")
            }
            switch event.kind {
            case "void": guard event.value == nil else { throw failure("invalidRequest", "Unexpected control value.") }
            case "string": guard event.value != nil else { throw failure("invalidRequest", "Missing control value.") }
            case "bool": guard event.value == "true" || event.value == "false" else { throw failure("invalidRequest", "Invalid Boolean value.") }
            case "int": guard let value = event.value, Int(value) != nil else { throw failure("invalidRequest", "Invalid integer value.") }
            case "double": guard let value = event.value, let number = Double(value), number.isFinite else { throw failure("invalidRequest", "Invalid numeric value.") }
            default: throw failure("invalidRequest", "Unsupported control event.")
            }
        }
        session.busy = true; session.lastUsed = Date()
        defer { session.busy = false; session.actions.removeAll(); session.effects.removeAll() }
        for event in request.events {
            let callbackID = Int64(event.id)!
            switch event.kind {
            case "void": host.callbacks.invokeVoid(callbackID)
            case "string": host.callbacks.invokeString(callbackID, event.value!)
            case "bool": host.callbacks.invokeBool(callbackID, event.value == "true")
            case "int": host.callbacks.invokeInt(callbackID, Int(event.value!)!)
            case "double": host.callbacks.invokeDouble(callbackID, Double(event.value!)!)
            default: break
            }
        }
        var effects: [BrowserEffect] = []
        for action in session.actions {
            let result = await session.store.send(action)
            if case .exportEnrollmentBundle = action, let bundle = result.enrollmentBundle {
                effects.append(try download(bundle, filename: "swiftkey-enrollment.json"))
            }
        }
        for effect in session.effects {
            switch effect {
            case .copyPublicKey(let data): effects.append(.init(copy: data.map { String(format: "%02x", $0) }.joined()))
            case .copyInvitation(let invitation): effects.append(.init(copy: invitation.enrollmentToken))
            case .exportCredential(let credential): effects.append(try download(credential, filename: "swiftkey-credential.json"))
            case .exportLedger(let ledger): effects.append(try download(ledger, filename: "swiftkey-ledger.json"))
            }
        }
        // Disconnect can run while the store awaits I/O. Do not return a secret
        // invitation or resurrect a session that the browser already destroyed.
        guard sessions[id] === session else { throw failure("notFound", "Workspace disconnected.") }
        return try await render(session, effects: effects)
    }

    private func render(_ session: Session, effects: [BrowserEffect]) async throws -> BrowserWorkspaceResponse {
        let snapshot = await session.store.snapshot()
        let invitation = await session.store.invitation()
        guard sessions[session.id] === session else { throw failure("notFound", "Workspace disconnected.") }
        let root = WorkspaceView(snapshot: snapshot,
            drafts: Binding(get: { [weak session] in session?.drafts ?? WorkspaceDrafts() },
                set: { [weak session] in session?.drafts = $0 }),
            invitation: invitation,
            onAction: { [weak session] in session?.actions.append($0) },
            onEffect: { [weak session] in session?.effects.append($0) })
        let host = ViewHost(root)
        let node = host.evaluate()
        session.host = host
        session.callbacks = enabledCallbacks(node, registry: host.callbacks)
        session.revision += 1
        return BrowserWorkspaceResponse(sessionID: session.id, revision: session.revision,
            tree: BrowserTree(node), effects: effects)
    }

    private func enabledCallbacks(_ node: RenderNode, registry: CallbackRegistry, disabled: Bool = false) -> [Int64: String] {
        let disabled = disabled || node.modifiers.contains { $0.kind == "disabled" && $0.args["value"] == .bool(true) }
        var result: [Int64: String] = [:]
        if !disabled {
            for name in ["onTap", "onChange", "onSubmit", "onToggle", "onExpandedChange"] {
                if case .int(let raw)? = node.props[name], let callback = registry.callback(for: Int64(raw)), let kind = callbackKind(callback) {
                    result[Int64(raw)] = kind
                }
            }
        }
        for child in node.children { result.merge(enabledCallbacks(child, registry: registry, disabled: disabled)) { _, new in new } }
        return result
    }

    private func callbackKind(_ callback: CallbackRegistry.Callback) -> String? {
        switch callback {
        case .void: "void"
        case .string: "string"
        case .bool: "bool"
        case .int: "int"
        case .double: "double"
        case .item: nil
        }
    }

    private func download<T: Encodable>(_ value: T, filename: String) throws -> BrowserEffect {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return .init(download: String(decoding: try encoder.encode(value), as: UTF8.self), filename: filename)
    }
    private func expireSessions() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        sessions = sessions.filter { $0.value.busy || $0.value.lastUsed > cutoff }
    }
    private func failure(_ code: String, _ message: String) -> AuthorityError {
        .protocolFailure(code: code, message: message)
    }
}
