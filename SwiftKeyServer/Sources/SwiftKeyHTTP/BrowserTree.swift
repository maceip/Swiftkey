import Foundation
import SwiftUICore

/// A renderer transport, not a second application model. Integers are strings
/// so callback IDs retain all 63 bits across the JavaScript boundary.
public enum BrowserValue: Encodable, Sendable {
    case string(String), number(Double), bool(Bool), array([BrowserValue])

    init(_ value: PropValue) {
        switch value {
        case .string(let value): self = .string(value)
        case .int(let value): self = .string(String(value))
        case .double(let value): self = value.isFinite ? .number(value) : .string(String(value))
        case .bool(let value): self = .bool(value)
        case .array(let values): self = .array(values.map(BrowserValue.init))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }
}

public struct BrowserModifier: Encodable, Sendable {
    public let kind: String
    public let args: [String: BrowserValue]
}

public struct BrowserTree: Encodable, Sendable {
    public let type: String
    public let id: String
    public let props: [String: BrowserValue]
    public let modifiers: [BrowserModifier]
    public let children: [BrowserTree]

    public init(_ node: RenderNode) {
        type = node.type; id = node.id
        // The administrative credential belongs to the browser's transport
        // shell, never to a Swift view. SwiftUICore resolves SecureField as a
        // TextField with secure=true, so inspect its props before serializing.
        let isSecureField = node.type == "SecureField"
            || (node.type == "TextField" && node.props["secure"] == .bool(true))
        props = node.props.filter { !isSecureField || $0.key != "text" }
            .mapValues(BrowserValue.init)
        modifiers = node.modifiers.map { .init(kind: $0.kind, args: $0.args.mapValues(BrowserValue.init)) }
        children = node.children.map(BrowserTree.init)
    }
}

public struct BrowserEvent: Decodable, Sendable {
    public let id: String
    public let kind: String
    public let value: String?
}

public struct BrowserEventRequest: Decodable, Sendable {
    public let revision: UInt64
    public let events: [BrowserEvent]
}

public struct BrowserEffect: Encodable, Sendable {
    public let kind: String
    public let text: String
    public let filename: String?
    public let mediaType: String?

    init(copy text: String) {
        kind = "copy"; self.text = text; filename = nil; mediaType = nil
    }
    init(download text: String, filename: String) {
        kind = "download"; self.text = text; self.filename = filename
        mediaType = "application/json"
    }
}

public struct BrowserWorkspaceResponse: Encodable, Sendable {
    public let sessionID: String
    public let revision: UInt64
    public let tree: BrowserTree
    public let effects: [BrowserEffect]
}
