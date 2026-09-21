//
//  SwiftUIActivity.swift
//  AndroidSwiftUI
//
//  Created by Alsey Coleman Miller on 6/8/25.
//

import Foundation
import AndroidKit
import JavaLang
import BridgeExport

/// The reusable host activity, implemented in `:androidbridge`. A host app
/// subclasses the Kotlin `SwiftUIActivity`; nothing on either side declares a
/// JNI symbol by hand.
@JavaClass("com.pureswift.swiftandroid.SwiftUIActivity")
open class SwiftUIActivity: AndroidApp.Activity {

    public internal(set) static var shared: SwiftUIActivity!

    @JavaMethod
    open func setRootView(_ view: AndroidView.View?)
}

/// Kotlin's holder for the Java objects the generated bridge can't carry.
/// Reading it by name lookup is the safe direction across the boundary.
@JavaClass("com.pureswift.swiftandroid.HostContext")
open class HostContext: JavaObject {}

extension JavaClass<HostContext> {

    @JavaStaticMethod
    public func getActivity() -> SwiftUIActivity?
}

/// `Activity.onCreate`, handed off from the generated `BridgeExport` entry
/// point (which can't reach this module — see the note at its declaration).
@_cdecl("swiftui_activityCreated")
func swiftui_activityCreated() {
    guard let activity = try! JavaClass<HostContext>().getActivity() else {
        SwiftUIActivity.logError("activityCreated: HostContext has no activity")
        return
    }
    SwiftUIActivity.log("\(activity).\(#function)")
    SwiftUIActivity.shared = activity

    // Point @AppStorage at a file in the app's private storage before any
    // view is built, so the first evaluation already reads saved values.
    // The path comes through the existing Context binding — no new bridge.
    if let directory = (activity as AndroidContent.Context).getFilesDir()?.getAbsolutePath() {
        AppStorageStore.backend = FileAppStorage(directory: directory)
    } else {
        SwiftUIActivity.log("no files directory; @AppStorage stays in memory")
    }

    // start app
    AndroidSwiftUIMain()
}

/// `Activity.onActivityResult`. The `Intent` stays in `HostContext`; only the
/// primitive codes cross the generated bridge.
@_cdecl("swiftui_activityResult")
func swiftui_activityResult(_ requestCode: Int32, _ resultCode: Int32) {
    SwiftUIActivity.log("\(#function) requestCode \(requestCode) resultCode \(resultCode)")
}

extension SwiftUIActivity {

    static var logTag: String { "SwiftUIActivity" }

    static let log = try! JavaClass<AndroidUtil.Log>()

    static func log(_ string: String) {
        _ = Self.log.d(Self.logTag, string)
    }

    static func logInfo(_ string: String) {
        _ = Self.log.i(Self.logTag, string)
    }

    static func logError(_ string: String) {
        _ = Self.log.e(Self.logTag, string)
    }

    func log(_ string: String) {
        Self.log(string)
    }

    func logError(_ string: String) {
        Self.logError(string)
    }
}
