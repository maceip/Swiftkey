//
//  AndroidApplication.swift
//  AndroidSwiftUI
//
//  Created by Alsey Coleman Miller on 6/8/25.
//

import AndroidKit
import BridgeExport
#if canImport(AndroidLooper)
import AndroidLooper
#endif

/// The reusable host application, implemented in `:androidbridge`. A host app
/// names the Kotlin `SwiftUIApplication` (or a subclass) in its manifest.
@JavaClass("com.pureswift.swiftandroid.SwiftUIApplication")
open class SwiftUIApplication: AndroidApp.Application {}

/// `Application.onCreate`, handed off from the generated `BridgeExport` entry
/// point (which can't reach this module — see the note at its declaration).
@_cdecl("swiftui_applicationCreated")
func swiftui_applicationCreated() {
    SwiftUIApplication.log("\(#function)")

    // Bind the Android main looper to `AndroidMainActor` at process launch.
    // `Application.onCreate` runs on the main thread — the required call site
    // — so `@MainActor` and `DispatchQueue.main` dispatch correctly from here
    // on, without hand-draining `RunLoop.main`.
    #if canImport(AndroidLooper)
    let boundMainLooper = AndroidMainActor.setupMainLooper()
    SwiftUIApplication.log("AndroidMainActor.setupMainLooper() -> \(boundMainLooper)")
    #endif
}

/// `Application.onTerminate`.
@_cdecl("swiftui_applicationTerminated")
func swiftui_applicationTerminated() {
    SwiftUIApplication.log("\(#function)")
}

extension SwiftUIApplication {

    static var logTag: String { "SwiftUIApplication" }

    static func log(_ string: String) {
        let log = try! JavaClass<AndroidUtil.Log>()
        _ = log.v(Self.logTag, string)
    }
}

/// The app's entry point, defined by the application module.
@_silgen_name("AndroidSwiftUIMain")
func AndroidSwiftUIMain()
