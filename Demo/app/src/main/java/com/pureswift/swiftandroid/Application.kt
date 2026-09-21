package com.pureswift.swiftandroid

// A pure consumer: the lifecycle bridge lives in `SwiftUIApplication`
// (`:androidbridge`). Named in the manifest as `.Application`.
class Application : SwiftUIApplication() {
    override fun onCreate() {
        HardwareKeyStore.initialize(this)
        PhoneProtocolHost.initialize(this)
        super.onCreate()
    }
}
