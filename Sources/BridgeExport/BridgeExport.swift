//
//  BridgeExport.swift
//  The jextract-JNI export surface the host app consumes.
//
//  jextract (mode: jni) generates a Java class `com.pureswift.bridge.BridgeExport`
//  mirroring these global functions, plus the `@_cdecl` thunks. This target is
//  linked INTO the app library (the Android `.so` / desktop dylib), not shipped
//  as its own — a separate library would embed a second copy of ComposeUI and
//  thus a distinct, never-started `BridgeRuntime.current`, so dispatch would
//  no-op. The generated Java therefore emits no `loadLibrary` (config
//  `overrideStaticBlockLibraryLoading: []`): the app's boot already loaded the
//  single image these thunks resolve against.
//
//  Only the event-dispatch surface lives here for now: these are plain
//  Java→Swift calls (no `enableJavaCallbacks` needed), replacing the five
//  hand-matched scalar `SwiftCallbackSink` externals. `itemNode` stays a
//  hand-matched external (it returns a JavaKit-wrapped `ViewNode`, which
//  jextract cannot express), and the main-thread scheduler / closure boxing
//  move in a later phase (they need the Swift→Java callback machinery).
//

import ComposeUI

/// Dispatches a `() -> Void` handler by id into the active runtime.
public func bridgeInvokeVoid(_ id: Int64) {
    BridgeRuntime.current?.invokeVoid(id)
}

/// Dispatches a `(Bool) -> Void` handler by id.
public func bridgeInvokeBool(_ id: Int64, _ value: Bool) {
    BridgeRuntime.current?.invokeBool(id, value)
}

/// Dispatches a `(Double) -> Void` handler by id.
public func bridgeInvokeDouble(_ id: Int64, _ value: Double) {
    BridgeRuntime.current?.invokeDouble(id, value)
}

/// Dispatches an `(Int) -> Void` handler by id.
public func bridgeInvokeInt(_ id: Int64, _ value: Int32) {
    BridgeRuntime.current?.invokeInt(id, Int(value))
}

/// Dispatches a `(String) -> Void` handler by id.
public func bridgeInvokeString(_ id: Int64, _ value: String) {
    BridgeRuntime.current?.invokeString(id, value)
}
