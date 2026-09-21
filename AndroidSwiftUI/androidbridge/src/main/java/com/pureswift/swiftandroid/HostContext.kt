package com.pureswift.swiftandroid

import android.app.Application
import android.content.Intent
import android.os.Bundle

/// Where the host parks the Java objects Swift needs to read.
///
/// The generated bridge carries only primitives, Strings and closures — a
/// wrapped Java type like `Activity` can't be an argument to it. So those
/// cross in the other, safe direction: Kotlin publishes them here and Swift
/// reads them through its classic `@JavaClass` name-lookup bindings, leaving
/// the generated lifecycle calls to carry nothing but primitives.
///
/// `savedState` and `activityResultData` are published for hosts that need
/// them; the Swift bridge itself currently only reads `activity`.
object HostContext {

    @JvmStatic
    var activity: SwiftUIActivity? = null

    @JvmStatic
    var application: Application? = null

    @JvmStatic
    var savedState: Bundle? = null

    @JvmStatic
    var activityResultData: Intent? = null
}
