import SwiftUI
import UIKit

/// The native mock host uses the same semantic palette as SwiftKey's other UIs.
enum MockDesign {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static var canvas: Color { adaptive(0xFFFFFF, 0x1E1E1E) }
    static var surface: Color { adaptive(0xFAF8FA, 0x252326) }
    static var ink: Color { adaptive(0x1E1E1E, 0xFCFCFC) }
    static var muted: Color { adaptive(0x6B6B6B, 0xABBAB9) }
    static var line: Color { adaptive(0xE5E5E5, 0x3D3A3E) }
    static var accent: Color { adaptive(0xA02AB8, 0xD28FE2) }
    static var onAccent: Color { adaptive(0xFFFFFF, 0x1E1E1E) }
    static var danger: Color { adaptive(0xBA2922, 0xF9786A) }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("HostGrotesk-Regular", size: size, relativeTo: .body).weight(weight)
    }
    static func mono(_ size: CGFloat = 12) -> Font {
        .custom("JetBrainsMono-Regular", size: size, relativeTo: .caption)
    }
}

struct MockModeBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flask.fill")
            Text("Mock mode").font(MockDesign.font(13, weight: .semibold))
            Spacer()
            Text("LOCAL TEST ONLY").font(MockDesign.mono(10))
        }
        .foregroundStyle(MockDesign.accent)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(MockDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mock.mode.banner")
    }
}

struct MockActionStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MockDesign.font(16, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(secondary ? MockDesign.accent : MockDesign.onAccent)
            .background(secondary ? MockDesign.accent.opacity(0.09) : MockDesign.accent,
                in: RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct MockCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(MockDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MockDesign.line, lineWidth: 1))
    }
}
