#if canImport(AndroidSwiftUI)
import AndroidSwiftUI
import Foundation
import SwiftJava
import SwiftKeyClient
import SwiftKeyCore
import SwiftKeyApplication
import SwiftKeyUI

@JavaClass("com.pureswift.swiftandroid.PhoneProtocolHost")
class AndroidPhoneProtocolHost: JavaObject {}
extension JavaClass<AndroidPhoneProtocolHost> {
    @JavaStaticMethod func readConfiguration() -> String
    @JavaStaticMethod func readState() -> String
    @JavaStaticMethod func writeState(_ json: String) -> String
    @JavaStaticMethod func postJSON(_ url: String, _ body: String, _ bearer: String) -> String
    @JavaStaticMethod func isForeground() -> Bool
    @JavaStaticMethod func consumeEvent() -> String
    @JavaStaticMethod func requestImport(_ camera: Bool)
    @JavaStaticMethod func requestConfiguration()
    @JavaStaticMethod func openPasskeys()
    @JavaStaticMethod func presentInvitation(_ link: String, _ binding: String, _ expiry: String)
    @JavaStaticMethod func updatePresentationContext(_ binding: String)
    @JavaStaticMethod func dismiss()
}

func openAndroidPasskeys() {
    (try? JavaClass<AndroidPhoneProtocolHost>())?.openPasskeys()
}
extension JavaClass<AndroidHardwareKeyStore> {
    @JavaStaticMethod func enrollV2(_ challengeBase64: String) -> String
    @JavaStaticMethod func rootSignV2(_ messageBase64: String) -> String
}

/// Resolve Java classes on the app thread; retain global JNI references for
/// worker operations. V2 never reads, overwrites or deletes v1 state/root aliases.
final class AndroidPhoneProtocolBridge: @unchecked Sendable {
    let host: JavaClass<AndroidPhoneProtocolHost>
    private let hardware: JavaClass<AndroidHardwareKeyStore>
    init() throws {
        host = try JavaClass<AndroidPhoneProtocolHost>()
        hardware = try JavaClass<AndroidHardwareKeyStore>()
    }
    func configuration() throws -> PairingClientConfiguration? {
        let bytes = try checked(host.readConfiguration())
        if try JSONSerialization.jsonObject(with: bytes) as? [String: String] == [:] { return nil }
        return try JSONDecoder().decode(PairingClientConfiguration.self, from: bytes)
    }
    func platform() -> ClientPlatform {
        ClientPlatform(enroll: { challenge in
            try JSONDecoder().decode(AndroidEnrollmentEvidence.self,
                from: self.checked(self.hardware.enrollV2(challenge.base64EncodedString())))
        }, signRootMessage: { message in
            struct Signature: Decodable { let signature: Data }
            return try JSONDecoder().decode(Signature.self,
                from: self.checked(self.hardware.rootSignV2(message.base64EncodedString()))).signature
        }, post: { url, body, bearer in
            guard let text = String(data: body, encoding: .utf8) else { throw ClientError.invalidServerResponse }
            return try self.networkResponse(self.host.postJSON(url, text, bearer))
        }, readState: {
            let bytes = try self.checked(self.host.readState())
            if try JSONSerialization.jsonObject(with: bytes) as? [String: String] == [:] { return nil }
            return bytes
        }, writeState: { bytes in
            guard let text = String(data: bytes, encoding: .utf8) else { throw ClientError.storedStateMismatch }
            let response = try self.checked(self.host.writeState(text))
            guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  object["ok"] as? Bool == true else { throw ClientError.storedStateMismatch }
        })
    }
    func nativeEvent() -> NativePhoneEvent? {
        guard let bytes = host.consumeEvent().data(using: .utf8), bytes.count <= 16384 else { return nil }
        return try? JSONDecoder().decode(NativePhoneEvent.self, from: bytes)
    }
    func updatePresentation(_ snapshot: PhoneProtocolSnapshot) {
        let canShow = snapshot.phase == .invitation && snapshot.availability == .nativeReady
            && !snapshot.busy && snapshot.peer == nil
        let key = canShow ? snapshot.binding.map(Self.bindingKey) ?? "" : ""
        host.updatePresentationContext(key)
    }
    static func bindingKey(_ binding: PhoneProtocolBinding) -> String {
        "\(binding.objectID)|\(binding.revision)|\(binding.digest)|\(binding.expiresAt)"
    }
    private func networkResponse(_ text: String) throws -> Data {
        guard let bytes = text.data(using: .utf8), bytes.count <= 2 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw NativePhoneBridgeError.operationUnavailable
        }
        if object["error"] != nil {
            // Only the HTTP adapter may mark a parsed authority error. Local
            // timeout/storage/hardware errors must preserve an ambiguous write.
            guard let status = object["httpStatus"] as? Int, (400...599).contains(status),
                  object["code"] is String else { throw NativePhoneBridgeError.operationUnavailable }
        }
        return bytes
    }
    private func checked(_ text: String) throws -> Data {
        guard let bytes = text.data(using: .utf8), bytes.count <= 2 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw ClientError.invalidServerResponse
        }
        if object["error"] != nil { throw NativePhoneBridgeError.operationUnavailable }
        return bytes
    }
}

