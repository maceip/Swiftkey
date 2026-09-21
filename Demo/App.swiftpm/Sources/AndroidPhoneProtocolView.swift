#if canImport(AndroidSwiftUI)
import AndroidSwiftUI
import Foundation
import SwiftKeyApplication
import SwiftKeyUI

/// Explicit entry preserves the original v1 identity view and never migrates it.
struct SwiftKeyPhoneEntryView: View {
    @State private var showsPairing = false
    var body: some View {
        VStack(spacing: 0) {
            if showsPairing {
                AndroidPhoneProtocolView(onClose: { showsPairing = false })
            } else {
                HStack {
                    Text("Existing identity · legacy v1").font(.system(size: 12))
                        .foregroundColor(SwiftKeyAppearance.muted)
                    Spacer()
                    Button("Pair phones · v2") { showsPairing = true }
                        .accessibilityIdentifier("swiftkey.open-phone-protocol")
                }.padding(16).background(SwiftKeyAppearance.canvas)
                HardwareKeyView()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AndroidPhoneProtocolView: View {
    let onClose: () -> Void
    private let session: AndroidPhoneProtocolSession?
    private let observerID = UUID()
    @State private var snapshot = PhoneProtocolSnapshot()
    @State private var drafts = PhoneProtocolDrafts()
    @State private var message: String? = nil
    @State private var now = UInt64(max(0, Date().timeIntervalSince1970))
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        session = try? AndroidPhoneProtocolCoordinator.shared()
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to legacy identity") {
                    Task { await session?.disconnect(observerID) }
                    onClose()
                }.accessibilityIdentifier("swiftkey.close-phone-protocol")
                Spacer()
                Button("Trusted authority") { Task { await session?.configureAuthority() } }
                    .disabled(snapshot.busy).accessibilityIdentifier("swiftkey.configure-pairing-authority")
            }.padding(16).background(SwiftKeyAppearance.canvas)
            if let message {
                Text(message).font(.system(size: 14)).padding(16)
                    .background(SwiftKeyAppearance.citron).accessibilityIdentifier("swiftkey.native-phone-message")
            }
            PhoneProtocolView(snapshot: snapshot, drafts: $drafts, now: now,
                effects: Set(PhoneHostCapability.allCases),
                onAction: { action in Task { await session?.send(action) } },
                onEffect: { effect in Task { await session?.effect(effect) } })
        }
        .onAppear {
            guard let session else {
                message = "Native protocol host unavailable. No key or account operation was started."
                return
            }
            Task {
                await session.connect(observerID) { next, status in
                    snapshot = next
                    now = UInt64(max(0, Date().timeIntervalSince1970))
                    if let status { message = status }
                    else if next.availability == .nativeReady { message = nil }
                }
            }
        }
        .onDisappear { Task { await session?.disconnect(observerID) } }
    }
}
#endif
