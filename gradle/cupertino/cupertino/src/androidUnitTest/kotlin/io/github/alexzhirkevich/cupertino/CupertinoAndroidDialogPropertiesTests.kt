package io.github.alexzhirkevich.cupertino

import androidx.compose.runtime.AbstractApplier
import androidx.compose.runtime.Composition
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.window.PopupProperties
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Evaluate the Android actual helper, rather than the already-focusable desktop actual. */
class CupertinoAndroidDialogPropertiesTests {
    @Test
    fun modalPopupsOwnFocusWhilePreservingExplicitDismissPolicies() {
        val observed = mutableListOf<PopupProperties>()
        val recomposer = Recomposer(EmptyCoroutineContext)
        val composition = Composition(NoOpApplier(), recomposer)
        try {
            composition.setContent {
                observed += FullscreenPopupProperties(
                    dismissOnBackPress = true,
                    dismissOnClickOutside = true,
                    usePlatformDefaultWidth = true,
                )
                observed += FullscreenPopupProperties(
                    dismissOnBackPress = false,
                    dismissOnClickOutside = false,
                    usePlatformDefaultWidth = false,
                )
            }
            assertEquals(2, observed.size)
            observed.forEach { assertTrue(it.focusable, "Modal dialogs must own the Android window focus") }
            assertTrue(observed[0].dismissOnBackPress)
            assertTrue(observed[0].dismissOnClickOutside)
            assertTrue(observed[0].usePlatformDefaultWidth)
            assertFalse(observed[1].dismissOnBackPress)
            assertFalse(observed[1].dismissOnClickOutside)
            assertFalse(observed[1].usePlatformDefaultWidth)
        } finally {
            composition.dispose()
            recomposer.cancel()
        }
    }

    private class NoOpApplier : AbstractApplier<Unit>(Unit) {
        override fun insertBottomUp(index: Int, instance: Unit) = Unit
        override fun insertTopDown(index: Int, instance: Unit) = Unit
        override fun move(from: Int, to: Int, count: Int) = Unit
        override fun remove(index: Int, count: Int) = Unit
        override fun onClear() = Unit
    }
}
