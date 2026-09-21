@file:OptIn(ExperimentalCupertinoApi::class, InternalCupertinoApi::class)

package io.github.alexzhirkevich.cupertino

import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.alexzhirkevich.cupertino.theme.CupertinoTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click

/** Regression tests for the documented SwiftKey patches, outside upstream's source tree. */
class CupertinoPickerRegressionTests {
    @get:Rule val compose = createComposeRule()
    private fun awaitCondition(condition: () -> Boolean) {
        val deadline = System.nanoTime() + 5_000_000_000L
        compose.waitUntil(5000) {
            val ready = condition()
            check(ready || System.nanoTime() < deadline) { "Timed out waiting for picker state" }
            ready
        }
    }
    private val day = LocalDate.of(2026, 9, 20).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()

    @Test fun twelveHourInitialPmAndManualRoundtripPreserveFullDayHour() {
        val state = CupertinoTimePickerState(initialHour = 14, initialMinute = 37, is24Hour = false)
        compose.setContent { CupertinoTheme { CupertinoTimePicker(state) } }
        compose.runOnIdle {
            assertEquals(14, state.hour)
            assertEquals(37, state.minute)
            state.isManual = true
            assertEquals(14, state.hour, "Entering manual mode must preserve PM")
            state.manualHour = 23
            state.manualMinute = 58
            state.isManual = false
        }
        awaitCondition { state.hour == 23 && state.minute == 58 }
        compose.runOnIdle {
            state.isManual = true
            state.manualHour = 0
            state.manualMinute = 5
            state.isManual = false
        }
        awaitCondition { state.hour == 0 && state.minute == 5 }
    }

    @Test fun infiniteDateTimeWheelKeepsPmAfterMultipleHourCycles() {
        val state = CupertinoDateTimePickerState(day, 2026..2026, 14, 37, false)
        lateinit var scope: CoroutineScope
        compose.setContent {
            scope = rememberCoroutineScope()
            CupertinoTheme { CupertinoDateTimePicker(state = state, style = DatePickerStyle.Wheel()) }
        }
        compose.runOnIdle {
            assertEquals(14, state.selectedHour)
            scope.launch {
                state.stateData.hourState.scrollToItem(26)
                state.stateData.minuteState.scrollToItem(76)
            }
        }
        awaitCondition { state.stateData.hourState.selectedItemIndex == 26 && state.stateData.minuteState.selectedItemIndex == 76 }
        compose.runOnIdle {
            assertEquals(14, state.selectedHour, "Raw cyclic index must be normalized before applying PM")
            assertEquals(16, state.selectedMinute)
            assertEquals(day + 14 * 3_600_000L + 16 * 60_000L, state.selectedDateTimeMillis)
            scope.launch { state.stateData.hourState.scrollToItem(38) }
        }
        awaitCondition { state.stateData.hourState.selectedItemIndex == 38 }
        compose.runOnIdle { assertEquals(14, state.selectedHour) }
    }

    @Test fun animatedCyclicScrollRetainsItsInfiniteOffset() {
        val state = CupertinoPickerState(infinite = true, initiallySelectedItemIndex = 26)
        val initial = state.lazyListState.firstVisibleItemIndex
        lateinit var scope: CoroutineScope
        compose.setContent {
            scope = rememberCoroutineScope()
            LazyColumn(state = state.lazyListState, modifier = Modifier.height(160.dp)) {
                items(Int.MAX_VALUE) { Box(Modifier.size(30.dp)) }
            }
        }
        compose.runOnIdle { scope.launch { state.animateScrollToItem(38) } }
        awaitCondition { state.lazyListState.firstVisibleItemIndex == initial + 12 }
        compose.runOnIdle { assertEquals(initial + 12, state.lazyListState.firstVisibleItemIndex) }
    }

