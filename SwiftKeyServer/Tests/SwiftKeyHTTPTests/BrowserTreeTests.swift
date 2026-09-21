import Foundation
import SwiftUICore
import Testing
@testable import SwiftKeyHTTP

@Test @MainActor func browserTreeOmitsResolvedSecureFieldTextAndRetainsPublicControls() throws {
    let secret = "secure-field-regression-secret"
    let host = ViewHost(VStack {
        TextField("Account label", text: .constant("Public account label"))
        SecureField("Credential", text: .constant(secret))
    })
    let node = host.evaluate()
    let secureNode = try #require(node.children.first { $0.props["secure"] == .bool(true) })
    // Exercise the real evaluator representation rather than an invented
    // SecureField node, which previously let the transport regression escape.
    #expect(secureNode.type == "TextField")
    #expect(secureNode.props["text"] == .string(secret))
    let encoded = try JSONEncoder().encode(BrowserTree(node))
    #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
    let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let children = try #require(root["children"] as? [[String: Any]])
    let props = children.compactMap { $0["props"] as? [String: Any] }
    let secure = try #require(props.first { $0["secure"] as? Bool == true })
    #expect(secure["text"] == nil)
    #expect(secure["placeholder"] as? String == "Credential")
    #expect(secure["onChange"] as? String != nil)
    #expect(props.contains { $0["text"] as? String == "Public account label" })
}

@Test func browserTreePreservesExplicitlyNonsecureTextAndRedactsLegacySecureNode() throws {
    let node = RenderNode(type: "VStack", id: "root", children: [
        RenderNode(type: "TextField", id: "public", props: ["secure": .bool(false), "text": .string("Public label")]),
        RenderNode(type: "SecureField", id: "legacy", props: ["text": .string("legacy-secret")])
    ])
    let encoded = String(decoding: try JSONEncoder().encode(BrowserTree(node)), as: UTF8.self)
    #expect(encoded.contains("Public label"))
    #expect(!encoded.contains("legacy-secret"))
}
