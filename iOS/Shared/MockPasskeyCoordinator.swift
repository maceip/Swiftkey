import Foundation
import Combine
import CryptoKit
import SwiftKeyPasskeys

public struct MockPasskeySummary: Identifiable {
    public let id: String
    public let rpID: String
    public let userName: String
    public let displayName: String
    public let createdAt: Date
    init(_ credential: MockPasskeyCredential) {
        id = credential.id.mockBase64URL
        rpID = credential.rpID; userName = credential.userName
        displayName = credential.displayName; createdAt = credential.createdAt
    }
}

public struct MockPasskeyPending: Identifiable {
    public enum Kind: String { case registration, assertion }
    public let id: UUID
    public let kind: Kind
    public let rpID: String
    public let userName: String
    public let expiresAt: Date
}

public enum MockPasskeyResult {
    case registration(MockRegistrationResponse)
    case assertion(MockAssertionResponse)
}

/// Shared by the native provider adapter and the app's explicitly labelled simulator harness.
@MainActor public final class MockPasskeyCoordinator: ObservableObject {
    public static var isMockEnabled: Bool { MockPasskeyStore.isMockEnabled }
    @Published public private(set) var credentials: [MockPasskeySummary] = []
    @Published public private(set) var pending: MockPasskeyPending?
    @Published public private(set) var result: MockPasskeyResult?
    @Published public private(set) var status = "Mock mode · software keys, simulated verification."
    @Published public private(set) var error: String?
    @Published public private(set) var identityIndexStatus: String?

    private let store: MockPasskeyStore
    private let now: () -> Date
    private var operation: MockPasskeyOperation?
    private var lastOperation: MockPasskeyOperation?
    private var localClientDataJSON: Data?

    public init(store: MockPasskeyStore = .init(), now: @escaping () -> Date = Date.init) {
        self.store = store; self.now = now
        reload()
    }

    public func reload() {
        do {
            guard Self.isMockEnabled else { throw MockPasskeyStorageError.unavailable }
            credentials = try store.credentials().map(MockPasskeySummary.init)
            error = nil
        } catch { report(error) }
    }

    public func beginMockRegistration(userName: String, rpID: String = "swiftkey.mock") {
        do {
            let clientData = try makeClientData(type: "webauthn.create", rpID: rpID)
            let request = MockCreatePasskeyRequest(rpID: rpID, userHandle: randomBytes(32),
                userName: userName, displayName: userName, clientDataHash: Data(SHA256.hash(data: clientData)))
            try beginRegistration(request)
            localClientDataJSON = clientData
        } catch { report(error) }
    }

    public func beginMockAssertion(credentialID: String) {
        do {
            guard let record = try store.credentials().first(where: { $0.id.mockBase64URL == credentialID }) else {
                throw MockCoordinatorError.missingCredential
            }
            let clientData = try makeClientData(type: "webauthn.get", rpID: record.rpID)
            let request = MockSignPasskeyRequest(rpID: record.rpID,
                clientDataHash: Data(SHA256.hash(data: clientData)), credentialID: record.id,
                allowedCredentialIDs: [record.id], userHandle: record.userHandle)
            try beginAssertion(request)
            localClientDataJSON = clientData
        } catch { report(error) }
    }

    /// OS request data is copied into immutable core values before showing approval controls.
    public func beginRegistration(_ request: MockCreatePasskeyRequest) throws {
        try ready(rpID: request.rpID, hash: request.clientDataHash)
        guard request.algorithms.contains(-7), (1...64).contains(request.userHandle.count),
              !request.userName.isEmpty, request.userName.utf8.count <= 256 else { throw MockCoordinatorError.invalidRequest }
        operation = .create(request)
        pending = .init(id: request.requestID, kind: .registration, rpID: request.rpID,
                        userName: request.userName, expiresAt: now().addingTimeInterval(60))
        prepared()
    }

    public func beginAssertion(_ request: MockSignPasskeyRequest) throws {
        try ready(rpID: request.rpID, hash: request.clientDataHash)
        guard let id = request.credentialID,
              let record = try store.credentials().first(where: { $0.id == id && $0.rpID == request.rpID }),
              request.allowedCredentialIDs.isEmpty || request.allowedCredentialIDs.contains(id),
              request.userHandle == nil || request.userHandle == record.userHandle else { throw MockCoordinatorError.missingCredential }
        operation = .sign(request)
        pending = .init(id: request.requestID, kind: .assertion, rpID: request.rpID,
                        userName: record.userName, expiresAt: now().addingTimeInterval(60))
        prepared()
    }

    @discardableResult public func approve(requestID: UUID, simulatedVerification: Bool) -> MockPasskeyResult? {
        do {
            guard Self.isMockEnabled else { throw MockPasskeyStorageError.unavailable }
            guard let pending, pending.id == requestID, let operation else { throw MockCoordinatorError.staleRequest }
            let instant = now()
            guard instant >= pending.expiresAt.addingTimeInterval(-60), pending.expiresAt > instant else {
                clearPending(); throw MockCoordinatorError.expired
            }
            guard simulatedVerification else {
                clearPending(); throw MockCoordinatorError.verificationRequired
            }
            let completed: MockPasskeyResult = try store.transaction { engine in
                let approval = try engine.approve(operation, now: instant)
                switch operation {
                case .create(let request):
                    let response = try engine.create(request, approval: approval, now: instant)
                    // The harness exercises real encoding and exact client-data-hash binding.
                    _ = try response.webAuthnJSON(clientDataJSON: localClientDataJSON ?? Data())
                    return .registration(response)
                case .sign(let request):
                    guard let credential = engine.credentials.first(where: { $0.id == request.credentialID }) else {
                        throw MockCoordinatorError.missingCredential
                    }
                    let response = try engine.sign(request, approval: approval, now: instant)
                    try response.verify(publicKeyX963: credential.publicKeyX963)
                    _ = try response.webAuthnJSON(clientDataJSON: localClientDataJSON ?? Data())
                    return .assertion(response)
                }
            }
            lastOperation = operation
            clearPending(); result = completed; error = nil
            credentials = try store.credentials().map(MockPasskeySummary.init)
            switch completed {
            case .registration: status = "Mock mode · software passkey created. Verification was simulated."
            case .assertion: status = "Mock mode · signature verified with the stored public key. Verification was simulated."
            }
            synchronizeIdentityIndex()
            return completed
        } catch { report(error); return nil }
    }

