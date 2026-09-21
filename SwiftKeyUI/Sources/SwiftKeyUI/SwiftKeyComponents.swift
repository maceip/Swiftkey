import SwiftUICore

/// Nested rounded backgrounds produce the same one-point card border on both hosts.
struct SwiftKeyCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SwiftKeyAppearance.panelInset)
            .background(SwiftKeyAppearance.surface).cornerRadius(SwiftKeyAppearance.cardRadius - 1)
            .padding(1).background(SwiftKeyAppearance.border).cornerRadius(SwiftKeyAppearance.cardRadius)
    }
}

struct SwiftKeyPageHeader: View {
    let title: String
    let subtitle: String?
    init(_ title: String, subtitle: String? = nil) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                SwiftKeyBrandMark()
                Text("SwiftKey").font(SwiftKeyAppearance.body(18, weight: 560)).lineHeight(27).tracking(-0.3)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(SwiftKeyAppearance.heading(32)).lineHeight(48).tracking(-0.3)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(SwiftKeyAppearance.body()).lineHeight(28)
                        .foregroundColor(SwiftKeyAppearance.muted)
                }
            }
        }.foregroundColor(SwiftKeyAppearance.ink)
    }
}

struct SwiftKeyActionLabel: View {
    let title: String
    var secondary = false
    var body: some View {
        Text(title).font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).tracking(0)
            .multilineTextAlignment(.leading)
            .foregroundColor(secondary ? SwiftKeyAppearance.accent : SwiftKeyAppearance.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            .background(secondary ? SwiftKeyAppearance.emphasis : SwiftKeyAppearance.accent)
            .cornerRadius(SwiftKeyAppearance.controlRadius)
    }
}

struct SwiftKeyStatusLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(SwiftKeyAppearance.body(14, weight: 500)).lineHeight(21).tracking(0)
            .foregroundColor(SwiftKeyAppearance.accent)
            .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
            .background(SwiftKeyAppearance.emphasis).cornerRadius(SwiftKeyAppearance.controlRadius)
    }
}
