import SwiftUICore

/// Semantic values converted from the supplied design-system 4.2.3 OKLCH
/// themes, rather than the approximate hex comments in that source.
public enum SwiftKeyAppearance {
    public static let canvas = adaptive(0xFFFFFF, 0x1E1E1E)
    public static let surface = adaptive(0xFFFFFF, 0x252326)
    public static let subtle = adaptive(0xFAF8FA, 0x252326)
    public static let codeSurface = adaptive(0xFDFCFE, 0x252326)
    public static let ink = adaptive(0x1E1E1E, 0xFCFCFC)
    public static let muted = adaptive(0x6B6B6B, 0xABBAB9)
    public static let border = adaptive(0xE5E5E5, 0x2F2D30)
    public static let accent = adaptive(0xA02AB8, 0xD28FE2)
    public static let onAccent = adaptive(0xFFFFFF, 0x1E1E1E)
    public static let emphasis = Color(light: color(0xA02AB8, opacity: 0.07), dark: color(0xD28FE2, opacity: 0.12))
    public static let danger = adaptive(0xD33C33, 0xF9786A)
    public static let warning = adaptive(0xC18724, 0xDCA249)
    public static let success = adaptive(0x03AA5C, 0x50C67D)

    // Retained for existing host integrations that use these semantic aliases.
    public static let forest = accent
    public static let citron = emphasis

    public static let pageInset: Double = 20
    public static let panelInset: Double = 16
    public static let contentWidth: Double = 520
    public static let titleSize: Double = 32
    public static let keySize: Double = 14
    public static let cardRadius: Double = 12
    public static let controlRadius: Double = 8

    public static func body(_ size: Double = 16, weight: Double = 400) -> Font {
        .custom("Host Grotesk", size: size).weight(weight)
    }
    public static func heading(_ size: Double = 24) -> Font { body(size, weight: 560) }
    public static func technical(_ size: Double = 13, weight: Double = 400) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(light: color(light), dark: color(dark))
    }
    private static func color(_ rgb: UInt32, opacity: Double = 1) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255,
              blue: Double(rgb & 255) / 255, opacity: opacity)
    }
}

public struct SwiftKeyBrandMark: View {
    public init() {}
    public var body: some View {
        HStack(alignment: .top, spacing: 3) {
            Rectangle().fill(SwiftKeyAppearance.accent).frame(width: 8, height: 26).cornerRadius(4)
            VStack(spacing: 3) {
                Rectangle().fill(SwiftKeyAppearance.accent).frame(width: 15, height: 8).cornerRadius(4)
                Rectangle().fill(SwiftKeyAppearance.accent).frame(width: 15, height: 15).cornerRadius(4).opacity(0.45)
            }
        }
        .accessibilityHidden(true)
    }
}
