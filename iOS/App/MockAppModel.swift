import Foundation
import Combine

struct MockCredentialItem: Identifiable, Equatable {
    let id: String
    let userName: String
    let relyingPartyID: String
}
enum MockRequestKind { case registration, assertion }
struct MockPendingRequest: Identifiable {
    let id: UUID
    let kind: MockRequestKind
    let userName: String
    let relyingPartyID: String
}
struct MockOutcome {
    let title: String
    let message: String
    var isError = false
    var isCancelled = false
}

/// Presentation state only. The exact same coordinator used by the extension
/// owns requests, software-key storage, response generation and verification.
@MainActor
final class MockAppModel: ObservableObject {
    @Published var testName = ""
    @Published private(set) var credentials: [MockCredentialItem] = []
    @Published private(set) var pending: MockPendingRequest?
    @Published private(set) var outcome: MockOutcome?
    @Published private(set) var startupFailure: String?
    @Published private(set) var showVerification = false
    @Published private(set) var isWorking = false
    @Published private(set) var identityIndexStatus: String?
    private let coordinator: MockPasskeyCoordinator
    private var identityStatusObserver: AnyCancellable?
    private var loaded = false

    init(coordinator: MockPasskeyCoordinator = MockPasskeyCoordinator()) {
        self.coordinator = coordinator
        identityStatusObserver = coordinator.$identityIndexStatus.sink { [weak self] status in
            self?.identityIndexStatus = status
        }
    }
    var canRegister: Bool {
        startupFailure == nil && !isWorking && pending == nil &&
        !testName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && testName.utf8.count <= 80
    }
    func load() async {
        guard !loaded else { return }
        loaded = true
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") &&
            ProcessInfo.processInfo.arguments.contains("--reset-mock-state") {
            coordinator.resetMockState()
        }
        #endif
        coordinator.reload()
        refresh()
        if !MockPasskeyCoordinator.isMockEnabled {
            startupFailure = "Mock mode is available only in a Debug iOS Simulator build."
        } else if let error = coordinator.error { startupFailure = error }
    }
    func requestRegistration() {
        guard canRegister else { return }
        outcome = nil; showVerification = false
        coordinator.beginMockRegistration(userName: testName.trimmingCharacters(in: .whitespacesAndNewlines), rpID: "swiftkey.mock")
        refresh()
        displayErrorIfNeeded()
    }
    func refreshFromStore() {
        guard loaded, !isWorking, pending == nil else { return }
        coordinator.reload()
        refresh()
        startupFailure = coordinator.error
    }
    func requestSignIn(_ credential: MockCredentialItem) {
        guard !isWorking, pending == nil, startupFailure == nil else { return }
        outcome = nil; showVerification = false
        coordinator.beginMockAssertion(credentialID: credential.id)
        refresh()
        displayErrorIfNeeded()
    }
    func approveReview() {
        guard pending != nil, !isWorking else { return }
        showVerification = true
    }
    func completeVerification(success: Bool) {
        guard let request = pending, showVerification, !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            // Give the progress state a render turn before the local transaction.
            await Task.yield()
            coordinator.approve(requestID: request.id, simulatedVerification: success)
            let failure = coordinator.error
            // A rejected attempt ends this presentation. Preserve its actual
            // error before cancellation clears coordinator transient messages.
            // Never cancel a newer request if the captured request became stale.
            if failure != nil, coordinator.pending?.id == request.id {
                coordinator.cancel(requestID: request.id)
            }
            refresh()
            isWorking = false
            showVerification = false
            if let error = failure {
                outcome = MockOutcome(title: "Verification not completed", message: error, isError: true)
            } else if let result = coordinator.result {
                switch result {
                case .registration:
                    outcome = MockOutcome(title: "Passkey created", message: coordinator.status)
                    testName = ""
                case .assertion:
                    outcome = MockOutcome(title: "Signature verified", message: coordinator.status)
                }
            } else {
                outcome = MockOutcome(title: "No response accepted", message: "The mock request did not produce a verified response. Try a new request.", isError: true)
            }
        }
    }
    func cancelPending() {
        guard let request = pending, !isWorking else { return }
        coordinator.cancel(requestID: request.id)
        refresh(); showVerification = false
        outcome = MockOutcome(title: "Request cancelled", message: "No passkey was created and no sign-in was completed.", isCancelled: true)
    }
    func delete(_ credential: MockCredentialItem) {
        guard !isWorking, pending == nil else { return }
        coordinator.removeCredential(id: credential.id)
        refresh()
        if let error = coordinator.error {
            outcome = MockOutcome(title: "Passkey was not deleted", message: error, isError: true)
        } else {
            outcome = MockOutcome(title: "Test passkey deleted", message: "Only this local mock credential was removed.")
        }
    }
    private func refresh() {
        credentials = coordinator.credentials.map {
            MockCredentialItem(id: $0.id, userName: $0.userName, relyingPartyID: $0.rpID)
        }
        pending = coordinator.pending.map {
            MockPendingRequest(id: $0.id, kind: $0.kind == .registration ? .registration : .assertion,
                userName: $0.userName, relyingPartyID: $0.rpID)
        }
    }
    private func displayErrorIfNeeded() {
        if let error = coordinator.error {
            outcome = MockOutcome(title: "Request unavailable", message: error, isError: true)
        }
    }
}