    public func cancel(requestID: UUID) {
        guard pending?.id == requestID else { report(MockCoordinatorError.staleRequest); return }
        clearPending(); error = nil; result = nil
        status = "Mock mode · request cancelled. No credential was created or signed."
    }

    public func removeCredential(id: String) {
        do {
            guard pending == nil else { throw MockCoordinatorError.requestInProgress }
            guard let record = try store.credentials().first(where: { $0.id.mockBase64URL == id }) else {
                throw MockCoordinatorError.missingCredential
            }
            try store.transaction { try $0.deleteCredential(id: record.id) }
            credentials = try store.credentials().map(MockPasskeySummary.init)
            result = nil; error = nil; status = "Mock mode · software passkey removed from this simulator."
            synchronizeIdentityIndex()
        } catch { report(error) }
    }

    /// Exercises the persisted one-use request guard; it never fabricates a success screen.
    public func retryLastRequest() {
        do {
            guard pending == nil, let lastOperation else { throw MockCoordinatorError.staleRequest }
            try store.transaction { engine in
                let approval = try engine.approve(lastOperation, now: now())
                switch lastOperation {
                case .create(let request): _ = try engine.create(request, approval: approval, now: now())
                case .sign(let request): _ = try engine.sign(request, approval: approval, now: now())
                }
            }
            report(MockCoordinatorError.replayUnexpectedlyAccepted)
        } catch { report(error) }
    }

    public func resetMockState() {
        do {
            try store.resetMockState(); clearPending(); lastOperation = nil; result = nil
            credentials = []; error = nil; status = "Mock mode · isolated software-key store reset."
            synchronizeIdentityIndex()
        } catch { report(error) }
    }

    public func matchingCredentials(rpID: String, allowedIDs: [Data]) throws -> [MockPasskeyCredential] {
        guard Self.isMockEnabled, ["swiftkey.mock", "localhost"].contains(rpID) else { throw MockCoordinatorError.unsupportedRP }
        return try store.credentials().filter { $0.rpID == rpID && (allowedIDs.isEmpty || allowedIDs.contains($0.id)) }
    }

    private func ready(rpID: String, hash: Data) throws {
        guard Self.isMockEnabled else { throw MockPasskeyStorageError.unavailable }
        guard pending == nil else { throw MockCoordinatorError.requestInProgress }
        guard ["swiftkey.mock", "localhost"].contains(rpID) else { throw MockCoordinatorError.unsupportedRP }
        guard hash.count == 32 else { throw MockCoordinatorError.invalidRequest }
        _ = try store.credentials()
    }
    private func prepared() {
        result = nil; error = nil; localClientDataJSON = nil
        status = "Mock mode · review this request and explicitly simulate verification. No biometrics will run."
    }
    private func synchronizeIdentityIndex() {
        guard Self.isMockEnabled, store.publishesSystemIdentities else { return }
        identityIndexStatus = "Mock mode · updating system credential suggestions…"
        Task { @MainActor [weak self, store] in
            do {
                try await MockPasskeyIdentitySync.synchronize(store: store)
                self?.identityIndexStatus = "Mock mode · system credential suggestions updated."
            } catch {
                // The local credential mutation already succeeded; index availability is advisory.
                self?.identityIndexStatus = "Mock mode · \(error.localizedDescription) Local mock storage is unchanged."
            }
        }
    }
    private func clearPending() { pending = nil; operation = nil; localClientDataJSON = nil }
    private func report(_ error: Error) { self.error = "Mock mode · \(error.localizedDescription)" }
    private func makeClientData(type: String, rpID: String) throws -> Data {
        guard ["swiftkey.mock", "localhost"].contains(rpID) else { throw MockCoordinatorError.unsupportedRP }
        return try JSONSerialization.data(withJSONObject: ["type": type, "challenge": randomBytes(32).mockBase64URL,
            "origin": rpID == "localhost" ? "http://localhost" : "https://swiftkey.mock", "crossOrigin": false], options: [.sortedKeys])
    }
    private func randomBytes(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: .min ... .max) }) }
}

public enum MockCoordinatorError: LocalizedError {
    case unsupportedRP, invalidRequest, missingCredential, staleRequest, expired, verificationRequired, requestInProgress, replayUnexpectedlyAccepted
    public var errorDescription: String? {
        switch self {
        case .unsupportedRP: "Only swiftkey.mock and localhost are available in this simulator mock."
        case .invalidRequest: "The mock request is malformed or requests an unsupported algorithm."
        case .missingCredential: "No matching mock credential exists for this exact request."
        case .staleRequest: "This mock request is stale, cancelled, or already completed."
        case .expired: "This mock request expired. Start another request."
        case .verificationRequired: "Explicitly enable simulated verification. No biometric authentication is performed."
        case .requestInProgress: "Finish or cancel the current mock request first."
        case .replayUnexpectedlyAccepted: "The replay check failed; do not treat this run as verified."
        }
    }
}

extension Data {
    var mockBase64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
