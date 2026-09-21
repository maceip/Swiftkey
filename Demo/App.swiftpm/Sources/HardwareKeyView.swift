#if canImport(AndroidSwiftUI)
import AndroidSwiftUI
import SwiftKeyUI
import SwiftJava

@JavaClass("com.pureswift.swiftandroid.HardwareKeyStore")
class AndroidHardwareKeyStore: JavaObject {}

extension JavaClass<AndroidHardwareKeyStore> {
    @JavaStaticMethod
    func publicKeyHex() -> String
}

/// Displays the public bytes of the persistent device key. The private key
/// stays in Android StrongBox; the adapter verifies it before returning bytes.
struct HardwareKeyView: View {
    @State private var keyText: String
    @State private var protocolStarted = false

    init() {
        // Resolve the Java class on the JVM's app launch thread. Load once,
        // rather than repeating hardware operations when the body is evaluated.
        do {
            let hex = try JavaClass<AndroidHardwareKeyStore>().publicKeyHex()
            _keyText = State(initialValue: Self.formattedPublicKey(hex))
        } catch {
            _keyText = State(initialValue: "StrongBox key unavailable: unable to reach Android Keystore")
        }
    }

    var body: some View {
        SwiftKeyIdentityView(publicKeyText: keyText)
        .onAppear {
            guard !protocolStarted else { return }
            protocolStarted = true
            AndroidProtocolRunner.start { hex in
                keyText = Self.formattedPublicKey(hex)
            }
        }
    }

    private static func formattedPublicKey(_ value: String) -> String {
        guard value.count == 130, value.hasPrefix("04"),
              value.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            return value.hasPrefix("StrongBox key unavailable:")
                ? value : "StrongBox key unavailable: invalid public key bytes"
        }
        let characters = Array(value)
        let bytes = stride(from: 0, to: characters.count, by: 2).map {
            String(characters[$0...($0 + 1)])
        }
        return stride(from: 0, to: bytes.count, by: 8).map {
            bytes[$0..<min($0 + 8, bytes.count)].joined(separator: " ")
        }.joined(separator: "\n")
    }
}
#endif
