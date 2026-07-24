//
//  KotlinBindings.swift
//  ComposeUI
//
//  Swift→Kotlin bindings for the interpreter's node model. This is the safe
//  bridge direction: methods resolve by name+signature lookup and fail loudly
//  on mismatch.
//

import SwiftJava

/// Binding for `com.pureswift.swiftui.ViewNode`.
@JavaClass("com.pureswift.swiftui.ViewNode")
open class ViewNodeObject: JavaObject {

    /// The bridge constructor: one JNI call per node, arrays crossing as
    /// single arguments. Scalars cross typed — a kind tag per value selects
    /// the string slot or the bits slot (doubles bit-cast into the long) —
    /// so only array-valued props take the JSON path. Negative count/provider
    /// mean "absent".
    @JavaMethod
    @_nonoverride public convenience init(
        _ type: String,
        _ id: String,
        _ propKeys: [String],
        _ propKinds: [Int32],
        _ propStrings: [String],
        _ propBits: [Int64],
        _ modifierKinds: [String],
        _ modifierArgCounts: [Int32],
        _ argKeys: [String],
        _ argKinds: [Int32],
        _ argStrings: [String],
        _ argBits: [Int64],
        _ children: [ViewNodeObject?],
        _ count: Int32,
        _ itemProviderId: Int64,
        environment: JNIEnvironment? = nil
    )
}

/// Binding for `com.pureswift.swiftui.TreeStore`.
@JavaClass("com.pureswift.swiftui.TreeStore")
open class TreeStore: JavaObject {

    /// Assigns a freshly materialized tree; Compose recomposes changed subtrees.
    @JavaMethod
    open func update(_ node: ViewNodeObject?)

    /// Splices a re-evaluated subtree over the node with `targetId`; false
    /// when the target isn't in the current tree (caller does a full update).
    @JavaMethod
    open func patch(_ targetId: String, _ node: ViewNodeObject?) -> Bool
}
