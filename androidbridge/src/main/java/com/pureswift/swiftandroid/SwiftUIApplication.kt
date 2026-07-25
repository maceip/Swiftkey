package com.pureswift.swiftandroid

import com.pureswift.bridge.BridgeExport

/// Base `Application` for a SwiftUI-on-Android host: loads the Swift library
/// and drives the Swift side's process lifecycle through the generated
/// bridge. Name it (or a subclass) in the manifest instead of hand-writing
/// `external fun` — the JNI symbols are generated and typed.
open class SwiftUIApplication : android.app.Application() {

    init {
        NativeLibrary.shared()
    }

    override fun onCreate() {
        super.onCreate()
        HostContext.application = this
        BridgeExport.bridgeApplicationCreated()
    }

    override fun onTerminate() {
        super.onTerminate()
        BridgeExport.bridgeApplicationTerminated()
        HostContext.application = null
    }
}
