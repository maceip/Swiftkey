// Native iOS counterparts for the catalog's Compose-specific examples.
// The simulator staging script adds this file without changing upstream sources.
import SwiftUI

struct AlertButton: Identifiable {
    let id = UUID()
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

extension View {
    func alert(_ title: String, isPresented: Binding<Bool>, message: String,
               buttons: [AlertButton] = []) -> some View {
        alert(title, isPresented: isPresented) {
            if buttons.isEmpty { Button("OK", role: .cancel) {} }
            ForEach(buttons) { item in
                Button(item.title, role: item.role, action: item.action)
            }
        } message: { Text(message) }
    }

    func confirmationDialog(_ title: String, isPresented: Binding<Bool>,
                            titleVisibility: Visibility, message: String,
                            buttons: [AlertButton]) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility) {
            ForEach(buttons) { item in
                Button(item.title, role: item.role, action: item.action)
            }
        } message: { Text(message) }
    }
}

extension Section where Parent == Text, Content: View, Footer == Text {
    init(header: String, footer: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { Text(header) }, footer: { Text(footer) })
    }
}

struct NativeCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct ModifierNode {
    let kind: String
}

protocol RenderModifier: ViewModifier {
    var _modifierNode: ModifierNode { get }
}

extension RenderModifier {
    func body(content: Content) -> some View {
        content.overlay(Rectangle().stroke(.red, lineWidth: 2))
    }
}

enum NativeProperty: ExpressibleByIntegerLiteral {
    case double(Double)
    case color(Color)

    init(integerLiteral value: Int) { self = .double(Double(value)) }

    var number: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    var tint: Color? {
        if case .color(let value) = self { return value }
        return nil
    }
}

enum NativeAction {
    case double((Double) -> Void)

    func call(_ value: Double) {
        if case .double(let action) = self { action(value) }
    }
}

struct ComposableView<Content: View>: View {
    let name: String
    let props: [String: NativeProperty]
    let actions: [String: NativeAction]
    let content: Content

    init(
        _ name: String,
        props: [String: NativeProperty] = [:],
        actions: [String: NativeAction] = [:],
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.props = props
        self.actions = actions
        self.content = content()
    }

    var body: some View {
        switch name {
        case "RatingBar":
            let rating = props["rating"]?.number ?? 0
            let maximum = props["max"]?.number ?? 5
            GeometryReader { geometry in
                HStack(spacing: 8) {
                    ForEach(0..<Int(maximum), id: \.self) { index in
                        let fill = rating - Double(index)
                        Image(systemName: fill >= 1 ? "star.fill" : fill >= 0.5 ? "star.leadinghalf.filled" : "star")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let fraction = max(0, min(1, value.location.x / geometry.size.width))
                    actions["onRatingChanged"]?.call((fraction * maximum * 2).rounded() / 2)
                })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rating")
            .accessibilityValue("\(rating) of \(maximum)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: actions["onRatingChanged"]?.call(min(maximum, rating + 0.5))
                case .decrement: actions["onRatingChanged"]?.call(max(0, rating - 0.5))
                @unknown default: break
                }
            }
        case "DashedBorder":
            content.padding(18).overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(props["color"]?.tint ?? .blue,
                            style: StrokeStyle(lineWidth: 3, dash: [12, 7]))
            }
        default:
            Text("Unregistered custom view: \(name)")
                .foregroundStyle(.red)
        }
    }
}

extension ComposableView where Content == EmptyView {
    init(
        _ name: String,
        props: [String: NativeProperty] = [:],
        actions: [String: NativeAction] = [:]
    ) {
        self.init(name, props: props, actions: actions) { EmptyView() }
    }
}
