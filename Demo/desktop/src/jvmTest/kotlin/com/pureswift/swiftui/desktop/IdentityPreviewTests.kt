package com.pureswift.swiftui.desktop

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.pureswift.swiftui.JextractCallbackSink
import com.pureswift.swiftui.Render
import com.pureswift.swiftui.SwiftBridge
import com.pureswift.swiftui.TreeStore
import java.io.File
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Actual shared Swift presentation through JNI/Compose, using fixture bytes.
 * These tests prove layout/content only, never a real hardware identity. */
@OptIn(ExperimentalTestApi::class)
class IdentityPreviewTests {
    @get:Rule val compose = createComposeRule()

    @Test fun identityPhonePreviewPreservesOnlyNameAndAllPublicBytes() = verify(360, 1f, "identity-phone")

    @Test fun identityNarrowLargeTextRemainsScrollableAndUnclipped() = verify(320, 1.4f, "identity-large-text")

    private fun verify(width: Int, scale: Float, filename: String) {
        assertTrue("Swift identity preview library must load", SwiftRuntime.load())
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                MaterialTheme {
                    Box(Modifier.requiredSize(width.dp, 640.dp).testTag("identity.preview")) {
                        val store = remember {
                            TreeStore().also {
                                SwiftBridge.sink = JextractCallbackSink()
                                SwiftRuntime().startIdentityPreview(it)
                            }
                        }
                        store.root?.let { Render(it) }
                    }
                }
            }
        }
        val texts = compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Text))
            .fetchSemanticsNodes().flatMap { it.config[SemanticsProperties.Text].map { text -> text.text } }
        assertEquals(2, texts.size)
        assertEquals("SwiftKey", texts[0])
        val expected = (listOf(4) + (0..63)).joinToString("") { "%02x".format(it) }
        assertEquals(expected, texts[1].filterNot { it.isWhitespace() })
        val layout = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(texts[1]).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layout) }
        assertEquals(FontFamily.Monospace, layout.single().layoutInput.style.fontFamily)
        savePreview(filename)
        // Compose Desktop may keep the paragraph's available width larger than
        // the final intrinsic text box. Check actual glyph-line bounds instead
        // of didOverflowWidth, which treats that unused width as overflow.
        val textLayout = layout.single()
        for (line in 0 until textLayout.lineCount) {
            assertTrue("Public bytes must fit the measured text box", textLayout.getLineRight(line) <= textLayout.size.width + 1f)
            assertTrue("Public bytes must not clip at the leading edge", textLayout.getLineLeft(line) >= -1f)
            assertFalse("Public bytes must never be ellipsized", textLayout.isLineEllipsized(line))
        }
        assertFalse("Public bytes must retain every line", layout.single().didOverflowHeight)
        if (scale > 1f) {
            compose.onNodeWithText(texts[1]).performScrollTo()
            savePreview(filename + "-scrolled")
        }
    }

    private fun savePreview(name: String) {
        val directory = File(System.getProperty("swiftkey.previewDir", "/tmp/swiftkey-native-preview"))
        directory.mkdirs()
        val bitmap = compose.onNodeWithTag("identity.preview").captureToImage().asSkiaBitmap()
        val bytes = Image.makeFromBitmap(bitmap).encodeToData(EncodedImageFormat.PNG)!!.bytes
        File(directory, "$name.png").writeBytes(bytes)
    }
}
