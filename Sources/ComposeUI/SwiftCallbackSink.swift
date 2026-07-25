//
//  SwiftCallbackSink.swift
//  ComposeUI
//
//  The one remaining hand-matched Kotlin→Swift external: a lazy-row query
//  returning a materialized `ViewNode` subtree. It can't move to the generated
//  `BridgeExport` bindings because an exported Swift function can't return a
//  JavaKit-wrapped type. The JNI symbol derives from THIS signature, so the
//  Kotlin `external fun itemNode` in SwiftCallbackSink.kt must stay in sync.
//  The five scalar event callbacks now cross through `BridgeExport`.
//

import SwiftJava

@JavaClass("com.pureswift.swiftui.SwiftCallbackSink")
open class SwiftCallbackSink: JavaObject {
}

@JavaImplementation("com.pureswift.swiftui.SwiftCallbackSink")
extension SwiftCallbackSink {

    @JavaMethod
    func itemNode(_ id: Int64, _ index: Int32) -> ViewNodeObject? {
        BridgeRuntime.current?.itemNode(id, Int(index))
    }
}
