import Foundation
import Testing
import SwiftUICore
@testable import SwiftKeyUI

@Test @MainActor func publicKeyPresentationIncludesEveryByte() {
    let bytes = Data([4] + Array(UInt8(0)...UInt8(63)))
    let formatted = SwiftKeyPublicKeyView.groupedHex(bytes)
    #expect(formatted.split(separator: "\n").count == 9)
    #expect(formatted.split(whereSeparator: { $0.isWhitespace }).count == 65)
    #expect(formatted.hasSuffix("3f"))
    let tree = ViewHost(SwiftKeyIdentityView(publicKeyText: formatted)).evaluate()
    let texts = allNodes(tree).compactMap { node -> String? in
        guard case .string(let text) = node.props["text"] else { return nil }
        return text
    }
    #expect(texts.contains("SwiftKey"))
    #expect(texts.contains(formatted))
    #expect(texts.contains("Your hardware identity"))
    assertProductPresentation(tree)
}

func allNodes(_ node: RenderNode) -> [RenderNode] { [node] + node.children.flatMap(allNodes) }

/// Check rendered product copy, not third-party API/type names in the renderer.
func assertProductPresentation(_ tree: RenderNode) {
    let visibleProperties: Set<String> = ["text", "title", "label", "placeholder", "contentDescription", "accessibilityLabel"]
    let forbidden = ["cupertino", "cupertio", "showcase", "component catalog"]
    for node in allNodes(tree) {
        let values = node.props.filter { visibleProperties.contains($0.key) }.map(\.value)
            + node.modifiers.filter { $0.kind == "accessibilityLabel" }.flatMap { $0.args.values }
        for value in values {
            guard case .string(let text) = value else { continue }
            #expect(!forbidden.contains { text.lowercased().contains($0) }, "Developer gallery copy in product UI: \(text)")
        }
    }
}

@Test @MainActor func primaryActionsRemainReadableInBothAppearances() throws {
    let tree = ViewHost(SwiftKeyActionLabel(title: "Approve this exact proposal")).evaluate()
    let foreground = try #require(tree.modifiers.first { $0.kind == "foregroundColor" }?.args["color"])
    let background = try #require(tree.modifiers.first { $0.kind == "background" }?.args["color"])
    func variants(_ value: PropValue) throws -> [Int] {
        guard case .array(let entries) = value else { Issue.record("Expected both appearance variants"); return [] }
        return try entries.map { entry in
            guard case .int(let argb) = entry else { throw AppearanceTestError.invalidColor }
            return argb
        }
    }
    let foregrounds = try variants(foreground), backgrounds = try variants(background)
    #expect(foregrounds.count == 2 && backgrounds.count == 2)
    func luminance(_ argb: Int) -> Double {
        func channel(_ shift: Int) -> Double {
            let value = Double((argb >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
    for (foreground, background) in zip(foregrounds, backgrounds) {
        let first = luminance(foreground), second = luminance(background)
        #expect((max(first, second) + 0.05) / (min(first, second) + 0.05) >= 4.5)
    }
}

private enum AppearanceTestError: Error { case invalidColor }
