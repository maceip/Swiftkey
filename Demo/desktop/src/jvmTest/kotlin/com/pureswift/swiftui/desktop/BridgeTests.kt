package com.pureswift.swiftui.desktop

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.remember
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.pureswift.swiftui.JextractCallbackSink
import com.pureswift.swiftui.Render
import com.pureswift.swiftui.SwiftBridge
import com.pureswift.swiftui.TreeStore
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/// The end-to-end bridge test: native Swift evaluates the view tree, JNI
/// materializes it into Kotlin nodes, Compose renders it, a click dispatches
/// back into Swift, Swift re-evaluates, and the UI shows the new state.
/// Runs headless on the host JVM — no emulator, no window.
class BridgeTests {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun counterRoundTripAcrossTheBridge() {
        assertTrue("swiftui.library must point to the built Swift demo library", SwiftRuntime.load())

        compose.setContent {
            MaterialTheme {
                Surface {
                    val store = remember {
                        TreeStore().also {
                            SwiftBridge.sink = JextractCallbackSink()
                            registerDemoComposables()
                            SwiftRuntime().start(it)
                        }
                    }
                    store.root?.let { Render(it) }
                }
            }
        }

        // The live Swift root is the catalog; navigation also crosses the bridge.
        compose.onNodeWithText("Catalog").assertIsDisplayed()
        compose.onNodeWithText("Text").performClick()
        compose.onNodeWithText("Counter is 0").assertIsDisplayed()

        // Compose click → JNI → Swift @State write → re-evaluate → new tree
        compose.onNodeWithText("Increment").performClick()
        compose.onNodeWithText("Counter is 1").assertIsDisplayed()

        // and again, proving the callback registry survives re-registration
        compose.onNodeWithText("Increment").performClick()
        compose.onNodeWithText("Counter is 2").assertIsDisplayed()
    }
}
