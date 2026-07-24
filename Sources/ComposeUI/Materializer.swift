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

    // scalar value kinds understood by the Kotlin bridge constructor
    private static let kindString: Int32 = 0
    private static let kindDouble: Int32 = 1
    private static let kindBool: Int32 = 2
    private static let kindInt: Int32 = 3
    private static let kindJSON: Int32 = 4
    // homogeneous-array kinds: the bits slot packs (offset << 32 | count) into
    // the node's shared string or long pool
    private static let kindStringArray: Int32 = 5
    private static let kindDoubleArray: Int32 = 6
    private static let kindBoolArray: Int32 = 7
    private static let kindIntArray: Int32 = 8

    /// One node's array pools, filled while its values are encoded and handed
    /// to the constructor. Homogeneous arrays append their elements here and
    /// carry a packed (offset, count) reference in place of a JSON string.
    private struct Pools {
        var strings: [String] = []
        var longs: [Int64] = []
    }

    private static func pack(offset: Int, count: Int) -> Int64 {
        (Int64(offset) << 32) | Int64(count)
    }

    /// One value's typed slots: strings ride the string slot; numbers and bools
    /// ride the bits slot (doubles bit-cast, so 64-bit callback ids and doubles
    /// both cross exactly); a homogeneous array appends to a pool and packs its
    /// (offset, count) into the bits slot; only a nested/mixed array falls back
    /// to JSON text.
    private static func slots(for value: PropValue, pools: inout Pools) -> (kind: Int32, string: String, bits: Int64) {
        switch value {
        case .string(let string):
            return (kindString, string, 0)
        case .double(let double):
            return (kindDouble, "", Int64(bitPattern: double.bitPattern))
        case .bool(let bool):
            return (kindBool, "", bool ? 1 : 0)
        case .int(let int):
            return (kindInt, "", Int64(int))
        case .array(let elements):
            return arraySlot(elements, value: value, pools: &pools)
        }
    }

    /// Routes an array to a typed pool when its elements share one scalar kind;
    /// otherwise (nested or mixed — alert `buttons`, `searches`) to JSON.
    private static func arraySlot(
        _ elements: [PropValue],
        value: PropValue,
        pools: inout Pools
    ) -> (kind: Int32, string: String, bits: Int64) {
        func mapAll<T>(_ transform: (PropValue) -> T?) -> [T]? {
            var out: [T] = []
            out.reserveCapacity(elements.count)
            for element in elements {
                guard let mapped = transform(element) else { return nil }
                out.append(mapped)
            }
            return out
        }
        guard !elements.isEmpty else { return (kindJSON, "[]", 0) }
        if let strings = mapAll({ if case let .string(s) = $0 { s } else { nil } }) {
            let bits = pack(offset: pools.strings.count, count: strings.count)
            pools.strings.append(contentsOf: strings)
            return (kindStringArray, "", bits)
        }
        if let ints = mapAll({ if case let .int(i) = $0 { Int64(i) } else { nil } }) {
            let bits = pack(offset: pools.longs.count, count: ints.count)
            pools.longs.append(contentsOf: ints)
            return (kindIntArray, "", bits)
        }
        if let doubles = mapAll({ if case let .double(d) = $0 { Int64(bitPattern: d.bitPattern) } else { nil } }) {
            let bits = pack(offset: pools.longs.count, count: doubles.count)
            pools.longs.append(contentsOf: doubles)
            return (kindDoubleArray, "", bits)
        }
        if let bools = mapAll({ if case let .bool(b) = $0 { Int64(b ? 1 : 0) } else { nil } }) {
            let bits = pack(offset: pools.longs.count, count: bools.count)
            pools.longs.append(contentsOf: bools)
            return (kindBoolArray, "", bits)
        }
        return (kindJSON, jsonLiteral(value), 0)
    }

    /// Builds the Kotlin mirror of an IR tree, depth-first.
    public static func materialize(_ node: RenderNode) -> ViewNodeObject {
        var pools = Pools()
        var propKeys: [String] = []
        var propKinds: [Int32] = []
        var propStrings: [String] = []
        var propBits: [Int64] = []
        for (key, value) in node.props {
            let slot = slots(for: value, pools: &pools)
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
                let slot = slots(for: value, pools: &pools)
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
            pools.strings,
            pools.longs,
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