enum NativePhoneBridgeError: Error { case operationUnavailable }

struct NativePhoneEvent: Decodable {
    let kind: String
    let link: String?
    let code: String?
}

/// Process-wide coordinator survives Activity recreation. Only public snapshots
/// leave the actor; native invitation events are consumed once and never logged.
actor AndroidPhoneProtocolSession {
    typealias Observer = @Sendable (PhoneProtocolSnapshot, String?) -> Void
    private let bridge: AndroidPhoneProtocolBridge
    private var service: NativePhoneProtocolService?
    private var store: PhoneProtocolStore?
    private var observer: Observer?
    private var observerID: UUID?
    private var pollTask: Task<Void, Never>?
    private var value = PhoneProtocolSnapshot()
    private var actionSchedule = PhoneProtocolActionSchedule()
    private var queuedInvitationObserverID: UUID?
    private var performing: Bool { actionSchedule.isPerforming }
    private var refreshTick = 0
    private var nativeStatus: String?
    init(bridge: AndroidPhoneProtocolBridge) { self.bridge = bridge }

    func connect(_ id: UUID, _ observer: @escaping Observer) async {
        self.observerID = id; self.observer = observer
        if store == nil { await configure() } else { publish() }
        if pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { break }
                    await self?.tick()
                }
            }
        }
    }
    func disconnect(_ id: UUID) {
        guard observerID == id else { return }
        observerID = nil; observer = nil; pollTask?.cancel(); pollTask = nil
        bridge.host.updatePresentationContext(""); bridge.host.dismiss()
    }
    func configureAuthority() { bridge.host.requestConfiguration() }

    func send(_ action: PhoneProtocolAction, quiet: Bool = false) async {
        guard let store else { return }
        switch actionSchedule.begin(action, quiet: quiet) {
        case .busy: return
        case .deferred:
            nativeStatus = nil; value.busy = true; publish()
            return
        case .start: break
        }
        if !quiet { nativeStatus = nil }
        value.busy = true
        if action == .prepareIdentity { value.phase = .preparingIdentity }
        if action == .renewIdentity { value.phase = .renewingTrust }
        publish()
        let result = await store.send(action)
        value = result
        await completeScheduledWork()
    }
    private func completeScheduledWork() async {
        if let queued = actionSchedule.finish() {
            // Keep the binding captured at the tap. Store/effect validation
            // rejects it if the read changed the reviewed object or phase.
            switch queued {
            case .action(let action): await send(action)
            case .presentInvitation(let binding):
                let expectedObserver = queuedInvitationObserverID
                queuedInvitationObserverID = nil
                if expectedObserver != nil, expectedObserver == observerID, bridge.host.isForeground() {
                    await presentInvitation(binding)
                } else { publish() }
            }
        } else { publish() }
    }
    func effect(_ effect: PhoneProtocolEffect) async {
        switch effect {
        case .scanInvitation: bridge.host.requestImport(true)
        case .enterInvitation: bridge.host.requestImport(false)
        case .dismissInvitation: bridge.host.dismiss()
        case .presentInvitation(let binding): await presentInvitation(binding)
        }
    }
    private func presentInvitation(_ binding: PhoneProtocolBinding) async {
        guard let service, let expectedObserver = observerID, bridge.host.isForeground() else { return }
        switch actionSchedule.beginInvitation(binding) {
        case .busy: return
        case .deferred:
            queuedInvitationObserverID = expectedObserver
            nativeStatus = nil; value.busy = true; publish()
            return
        case .start: break
        }
        if PhoneProtocolActionSchedule.canPresentInvitation(binding, in: value) {
            do {
                let link = try await service.invitation(for: binding)
                // Recheck the original public binding after the async service read.
                if expectedObserver == observerID, bridge.host.isForeground(),
                   PhoneProtocolActionSchedule.canPresentInvitation(binding, in: value) {
                    // A queued tap temporarily cleared the native context while
                    // waiting. Restore this verified binding before opening it.
                    bridge.updatePresentation(value)
                    bridge.host.presentInvitation(link, AndroidPhoneProtocolBridge.bindingKey(binding), String(binding.expiresAt))
                }
            } catch { publish("The invitation is no longer available. Refresh its status before trying again.") }
        }
        await completeScheduledWork()
    }
    private func configure() async {
        nativeStatus = nil
        do {
            guard let configuration = try bridge.configuration() else {
                value = PhoneProtocolSnapshot()
                publish("Configure the trusted authority before preparing a v2 identity. Your existing legacy identity remains unchanged.")
                return
            }
            let client = try PairingClient(configuration: configuration, platform: bridge.platform())
            let service = NativePhoneProtocolService(client: client)
            self.service = service
            let store = PhoneProtocolStore(service: service)
            self.store = store
            value = await store.send(.refresh)
            publish()
        } catch {
            value = PhoneProtocolSnapshot()
            publish("The stored v2 configuration or identity journal could not be loaded. No key or state was replaced.")
        }
    }
    private func tick() async {
        guard !performing, bridge.host.isForeground() else { return }
        if let event = bridge.nativeEvent() {
            switch event.kind {
            case "invitation":
                if let link = event.link { await send(.inspectInvitation(PhoneInvitationInput(secretLink: link))) }
            case "configurationChanged":
                if !performing { store = nil; service = nil; await configure() }
            case "failure": publish("The native pairing action could not finish. You can retry camera or use manual import; no approval is automatic.")
            default: break
            }
        }
        refreshTick += 1
        // Interactive reviews also need current remote state: the other phone
        // can propose after pairing or replace/reject/cancel a reviewed object.
        // The shared policy keeps every approval tied to the newly shown binding.
        if !performing && refreshTick % 4 == 0 && value.phase.requiresCeremonyRefresh {
            await send(.refresh, quiet: true)
        } else if !performing { publish() } // Updates visible deadline without network/signing.
    }
    private func publish(_ message: String? = nil) {
        if let message { nativeStatus = message }
        let presentation = actionSchedule.presentation(value)
        bridge.updatePresentation(presentation)
        let observer = observer, snapshot = presentation, status = nativeStatus, expectedObserver = observerID
        Task { @MainActor in
            guard await self.isCurrentObserver(expectedObserver) else { return }
            observer?(snapshot, status)
        }
    }
    private func isCurrentObserver(_ id: UUID?) -> Bool { id != nil && observerID == id }
}

enum AndroidPhoneProtocolCoordinator {
    private static var session: AndroidPhoneProtocolSession?
    /// Called by the Android root view initializer on the app/JNI thread.
    static func shared() throws -> AndroidPhoneProtocolSession {
        if let session { return session }
        let session = AndroidPhoneProtocolSession(bridge: try AndroidPhoneProtocolBridge())
        Self.session = session
        return session
    }
}
#endif
