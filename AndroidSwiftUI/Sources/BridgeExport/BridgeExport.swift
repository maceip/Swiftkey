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
//  The event-dispatch functions below are plain Java→Swift calls. `BridgeHost`
//  and `SwiftTask` are the opposite direction (Swift calling back into
//  Kotlin) and need `enableJavaCallbacks: true`: jextract turns the protocol
//  into a Java interface Kotlin implements, and generates the Swift-side box
//  that lets Swift call through to it. `itemNode` stays a hand-matched
//  external (it returns a JavaKit-wrapped `ViewNode`, which jextract cannot
//  express).
//

import ComposeUI

/// Kotlin-implemented main-thread scheduler, installed once at startup
/// (`bridgeSetHost`). Replaces the hand-matched `Runnable`/`SwiftObject` JNI
/// pair: Swift calls `postToMain` instead of building a `Runnable` by hand,
/// so a signature drift fails to compile instead of reading garbage at the
/// JNI boundary.
public protocol BridgeHost {
    /// Runs `task` on the platform main thread/looper. On Android this must
    /// land on a `Handler.post` frame, not a native dispatch-queue drain — see
    /// the invariant documented at the `AndroidSwiftUIApp.run` call site.
    func postToMain(_ task: SwiftTask)
}

/// A boxed `() -> Void` Kotlin holds and runs later from
/// `BridgeHost.postToMain`, replacing `SwiftObject`'s hand-rolled retain map.
/// jextract's `SwiftArena` owns the instance's lifetime on the Java side.
public final class SwiftTask {

    private let block: () -> Void

    // Not public: only Swift ever constructs a `SwiftTask` (in
    // `bridgeScheduleMain`); Kotlin only ever receives instances handed to
    // `postToMain` and calls `run()`. A public init with an escaping-closure
    // parameter trips a jextract wrap-java bug — the generated Java nested
    // type for the closure is named `SwiftTask$init$block`, and translating
    // that back to Swift tries to declare a type literally named `init`,
    // which is a reserved keyword.
    init(_ block: @escaping () -> Void) {
        self.block = block
    }

    public func run() {
        block()
    }
}

private var currentHost: (any BridgeHost)?

/// Installs the process-wide `BridgeHost`. Called once at startup, before
/// `AndroidSwiftUIApp.run`.
public func bridgeSetHost(_ host: some BridgeHost) {
    currentHost = host
}

/// Schedules `block` on the main thread through the installed host.
public func bridgeScheduleMain(_ block: @escaping () -> Void) {
    guard let currentHost else {
        assertionFailure("bridgeSetHost was never called")
        block()
        return
    }
    currentHost.postToMain(SwiftTask(block))
}

// MARK: - Android lifecycle
//
// The Swift side of these lives in `AndroidSwiftUI`: it needs `AndroidKit`,
// which this target can't depend on (the desktop demo links `BridgeExport`
// too), and `AndroidSwiftUI` already depends on *this* target, so importing
// it back would be a cycle. The call is therefore handed off through fixed
// symbols — the same trick `AndroidSwiftUIMain` already uses. Unlike a JNI
// name match, a missing or misspelled definition fails at link time rather
// than reading garbage at runtime.
//
// Every product linking `BridgeExport` must define all four. `AndroidSwiftUI`
// does for Android hosts; the desktop rig defines no-ops.

@_silgen_name("swiftui_applicationCreated")
func swiftui_applicationCreated()

@_silgen_name("swiftui_applicationTerminated")
func swiftui_applicationTerminated()

@_silgen_name("swiftui_activityCreated")
func swiftui_activityCreated()

@_silgen_name("swiftui_activityResult")
func swiftui_activityResult(_ requestCode: Int32, _ resultCode: Int32)

/// `Application.onCreate`. Binds the main looper before anything renders.
public func bridgeApplicationCreated() {
    swiftui_applicationCreated()
}

/// `Application.onTerminate`.
public func bridgeApplicationTerminated() {
    swiftui_applicationTerminated()
}

/// `Activity.onCreate`. Reads the activity back out of `HostContext` and
/// starts the app; the activity itself can't come through as an argument.
public func bridgeActivityCreated() {
    swiftui_activityCreated()
}

/// `Activity.onActivityResult`. The `Intent` stays in `HostContext` — only
/// the primitive codes cross here.
public func bridgeActivityResult(_ requestCode: Int32, _ resultCode: Int32) {
    swiftui_activityResult(requestCode, resultCode)
}

// MARK: - Event dispatch

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
