import Foundation
import SwiftUICore

/// Displays every public byte. Validation and key ownership remain with the
/// caller; presentation never generates keys or abbreviates their identity.
public struct SwiftKeyPublicKeyView: View {
    public let publicKeyText: String
    public let compact: Bool

    public init(publicKeyText: String) { self.publicKeyText = publicKeyText; self.compact = false }
    /// The compact treatment fits eight-byte rows inside an inset workspace
    /// card at a 320-point viewport. Both hosts use the same treatment.
    public init(publicKey: Data, compact: Bool = false) {
        self.publicKeyText = Self.groupedHex(publicKey); self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PUBLIC KEY").font(SwiftKeyAppearance.technical(12, weight: 500)).lineHeight(18).tracking(0.3)
                .foregroundColor(SwiftKeyAppearance.muted)
            Text(publicKeyText)
                .font(SwiftKeyAppearance.technical(compact ? 13 : SwiftKeyAppearance.keySize)).lineHeight(compact ? 21 : 24).tracking(0)
                .foregroundColor(SwiftKeyAppearance.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("swiftkey.public-key")
        }
        .padding(compact ? 12 : SwiftKeyAppearance.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SwiftKeyAppearance.codeSurface).cornerRadius(SwiftKeyAppearance.cardRadius - 1)
        .padding(1).background(SwiftKeyAppearance.border).cornerRadius(SwiftKeyAppearance.cardRadius)
    }

    public static func groupedHex(_ bytes: Data) -> String {
        let alphabet = Array("0123456789abcdef")
        let values = bytes.map { byte in String([alphabet[Int(byte >> 4)], alphabet[Int(byte & 15)]]) }
        return stride(from: 0, to: values.count, by: 8).map { start in
            values[start..<min(start + 8, values.count)].joined(separator: " ")
        }.joined(separator: "\n")
    }
}
