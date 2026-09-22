import Foundation
import AuthenticationServices

@MainActor public enum MockPasskeyIdentitySync {
    private static var previousUpdate: Task<Void, Never>?
    /// Index contains only metadata for the simulator mock. Software private keys never leave its file.
    public static func synchronize(store: MockPasskeyStore = .init()) async throws {
        guard MockPasskeyStore.isMockEnabled else { throw MockPasskeyStorageError.unavailable }
        // Isolated tests must never publish their temporary credentials into the real simulator index.
        guard store.publishesSystemIdentities else { return }
        let previous = previousUpdate
        let update = Task { @MainActor in
            await previous?.value
            let state = await ASCredentialIdentityStore.shared.state()
            guard state.isEnabled else { throw MockIdentitySyncError.providerDisabled }
            // Reconcile changes made by the other app-group process while Apple's update was in flight.
            for _ in 0..<3 {
                let snapshot = try store.credentials()
                let identities: [any ASCredentialIdentity] = snapshot.map {
                    ASPasskeyCredentialIdentity(relyingPartyIdentifier: $0.rpID, userName: $0.userName,
                        credentialID: $0.id, userHandle: $0.userHandle, recordIdentifier: $0.id.mockBase64URL)
                }
                try await ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities)
                if try store.credentials() == snapshot { return }
            }
            throw MockIdentitySyncError.concurrentUpdate
        }
        previousUpdate = Task { @MainActor in _ = try? await update.value }
        try await update.value
    }
}

public enum MockIdentitySyncError: LocalizedError {
    case providerDisabled, concurrentUpdate
    public var errorDescription: String? {
        switch self {
        case .providerDisabled: "Enable the SwiftKey Mock provider in Settings before its credentials appear in system suggestions."
        case .concurrentUpdate: "Mock credentials changed during the system index update. Open provider configuration to refresh suggestions."
        }
    }
}