    @Test fun dateTimeManualAndProgrammaticSelectionUpdateEveryWheel() {
        val state = CupertinoDateTimePickerState(day, 2026..2026, 14, 37, false)
        compose.setContent { CupertinoTheme { CupertinoDateTimePicker(state = state, style = DatePickerStyle.Wheel()) } }
        compose.runOnIdle {
            state.isManual = true
            assertEquals(day + 14 * 3_600_000L + 37 * 60_000L, state.selectedDateTimeMillis)
            state.setSelection(day + 86_400_000L + 23 * 3_600_000L + 58 * 60_000L)
            state.isManual = false
        }
        awaitCondition { state.selectedDateTimeMillis == day + 86_400_000L + 23 * 3_600_000L + 58 * 60_000L }
        compose.runOnIdle { state.setSelection(day + 3_600_000L + 5 * 60_000L) }
        awaitCondition { state.selectedDateTimeMillis == day + 3_600_000L + 5 * 60_000L }
        compose.runOnIdle {
            assertEquals(1, state.selectedHour)
            assertEquals(5, state.selectedMinute)
        }
    }

    @Test fun manualDateTimeUsesMillisecondUnitsForHourAndMinute() {
        val state = CupertinoDateTimePickerState(day, 2026..2026, 14, 37, false)
        state.isManual = true
        state.setSelection(day + 23 * 3_600_000L + 58 * 60_000L)
        assertEquals(23, state.selectedHour)
        assertEquals(58, state.selectedMinute)
        assertEquals(day + 23 * 3_600_000L + 58 * 60_000L, state.selectedDateTimeMillis)
        state.setSelection(day + 12 * 3_600_000L + 1 * 60_000L)
        assertEquals(12, state.selectedHour)
        assertEquals(1, state.selectedMinute)
    }

    @Test fun dateSelectionAndManualRoundtripPreserveCanonicalDayAndRange() {
        val state = CupertinoDatePickerState(day, 2026..2026)
        state.setSelection(day + 86_400_000L + 12_345L)
        assertEquals(day + 86_400_000L, state.selectedDateMillis)
        state.isManual = true
        assertEquals(day + 86_400_000L, state.selectedDateMillis)
        state.setSelection(day + 2 * 86_400_000L + 12 * 3_600_000L)
        assertEquals(day + 2 * 86_400_000L, state.selectedDateMillis)
        assertFailsWith<IllegalArgumentException> { state.setSelection(0L) }
        assertEquals(day + 2 * 86_400_000L, state.selectedDateMillis)
        state.isManual = false
        assertEquals(day + 2 * 86_400_000L, state.selectedDateMillis)
    }

    @Test fun infinitePickerThreeLogicalKeysDoNotCollideAcrossVisibleCycles() {
        val state = CupertinoPickerState(infinite = true, initiallySelectedItemIndex = 1)
        compose.setContent {
            CupertinoTheme {
                CupertinoWheelPicker(state, listOf("First", "Second", "Third"), key = { it }) { CupertinoText(it) }
            }
        }
        compose.waitForIdle()
        assertEquals(1, state.currentSelectedItem(3))
    }

    @Test fun clickingInfiniteWheelItemUsesLogicalNotAbsoluteIndex() {
        val state = CupertinoPickerState(infinite = true, initiallySelectedItemIndex = 20)
        compose.setContent {
            CupertinoTheme {
                CupertinoWheelPicker(state, (0..99).toList()) { CupertinoText("Item $it") }
            }
        }
        compose.onNodeWithText("Item 21").performTouchInput { click() }
        awaitCondition { state.currentSelectedItem(100) == 21 && !state.isScrollInProgress }
    }

    @Test fun heightDetentUsesDensityWithoutMultiplyingByAvailableHeight() {
        assertEquals(240f, PresentationDetent.Height(120.dp).calculate(Density(2f), 1000f))
        assertEquals(100f, PresentationDetent.Height(120.dp).calculate(Density(2f), 100f))
        assertEquals(500f, PresentationDetent.Fraction(.5f).calculate(Density(2f), 1000f))
    }
}
