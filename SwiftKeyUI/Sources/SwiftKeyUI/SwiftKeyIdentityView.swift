import SwiftUICore

/// The same identity composition is available to the Android and web hosts.
public struct SwiftKeyIdentityView: View {
    public let publicKeyText: String
    public init(publicKeyText: String) { self.publicKeyText = publicKeyText }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SwiftKeyPageHeader("Your hardware identity", subtitle: "A public key belonging to this phone.")
                SwiftKeyPublicKeyView(publicKeyText: publicKeyText)
                Text("Keep the private key on this device. This public key identifies its root; account access is checked separately.")
                    .font(SwiftKeyAppearance.body(14)).lineHeight(24)
                    .foregroundColor(SwiftKeyAppearance.muted)
            }
            .frame(maxWidth: SwiftKeyAppearance.contentWidth, alignment: .leading)
            .padding(EdgeInsets(top: 28, leading: SwiftKeyAppearance.pageInset,
                                bottom: 48, trailing: SwiftKeyAppearance.pageInset))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SwiftKeyAppearance.canvas)
        .font(SwiftKeyAppearance.body()).lineHeight(28).tracking(0.3)
    }
}
