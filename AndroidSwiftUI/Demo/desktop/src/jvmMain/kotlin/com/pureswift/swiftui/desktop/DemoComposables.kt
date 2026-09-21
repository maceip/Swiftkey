package com.pureswift.swiftui.desktop

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pureswift.swiftui.ComposableRegistry
import kotlin.math.roundToInt

/// Registers the desktop rig's custom composables into the interpreter's
/// registry — the desktop counterpart to the Android demo's `registerDemo
/// Composables`. Called once before the first render. It shows that the
/// composable registry is a cross-platform extension point: `DashedBorder` is
/// the identical pure-Compose function used on Android, and `RatingBar` is a
/// pure Compose-Multiplatform reimplementation of what the Android demo bridges
/// to `android.widget.RatingBar`.
fun registerDemoComposables() {

    // A pure Compose-Multiplatform star rating — no native widget. Tapping or
    // dragging across the stars reports a half-step rating back to Swift; the
    // `rating` prop drives the fill so two-way binding round-trips.
    ComposableRegistry.register("RatingBar") { props, _ ->
        val rating = props.float("rating") ?: 0f
        val max = props.int("max") ?: 5
        val onChanged = props.doubleAction("onRatingChanged")

        // Maps a horizontal position within the row to the nearest half-star.
        fun report(x: Float, width: Int) {
            if (width <= 0 || onChanged == null) return
            val fraction = (x / width).coerceIn(0f, 1f)
            val stepped = (fraction * max * 2).roundToInt() / 2.0
            onChanged.invoke(stepped.coerceIn(0.0, max.toDouble()))
        }

        Box(
            modifier = Modifier
                .pointerInput(max) { detectTapGestures { report(it.x, size.width) } }
                .pointerInput(max) {
                    detectDragGestures { change, _ -> report(change.position.x, size.width) }
                },
        ) {
            androidx.compose.foundation.layout.Row {
                for (index in 0 until max) {
                    val fill = (rating - index).coerceIn(0f, 1f)
                    Star(fill)
                }
            }
        }
    }

    // The same pure Compose function the Android demo registers: a dashed border
    // drawn around whatever SwiftUI child content lands in the slot.
    ComposableRegistry.register("DashedBorder") { props, children ->
        val color = props.color("color") ?: Color(0xFF6750A4.toInt())
        Box(
            modifier = Modifier
                .drawBehind {
                    drawRoundRect(
                        color = color,
                        style = Stroke(
                            width = 5f,
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(24f, 14f)),
                        ),
                        cornerRadius = CornerRadius(20f, 20f),
                    )
                }
                .padding(18.dp),
        ) {
            children()
        }
    }
}

/// One star, filled left-to-right by `fill` (0…1) so halves render exactly.
/// A clipped filled glyph is layered over an empty one — no icon dependency.
@Composable
private fun Star(fill: Float) {
    val style = TextStyle(fontSize = 34.sp, textAlign = TextAlign.Center)
    Box(modifier = Modifier.size(40.dp), contentAlignment = Alignment.Center) {
        Text("☆", style = style, color = Color(0xFFB0B0B0)) // ☆
        Text(
            "★", // ★
            style = style,
            color = Color(0xFFFFC107),
            modifier = Modifier.drawWithContent {
                clipRect(right = size.width * fill) { this@drawWithContent.drawContent() }
            },
        )
    }
}
