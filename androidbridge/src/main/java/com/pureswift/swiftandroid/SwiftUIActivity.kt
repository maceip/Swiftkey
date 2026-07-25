package com.pureswift.swiftandroid

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import com.pureswift.bridge.BridgeExport

/// Base `Activity` for a SwiftUI-on-Android host. Subclassing this is the
/// whole contract: no `external fun`, no JNI symbol to match by hand.
///
/// Extends `FragmentActivity` so both framework and AndroidX fragments can
/// be hosted.
open class SwiftUIActivity : FragmentActivity() {

    init {
        NativeLibrary.shared()
    }

    /// Runs after the activity is published to [HostContext] but before Swift
    /// evaluates the first tree. Override to register custom composables —
    /// the registry is read during that first render, so registering later
    /// is too late.
    open fun onRegisterComposables() {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        HostContext.activity = this
        HostContext.savedState = savedInstanceState
        onRegisterComposables()
        BridgeExport.bridgeActivityCreated()
        enableEdgeToEdge()
    }

    override fun onDestroy() {
        if (HostContext.activity === this) {
            HostContext.activity = null
        }
        super.onDestroy()
    }

    /// Swift installs the rendered tree here.
    fun setRootView(view: View) {
        setContentView(view)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        HostContext.activityResultData = data
        BridgeExport.bridgeActivityResult(requestCode, resultCode)
    }
}
