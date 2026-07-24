//
//  Materializer.swift
//  ComposeUI
//
//  Walks the core's RenderNode IR and constructs the interpreter's Kotlin
//  ViewNode objects — the typed transport that replaces string serialization.
//

import SwiftUICore
import SwiftJava

public enum Materializer {

    // value kinds understood by the Kotlin bridge constructor
    private static let kindString: Int32 = 0
    private static let kindDouble: Int32 = 1
    private static let kindBool: Int32 = 2
    private static let kindInt: Int32 = 3
    private static let kindJSON: Int32 = 4

    /// One scalar's typed slots: strings ride the string slot; numbers and
    /// bools ride the bits slot (doubles bit-cast, so 64-bit callback ids and
    /// doubles both cross exactly); only arrays fall back to JSON text.
    private static func slots(for value: PropValue) -> (kind: Int32, string: String, bits: Int64) {
        switch value {
        case .string(let string):
            return (kindString, string, 0)
        case .double(let double):
            return (kindDouble, "", Int64(bitPattern: double.bitPattern))
        case .bool(let bool):
            return (kindBool, "", bool ? 1 : 0)
        case .int(let int):
            return (kindInt, "", Int64(int))
        case .array:
            return (kindJSON, jsonLiteral(value), 0)
        }
    }

    /// Builds the Kotlin mirror of an IR tree, depth-first.
    public static func materialize(_ node: RenderNode) -> ViewNodeObject {
        var propKeys: [String] = []
        var propKinds: [Int32] = []
        var propStrings: [String] = []
        var propBits: [Int64] = []
        for (key, value) in node.props {
            let slot = slots(for: value)
            propKeys.append(key)
            propKinds.append(slot.kind)
            propStrings.append(slot.string)
            propBits.append(slot.bits)
        }
        var modifierKinds: [String] = []
        var modifierArgCounts: [Int32] = []
        var argKeys: [String] = []
        var argKinds: [Int32] = []
        var argStrings: [String] = []
        var argBits: [Int64] = []
        for modifier in node.modifiers {
            modifierKinds.append(modifier.kind)
            modifierArgCounts.append(Int32(modifier.args.count))
            for (key, value) in modifier.args {
                let slot = slots(for: value)
                argKeys.append(key)
                argKinds.append(slot.kind)
                argStrings.append(slot.string)
                argBits.append(slot.bits)
            }
        }
        let children = node.children.map { materialize($0) as ViewNodeObject? }
        return ViewNodeObject(
            node.type,
            node.id,
            propKeys,
            propKinds,
            propStrings,
            propBits,
            modifierKinds,
            modifierArgCounts,
            argKeys,
            argKinds,
            argStrings,
            argBits,
            children,
            Int32(node.count ?? -1),
            Int64(-1)
        )
    }

    /// Encodes an array-valued prop as a JSON literal (`["a",1,true]`), the one
    /// value shape the typed slots don't carry. Scalars never reach this — they
    /// cross typed — so the only recursion is through nested array elements.
    static func jsonLiteral(_ value: PropValue) -> String {
        switch value {
        case .string(let string):
            return escapeJSON(string)
        case .double(let double):
            return "\(double)"
        case .int(let int):
            return "\(int)"
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let values):
            return "[" + values.map(jsonLiteral).joined(separator: ",") + "]"
        }
    }

    /// Minimal JSON string escaping (quotes, backslashes, control characters).
    static func escapeJSON(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
