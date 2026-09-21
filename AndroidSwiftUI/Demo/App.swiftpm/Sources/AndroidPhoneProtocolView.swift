#if canImport(AndroidSwiftUI)
import AndroidSwiftUI
import Foundation
import SwiftKeyApplication
import SwiftKeyUI

/// Explicit entry preserves the original v1 identity view and never migrates it.
struct SwiftKeyPhoneEntryView: View {
    @State private var showsPairing = false
    @State private var showsCupertinoCatalog = false
    var body: some View {
        VStack(spacing: 0) {
            if showsCupertinoCatalog {
                VStack(spacing: 0) {
                    Button { showsCupertinoCatalog = false } label: {
                        SwiftKeyHostActionLabel("Back to SwiftKey", secondary: true)
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("swiftkey.close-cupertino-catalog")
                        .padding(SwiftKeyAppearance.pageInset)
                    CupertinoCatalogView()
                }
            } else if showsPairing {
                AndroidPhoneProtocolView(onClose: { showsPairing = false })
            } else {
                HStack {
                    Text("Existing identity · legacy v1").font(SwiftKeyAppearance.body(12)).lineHeight(18)
                        .foregroundColor(SwiftKeyAppearance.muted)
                    Spacer()
                    Button { showsPairing = true } label: {
                        SwiftKeyHostActionLabel("Pair phones · v2")
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("swiftkey.open-phone-protocol")
                }.padding(16).background(SwiftKeyAppearance.canvas)
                Button { showsCupertinoCatalog = true } label: {
                    SwiftKeyHostActionLabel("Cupertino component catalog", secondary: true)
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("swiftkey.open-cupertino-catalog")
                    .padding(EdgeInsets(top: 0, leading: SwiftKeyAppearance.pageInset,
                                       bottom: 12, trailing: SwiftKeyAppearance.pageInset))
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
            VStack(spacing: 8) {
                Button {
                    Task { await session?.disconnect(observerID) }
                    onClose()
                } label: {
                    SwiftKeyHostActionLabel("Back to legacy identity", secondary: true)
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("swiftkey.close-phone-protocol")
                Button { Task { await session?.configureAuthority() } } label: {
                    SwiftKeyHostActionLabel("Trusted authority", secondary: true)
                }
                    .buttonStyle(.plain)
                    .disabled(snapshot.busy).accessibilityIdentifier("swiftkey.configure-pairing-authority")
            }.padding(SwiftKeyAppearance.pageInset).background(SwiftKeyAppearance.canvas)
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

/// Host navigation follows the shared product controls; catalog content keeps
/// the native Cupertino appearance of the component being demonstrated.
private struct SwiftKeyHostActionLabel: View {
    let title: String
    let secondary: Bool

    init(_ title: String, secondary: Bool = false) {
        self.title = title
        self.secondary = secondary
    }

    var body: some View {
        Text(title)
            .font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).tracking(0)
            .multilineTextAlignment(.leading)
            .foregroundColor(secondary ? SwiftKeyAppearance.accent : SwiftKeyAppearance.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(secondary ? SwiftKeyAppearance.emphasis : SwiftKeyAppearance.accent)
            .cornerRadius(SwiftKeyAppearance.controlRadius)
    }
}
#endif
