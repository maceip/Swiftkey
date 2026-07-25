package com.pureswift.swiftandroid

import android.os.Handler
import android.os.Looper
import com.pureswift.bridge.BridgeHost
import com.pureswift.bridge.SwiftTask

/// The generated `BridgeHost`: replaces the hand-matched `Runnable`/
/// `SwiftObject` JNI pair. Posting through `Handler.post` (not a coroutine
/// dispatcher) keeps the JVM frame that resolves JNI classes as the app's
/// class loader — see the invariant documented at `AndroidSwiftUIApp.run`.
class AndroidBridgeHost : BridgeHost {

    private val handler = Handler(Looper.getMainLooper())

    override fun postToMain(task: SwiftTask) {
        handler.post { task.run() }
    }
}
