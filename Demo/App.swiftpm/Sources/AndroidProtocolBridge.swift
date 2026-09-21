#if canImport(AndroidSwiftUI)
import AndroidSwiftUI
import Foundation
import SwiftJava
import SwiftKeyClient
import SwiftKeyCore

extension JavaClass<AndroidHardwareKeyStore> {
    @JavaStaticMethod func enroll(_ challengeBase64: String) -> String
    @JavaStaticMethod func rootSign(_ messageBase64: String) -> String
    @JavaStaticMethod func hasAttestedRoot() -> Bool
    @JavaStaticMethod func postJSON(_ url: String, _ body: String, _ bootstrapToken: String) -> String
    @JavaStaticMethod func readClientState() -> String
    @JavaStaticMethod func writeClientState(_ json: String) -> String
    @JavaStaticMethod func readClientConfiguration() -> String
}

/// The Java class is resolved on the app thread and held by SwiftJava's global
/// JNI reference. Each static call obtains the calling thread's JNI environment.
/// Network and hardware operations run on the protocol task, outside UI rendering.
final class AndroidProtocolBridge: @unchecked Sendable {
    private let hardware: JavaClass<AndroidHardwareKeyStore>

    init() throws { hardware = try JavaClass<AndroidHardwareKeyStore>() }

    func configuration() throws -> ClientConfiguration? {
        let data = try checkedJSON(hardware.readClientConfiguration())
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object.isEmpty {
            return nil
        }
        return try JSONDecoder().decode(ClientConfiguration.self, from: data)
    }

    func platform() -> ClientPlatform {
        ClientPlatform(
            enroll: { challenge in
                let bytes = try self.checkedJSON(self.hardware.enroll(challenge.base64EncodedString()))
                return try JSONDecoder().decode(AndroidEnrollmentEvidence.self, from: bytes)
            },
            signRootMessage: { message in
                struct SignatureResponse: Decodable { let signature: Data }
                let bytes = try self.checkedJSON(self.hardware.rootSign(message.base64EncodedString()))
                return try JSONDecoder().decode(SignatureResponse.self, from: bytes).signature
            },
            post: { url, body, bearer in
                guard let text = String(data: body, encoding: .utf8) else { throw ClientError.invalidServerResponse }
                return try self.checkedJSON(self.hardware.postJSON(url, text, bearer))
            },
            readState: {
                let bytes = try self.checkedJSON(self.hardware.readClientState())
                if let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], object.isEmpty { return nil }
                return bytes
            },
            writeState: { bytes in
                guard let text = String(data: bytes, encoding: .utf8) else { throw ClientError.storedStateMismatch }
                let response = try self.checkedJSON(self.hardware.writeClientState(text))
                guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any], object["ok"] as? Bool == true else {
                    throw ClientError.storedStateMismatch
                }
            }
        )
    }

    /// Cached enrollment metadata is not evidence that its private key remains
    /// usable. The adapter validates the current StrongBox entry before returning
    /// these public bytes, including on offline/restarted clients.
    func verifiedDisplayKey(matching enrolledKey: Data) throws -> String {
        let hex = hardware.publicKeyHex()
        guard hex.count == 130, hex.hasPrefix("04"),
              hex.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw ClientError.unsupportedHardware
        }
        let expected = enrolledKey.map { String(format: "%02x", $0) }.joined()
        guard hex == expected else { throw ClientError.enrollmentIdentityMismatch }
        return hex
    }

    private func checkedJSON(_ text: String) throws -> Data {
        guard let data = text.data(using: .utf8), data.count <= 1_048_576,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.invalidServerResponse
        }
        if let error = object["error"] as? String { throw ClientError.serverRejected(error) }
        return data
    }
}

enum AndroidProtocolRunner {
    private static let coordinator = Coordinator()

    static func start(displayPublicKey: @escaping @Sendable (String) -> Void) {
        // Activity recreation may create a new view while an old task is still
        // using the same app-private state. Replace its observer, not its client.
        guard let runID = coordinator.begin(displayPublicKey) else { return }
        do {
            let bridge = try AndroidProtocolBridge()
            guard let configuration = try bridge.configuration() else {
                coordinator.finish(runID)
                return
            }
            Task.detached(priority: .userInitiated) {
                defer { coordinator.finish(runID) }
                do {
                    let client = try ProtocolClient(configuration: configuration, platform: bridge.platform()) { stage in
                        AndroidSwiftUILog("SwiftKeyProtocol \(stage)")
                    }
                    let enrollment = try await client.enroll()
                    do {
                        let hex = try bridge.verifiedDisplayKey(matching: enrollment.publicKey)
                        coordinator.publish(hex, from: runID)
                    } catch {
                        coordinator.publish("StrongBox key unavailable: enrolled root could not be verified", from: runID)
                        throw error
                    }
                    let credential = try await client.ensureCurrentCredential()
                    let epochKey = credential.delegation.publicKey.map { String(format: "%02x", $0) }.joined()
                    AndroidSwiftUILog("SwiftKeyProtocol credentialReady=true accountID=\(enrollment.accountID) deviceID=\(enrollment.deviceID) epoch=\(credential.delegation.epoch) epochPublicKey=\(epochKey)")
                } catch let error as ClientError {
                    AndroidSwiftUILog("SwiftKeyProtocol failed clientError=\(error)")
                } catch let error as ProtocolError {
                    AndroidSwiftUILog("SwiftKeyProtocol failed protocolError=\(error)")
                } catch {
                    AndroidSwiftUILog("SwiftKeyProtocol failed errorType=\(type(of: error))")
                }
            }
        } catch {
            coordinator.finish(runID)
            AndroidSwiftUILog("SwiftKeyProtocol configurationUnavailable=true errorType=\(type(of: error))")
        }
    }

    /// Lock covers process-wide coordination only, never JNI/network calls or
    /// UI callbacks. Completed/failed runs unlock retries on the next appearance.
    private final class Coordinator: @unchecked Sendable {
        private let lock = NSLock()
        private var activeRun: UUID?
        private var latestRun: UUID?
        private var observer: (@Sendable (String) -> Void)?

        func begin(_ display: @escaping @Sendable (String) -> Void) -> UUID? {
            lock.lock()
            defer { lock.unlock() }
            observer = display
            guard activeRun == nil else { return nil }
            let id = UUID()
            activeRun = id
            latestRun = id
            return id
        }

        func finish(_ id: UUID) {
            lock.lock()
            defer { lock.unlock() }
            if activeRun == id { activeRun = nil }
        }

        func publish(_ value: String, from id: UUID) {
            DispatchQueue.main.async {
                self.lock.lock()
                // A newer run supersedes queued output. If only the Activity
                // changed, send this run's result to its newest view instead.
                let display = self.latestRun == id ? self.observer : nil
                self.lock.unlock()
                display?(value)
            }
        }
    }
}
#endif
