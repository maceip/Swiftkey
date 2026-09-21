# Public function signatures (source-scanned, including public members)

## `CupertinoActivityIndicator` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoActivityIndicator.kt:62

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoActivityIndicator(
    modifier: Modifier = Modifier,
    size : Dp = CupertinoActivityIndicatorDefaults.MinSize,
    color: Color = CupertinoColors.Gray,
    count: Int = CupertinoActivityIndicatorDefaults.PathCount,
    innerRadius : Float = 1/3f,
    strokeWidth : Dp = Dp.Unspecified,
    animationSpec: InfiniteRepeatableSpec<Float> = infiniteRepeatable(
        animation = tween(
            durationMillis = CupertinoActivityIndicatorDefaults.DurationMillis,
            easing = LinearEasing,
        ),
        repeatMode = RepeatMode.Restart,
    ),
    minAlpha: Float = CupertinoActivityIndicatorDefaults.MinAlpha
)
```

## `CupertinoActivityIndicator` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoActivityIndicator.kt:165

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoActivityIndicator(
    modifier: Modifier = Modifier,
    progress : Float = 1f,
    size : Dp = CupertinoActivityIndicatorDefaults.MinSize,
    color: Color = CupertinoColors.Gray,
    count: Int = CupertinoActivityIndicatorDefaults.PathCount,
    innerRadius : Float = 1/3f,
    strokeWidth : Dp = Dp.Unspecified,
    animationSpec: InfiniteRepeatableSpec<Float> = infiniteRepeatable(
        animation = tween(
            durationMillis = CupertinoActivityIndicatorDefaults.DurationMillis,
            easing = LinearEasing,
        ),
        repeatMode = RepeatMode.Restart,
    ),
    minAlpha: Float = CupertinoActivityIndicatorDefaults.MinAlpha
)
```

## `CupertinoBottomAppBar` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomAppBar.kt:39

```kotlin
@ExperimentalCupertinoApi
@Composable
fun CupertinoBottomAppBar(
    modifier: Modifier = Modifier,
    isTranslucent : Boolean = true,
    isTransparent : Boolean = false,
    containerColor: Color = CupertinoNavigationBarDefaults.containerColor,
    contentColor: Color = CupertinoTheme.colorScheme.accent,
    contentPadding: PaddingValues = CupertinoSectionDefaults.PaddingValues,
    windowInsets: WindowInsets = WindowInsets.navigationBars,
    content: @Composable RowScope.() -> Unit,
)
```

## `CupertinoBottomSheetContent` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:70

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoBottomSheetContent(
    modifier: Modifier = Modifier,
    containerColor: Color = LocalContainerColor.current.takeOrElse {
        CupertinoBottomSheetDefaults.containerColor
    },
    contentColor: Color = LocalContentColor.current.takeOrElse {
        CupertinoBottomSheetDefaults.contentColor
    },
    appBarsAlpha : Float = LocalAppBarsBlurAlpha.current,
    appBarsBlurRadius : Dp = LocalAppBarsBlurRadius.current,
    hasNavigationTitle : Boolean = false,
    topBar : @Composable () -> Unit = {},
    bottomBar : @Composable () -> Unit = {},
    content : @Composable (PaddingValues) -> Unit
)
```

## `CupertinoBottomSheetDefaults.DragHandle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:132

```kotlin
@Composable
fun DragHandle(
        modifier: Modifier = Modifier,
        width: Dp = DragHandleWidth,
        height: Dp = DragHandleHeight,
        shape: Shape = CircleShape,
        color: Color = CupertinoTheme.colorScheme.systemFill
    )
```

## `PresentationDetent.calculate` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:184

```kotlin

fun calculate(density: Density, height: Float): Float
```

## `PresentationDetent.Large.calculate` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:193

```kotlin
@Immutable
@Serializable
override fun calculate(density: Density, height: Float): Float
```

## `PresentationDetent.Height.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:214

```kotlin

override fun hashCode(): Int
```

## `PresentationDetent.Height.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:218

```kotlin

override fun equals(other: Any?): Boolean
```

## `PresentationDetent.Height.calculate` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:222

```kotlin

override fun calculate(density: Density, height: Float): Float
```

## `PresentationDetent.Height.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:226

```kotlin

override fun toString(): String
```

## `PresentationDetent.Fraction.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:246

```kotlin

override fun hashCode(): Int
```

## `PresentationDetent.Fraction.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:250

```kotlin

override fun equals(other: Any?): Boolean
```

## `PresentationDetent.Fraction.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:254

```kotlin

override fun toString(): String
```

## `PresentationDetent.Fraction.calculate` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:258

```kotlin

override fun calculate(density: Density, height: Float): Float
```

## `CupertinoSheetValue.PartiallyExpanded.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:282

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoSheetValue.PartiallyExpanded.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:286

```kotlin

override fun hashCode(): Int
```

## `CupertinoSheetValue.PartiallyExpanded.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:290

```kotlin

override fun toString(): String
```

## `PresentationStyle.Modal.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:337

```kotlin

override fun equals(other: Any?): Boolean
```

## `PresentationStyle.Modal.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:351

```kotlin

override fun hashCode(): Int
```

## `PresentationStyle.Modal.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:359

```kotlin

override fun toString(): String
```

## `CupertinoSheetState.requireOffset` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:431

```kotlin

fun requireOffset(): Float
```

## `CupertinoSheetState.expand` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:449

```kotlin

suspend fun expand()
```

## `CupertinoSheetState.partialExpand` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:459

```kotlin

suspend fun partialExpand(detent : PresentationDetent)
```

## `CupertinoSheetState.show` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:475

```kotlin

suspend fun show()
```

## `CupertinoSheetState.hide` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:491

```kotlin

suspend fun hide()
```

## `CupertinoSheetState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:553

```kotlin

fun Saver(
            presentationStyle: PresentationStyle = PresentationStyle.Modal(),
            confirmValueChange: (CupertinoSheetValue) -> Boolean,
        )
```

## `rememberCupertinoSheetState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheet.kt:569

```kotlin
@Composable
fun rememberCupertinoSheetState(
    initialValue: CupertinoSheetValue = CupertinoSheetValue.Hidden,
    presentationStyle: PresentationStyle = PresentationStyle.Modal(),
    confirmValueChange: (CupertinoSheetValue) -> Boolean = { true },
): CupertinoSheetState
```

## `CupertinoBottomSheetScaffold` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheetScaffold.kt:105

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoBottomSheetScaffold(
    sheetContent: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    windowInsets: WindowInsets = CupertinoScaffoldDefaults.contentWindowInsets,
    scaffoldState: CupertinoBottomSheetScaffoldState = rememberCupertinoBottomSheetScaffoldState(),
    colors: CupertinoBottomSheetScaffoldColors = CupertinoBottomSheetScaffoldDefaults.colors(),
    sheetShape: Shape = CupertinoBottomSheetDefaults.shape,
    sheetShadowElevation: Dp = CupertinoBottomSheetDefaults.ShadowElevation,
    sheetDragHandle: @Composable (() -> Unit)? = if (scaffoldState.bottomSheetState.hasPartiallyExpandedState)
        null else {
        { CupertinoBottomSheetDefaults.DragHandle() }
    },
    sheetSwipeEnabled: Boolean = true,
    topBar: @Composable (() -> Unit)? = null,
    bottomBar: @Composable (() -> Unit)? = null,
    appBarsBlurAlpha: Float = CupertinoScaffoldDefaults.AppBarsBlurAlpha,
    appBarsBlurRadius: Dp = CupertinoScaffoldDefaults.AppBarsBlurRadius,
    hasNavigationTitle: Boolean = false,
    content: @Composable (PaddingValues) -> Unit
)
```

## `rememberCupertinoBottomSheetScaffoldState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheetScaffold.kt:195

```kotlin
@Composable
fun rememberCupertinoBottomSheetScaffoldState(
    bottomSheetState: CupertinoSheetState = rememberCupertinoSheetState(),
): CupertinoBottomSheetScaffoldState
```

## `CupertinoBottomSheetScaffoldDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoBottomSheetScaffold.kt:219

```kotlin
@Composable
fun colors(
        sheetContainerColor: Color = CupertinoBottomSheetDefaults.containerColor,
        sheetContentColor: Color = CupertinoBottomSheetDefaults.contentColor,
        containerColor: Color = CupertinoTheme.colorScheme.systemBackground,
        contentColor: Color = CupertinoTheme.colorScheme.label,
        scrimColor: Color = CupertinoColors.DefaultAlpha,
        scaledScaffoldBackgroundColor: Color = CupertinoColors.Black
    ): CupertinoBottomSheetScaffoldColors
```

## `CupertinoButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:88

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    size: CupertinoButtonSize = CupertinoButtonSize.Regular,
    colors: CupertinoButtonColors = filledButtonColors(),
    border: BorderStroke? = null,
    shape: Shape = size.shape(CupertinoTheme.shapes),
    contentPadding: PaddingValues = size.contentPadding,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable RowScope.() -> Unit
)
```

## `CupertinoIconButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:145

```kotlin
@ExperimentalCupertinoApi
@Composable
fun CupertinoIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: CupertinoButtonColors = plainButtonColors(),
    border: BorderStroke? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable () -> Unit
)
```

## `CupertinoButtonColors.containerColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:194

```kotlin
@Immutable
@Composable
fun containerColor(enabled: Boolean): State<Color>
```

## `CupertinoButtonColors.contentColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:204

```kotlin
@Composable
fun contentColor(enabled: Boolean): State<Color>
```

## `CupertinoButtonColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:208

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoButtonColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:220

```kotlin

override fun hashCode(): Int
```

## `CupertinoButtonDefaults.grayButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:238

```kotlin
@Composable
@ReadOnlyComposable
fun grayButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = CupertinoColors.DefaultAlpha
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.plainButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:257

```kotlin
@Composable
@ReadOnlyComposable
fun plainButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = Color.Transparent,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = Color.Transparent,
        indicationColor: Color = Color.Transparent
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.filledButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:277

```kotlin
@Composable
@ReadOnlyComposable
fun filledButtonColors(
        contentColor: Color = Color.White,
        containerColor: Color = CupertinoTheme.colorScheme.accent,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = contentColor.copy(alpha = .2f)
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.tintedButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:296

```kotlin
@Composable
@ReadOnlyComposable
fun tintedButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = contentColor.copy(alpha = CupertinoButtonTokens.BorderedButtonAlpha),
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = contentColor.copy(alpha = .15f)
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.borderedProminentButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:322

```kotlin
@Composable
@ReadOnlyComposable
@Deprecated(
fun borderedProminentButtonColors(
        contentColor: Color = Color.White,
        containerColor: Color = CupertinoTheme.colorScheme.accent,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = contentColor.copy(alpha = .2f)
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.borderedButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:348

```kotlin
@Deprecated(
@Composable
@ReadOnlyComposable
fun borderedButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = contentColor.copy(alpha = CupertinoButtonTokens.BorderedButtonAlpha),
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = contentColor.copy(alpha = .15f)
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.borderlessButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:374

```kotlin
@Deprecated(
@Composable
@ReadOnlyComposable
fun borderlessButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = Color.Transparent,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = Color.Transparent,
        indicationColor: Color = Color.Transparent
    ): CupertinoButtonColors
```

## `CupertinoButtonDefaults.borderedGrayButtonColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoButton.kt:400

```kotlin
@Deprecated(
@Composable
@ReadOnlyComposable
fun borderedGrayButtonColors(
        contentColor: Color = CupertinoTheme.colorScheme.accent,
        containerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        disabledContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledContainerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicationColor: Color = CupertinoColors.DefaultAlpha
    ): CupertinoButtonColors
```

## `CupertinoCheckBox` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:36

```kotlin
@Composable
fun CupertinoCheckBox(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: CupertinoCheckboxColors = CupertinoCheckboxDefaults.colors(),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() }
)
```

## `CupertinoTriStateCheckBox` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:59

```kotlin
@Composable
fun CupertinoTriStateCheckBox(
    state: ToggleableState,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: CupertinoCheckboxColors = CupertinoCheckboxDefaults.colors(),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() }
)
```

## `CupertinoCheckboxDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:97

```kotlin
@Composable
fun colors(
        checkedCheckmarkColor: Color = CupertinoTheme.colorScheme.systemBackground,
        uncheckedCheckmarkColor: Color = Color.Transparent,
        checkedBoxColor: Color = CupertinoTheme.colorScheme.accent,
        uncheckedBoxColor: Color = Color.Transparent,
        disabledCheckedBoxColor: Color = CupertinoTheme.colorScheme.secondarySystemBackground,
        disabledUncheckedBoxColor: Color = uncheckedBoxColor,
        disabledIndeterminateBoxColor: Color = disabledCheckedBoxColor,
        checkedBorderColor: Color = Color.Transparent,
        uncheckedBorderColor: Color = CupertinoTheme.colorScheme.systemFill,
        disabledBorderColor: Color = checkedBorderColor,
        disabledUncheckedBorderColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        disabledIndeterminateBorderColor: Color = disabledBorderColor
    ) : CupertinoCheckboxColors
```

## `CupertinoCheckboxColors.copy` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:169

```kotlin
@Immutable
fun copy(
        checkedCheckmarkColor: Color = this.checkedCheckmarkColor,
        uncheckedCheckmarkColor: Color = this.uncheckedCheckmarkColor,
        checkedBoxColor: Color = this.checkedBoxColor,
        uncheckedBoxColor: Color = this.uncheckedBoxColor,
        disabledCheckedBoxColor: Color = this.disabledCheckedBoxColor,
        disabledUncheckedBoxColor: Color = this.disabledUncheckedBoxColor,
        disabledIndeterminateBoxColor: Color = this.disabledIndeterminateBoxColor,
        checkedBorderColor: Color = this.checkedBorderColor,
        uncheckedBorderColor: Color = this.uncheckedBorderColor,
        disabledBorderColor: Color = this.disabledBorderColor,
        disabledUncheckedBorderColor: Color = this.disabledUncheckedBorderColor,
        disabledIndeterminateBorderColor: Color = this.disabledIndeterminateBorderColor
    )
```

## `CupertinoCheckboxColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:265

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoCheckboxColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCheckbox.kt:283

```kotlin

override fun hashCode(): Int
```

## `rememberCupertinoDatePickerState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:127

```kotlin
@Composable
@ExperimentalCupertinoApi
fun rememberCupertinoDatePickerState(
    initialSelectedDateMillis: Long = CupertinoDatePickerDefaults.today.utcTimeMillis,
    yearRange: IntRange = CupertinoDatePickerDefaults.YearRangeLarge,
): CupertinoDatePickerState
```

## `CupertinoDatePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:145

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoDatePicker(
    state: CupertinoDatePickerState,
    modifier: Modifier = Modifier,
    style: DatePickerStyle = DatePickerStyle.Wheel(),
    containerColor: Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    },
)
```

## `CupertinoDatePickerState.setSelection` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:245

```kotlin

fun setSelection(@Suppress("AutoBoxing") dateMillis: Long)
```

## `CupertinoDatePickerState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:265

```kotlin

fun Saver(): Saver<CupertinoDatePickerState, *>
```

## `CupertinoDatePickerColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:385

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoDatePickerColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:406

```kotlin

override fun hashCode(): Int
```

## `calculatePagerHeight` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePicker.kt:1426

```kotlin
@Stable
fun calculatePagerHeight(
    verticalSpacing: Dp,
    maxDaySize: Dp,
)
```

## `rememberCupertinoDateTimePickerState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:71

```kotlin
@Composable
@ExperimentalCupertinoApi
fun rememberCupertinoDateTimePickerState(
    initialSelectedDateMillis: Long = CupertinoDatePickerDefaults.today.utcTimeMillis,
    initialHour: Int = 0,
    initialMinute: Int = 0,
    is24Hour: Boolean = PlatformDateFormat.is24HourFormat(defaultLocale()),
    yearRange: IntRange = CupertinoDatePickerDefaults.YearRangeSmall,
): CupertinoDateTimePickerState
```

## `CupertinoDateTimePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:96

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoDateTimePicker(
    state: CupertinoDateTimePickerState,
    style: DatePickerStyle = DatePickerStyle.Wheel(),
    containerColor : Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    },
    modifier: Modifier = Modifier
)
```

## `DatePickerStyle.Pager.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:134

```kotlin
@Immutable
override fun equals(other: Any?): Boolean
```

## `DatePickerStyle.Pager.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:149

```kotlin

override fun hashCode(): Int
```

## `DatePickerStyle.Wheel.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:171

```kotlin
@Immutable
override fun equals(other: Any?): Boolean
```

## `DatePickerStyle.Wheel.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:183

```kotlin

override fun hashCode(): Int
```

## `DatePickerStyle.Companion.Pager` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:192

```kotlin
@Composable
fun Pager(
            textStyles: CupertinoDatePickerTextStyles = CupertinoDatePickerDefaults.pagerTextStyles(),
            colors: CupertinoDatePickerColors = CupertinoDatePickerDefaults.pagerColors(),
            rowSpacing : Dp = 6.dp,
            rowMaxHeight : Dp = CupertinoButtonTokens.IconButtonSize,
            userScrollEnabled : Boolean = true
        ): Pager
```

## `CupertinoDateTimePickerState.setSelection` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:720

```kotlin

fun setSelection(@Suppress("AutoBoxing") dateMillis: Long)
```

## `CupertinoDateTimePickerState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:733

```kotlin

fun Saver(
            is24Hour : Boolean
        ): Saver<CupertinoDateTimePickerState, *>
```

## `CupertinoDatePickerDefaults.pagerTextStyles` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:799

```kotlin
@Composable
fun pagerTextStyles(
        headline : TextStyle = CupertinoTheme.typography.headline,
        day : TextStyle = CupertinoTheme.typography.title3,
        selectedDay : TextStyle = day.copy(fontWeight = FontWeight.Bold),
        weekday : TextStyle = CupertinoTheme.typography.footnote
            .copy(fontWeight = FontWeight.SemiBold),
        monthWheel : TextStyle = CupertinoPickerDefaults.textStyle
    ) : CupertinoDatePickerTextStyles
```

## `CupertinoDatePickerDefaults.pagerColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePicker.kt:815

```kotlin
@Composable
fun pagerColors(
        chevronsColor : Color = CupertinoTheme.colorScheme.accent,
        headlineContentColor: Color = CupertinoTheme.colorScheme.label,
        weekdayContentColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        todayContentColor: Color = CupertinoTheme.colorScheme.accent,
        dayContentColor: Color = CupertinoTheme.colorScheme.label,
        disabledDayContentColor: Color = dayContentColor.copy(alpha = 0.38f),
        disabledSelectedDayContentColor: Color = todayContentColor.copy(alpha = 0.38f),
        selectedDayContentColor: Color = todayContentColor,
        selectedDayContainerColor: Color = todayContentColor.copy(alpha = CupertinoButtonTokens.BorderedButtonAlpha),
        disabledSelectedDayContainerColor: Color = selectedDayContainerColor.copy(alpha = 0.38f),
        dayInSelectionRangeContentColor: Color = CupertinoTheme.colorScheme.label,
        dayInSelectionRangeContainerColor: Color = CupertinoTheme.colorScheme.label
    ) : CupertinoDatePickerColors
```

## `AlertDialogActionsScope.action` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:150

```kotlin

fun action(
        onClick : () -> Unit,
        style : AlertActionStyle = AlertActionStyle.Default,
        enabled : Boolean = true,
        title : @Composable () -> Unit
    )
```

## `AlertDialogActionsScope.default` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:161

```kotlin

fun AlertDialogActionsScope.default(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : @Composable () -> Unit
)
```

## `AlertDialogActionsScope.destructive` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:175

```kotlin

fun AlertDialogActionsScope.destructive(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : @Composable () -> Unit
)
```

## `AlertDialogActionsScope.cancel` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:189

```kotlin

fun AlertDialogActionsScope.cancel(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : @Composable () -> Unit
)
```

## `CupertinoAlertDialog` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:213

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoAlertDialog(
    onDismissRequest: () -> Unit,
    title: @Composable () -> Unit,
    message: (@Composable () -> Unit)? = null,
    containerColor: Color = CupertinoDialogsDefaults.ContainerColor,
    shape: Shape = CupertinoDialogsDefaults.Shape,
    shadowElevation : Dp = CupertinoDialogsTokens.AlertDialogElevation,
    properties: DialogProperties = DialogProperties(),
    buttonsOrientation: Orientation = CupertinoDialogsDefaults.ButtonOrientation,
    buttons: AlertDialogActionsScope.() -> Unit
)
```

## `CupertinoActionSheet` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.kt:320

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoActionSheet(
    visible : Boolean,
    onDismissRequest : () -> Unit,
    title : (@Composable () -> Unit)? = null,
    message : (@Composable () -> Unit)? = null,
    containerColor : Color = CupertinoDialogsDefaults.ContainerColor,
    secondaryContainerColor : Color = CupertinoTheme.colorScheme.tertiarySystemBackground,
    properties: DialogProperties = DialogProperties(),
    content  : (@Composable () -> Unit) ?= null,
    buttons : AlertDialogActionsScope.() -> Unit,
)
```

## `CupertinoDropdownMenu` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:110

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    offset: DpOffset = DpOffset(0.dp, 0.dp),
    paddingValues: PaddingValues = CupertinoDropdownMenuDefaults.PaddingValues,
    containerColor: Color = CupertinoDropdownMenuDefaults.ContainerColor,
    width: Dp = CupertinoDropdownMenuDefaults.DefaultWidth,
    elevation: Dp = CupertinoDropdownMenuDefaults.Elevation,
    scrollState: ScrollState = rememberScrollState(),
    properties: PopupProperties = PopupProperties(focusable = true),
    content: @Composable CupertinoMenuScope.() -> Unit
)
```

## `CupertinoMenuScope.MenuItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:176

```kotlin
@Composable
fun CupertinoMenuScope.MenuItem(
    modifier: Modifier = Modifier,
    minHeight: Dp = MinItemHeight,
    content: @Composable (padding: PaddingValues) -> Unit
)
```

## `CupertinoMenuScope.MenuSection` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:206

```kotlin
@Composable
inline fun CupertinoMenuScope.MenuSection(
    noinline title: (@Composable () -> Unit)? = null,
    content: @Composable CupertinoMenuScope.() -> Unit
)
```

## `CupertinoMenuScope.MenuTitle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:221

```kotlin
@Composable
fun CupertinoMenuScope.MenuTitle(
    modifier: Modifier = Modifier,
    title: @Composable () -> Unit
)
```

## `CupertinoMenuScope.MenuAction` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:259

```kotlin
@Composable
fun CupertinoMenuScope.MenuAction(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onClickLabel: String? = null,
    enabled: Boolean = true,
    contentColor: Color = CupertinoDropdownMenuDefaults.ContentColor,
    icon: (@Composable () -> Unit) = {},
    caption: @Composable () -> Unit = {},
    title: @Composable () -> Unit,
)
```

## `CupertinoMenuScope.MenuPickerAction` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:301

```kotlin
@Composable
fun CupertinoMenuScope.MenuPickerAction(
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onClickLabel: String? = null,
    enabled: Boolean = true,
    contentColor: Color = CupertinoDropdownMenuDefaults.ContentColor,
    selectionIcon: (@Composable () -> Unit) = { CupertinoDropdownMenuDefaults.PickerLeadingIcon() },
    icon: (@Composable () -> Unit) = {},
    caption: @Composable () -> Unit = {},
    title: @Composable () -> Unit,
)
```

## `CupertinoMenuScope.MenuDivider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:362

```kotlin
@Composable
fun CupertinoMenuScope.MenuDivider(
    modifier: Modifier = Modifier,
    color: Color? = null,
    height: Dp = DividerHeight
)
```

## `CupertinoDropdownMenuDefaults.PickerLeadingIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDropdownMenu.kt:474

```kotlin
@Composable
fun PickerLeadingIcon()
```

## `CupertinoIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoIcon.kt:63

```kotlin
@Composable
fun CupertinoIcon(
    imageVector: ImageVector,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current
)
```

## `CupertinoIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoIcon.kt:96

```kotlin
@Composable
fun CupertinoIcon(
    bitmap: ImageBitmap,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current
)
```

## `CupertinoIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoIcon.kt:130

```kotlin
@Composable
fun CupertinoIcon(
    painter: Painter,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current
)
```

## `rememberCupertinoIndication` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoIndication.kt:41

```kotlin
@Composable
@ExperimentalCupertinoApi
fun rememberCupertinoIndication(
    color: Color = CupertinoIndication.DefaultColor
): Indication
```

## `CupertinoNavigateBackButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigateBackButton.kt:44

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoNavigateBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    size: CupertinoButtonSize = CupertinoButtonSize.Regular,
    shape: Shape = size.shape(CupertinoTheme.shapes),
    colors: CupertinoButtonColors = plainButtonColors(
    ),
    border: BorderStroke? = null,
    contentPadding: PaddingValues = PaddingValues(8.dp, 4.dp),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    icon: ImageVector = if (LocalLayoutDirection.current == LayoutDirection.Ltr)
        CupertinoIcons.Default.ChevronBackward else CupertinoIcons.Default.ChevronForward,
    title: @Composable RowScope.() -> Unit
)
```

## `cupertinoTranslucentBottomBarColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:76

```kotlin
@Composable
@ExperimentalCupertinoApi
fun cupertinoTranslucentBottomBarColor(
    color: Color,
    isTranslucent: Boolean,
    isTransparent: Boolean,
): Color
```

## `CupertinoNavigationBar` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:129

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoNavigationBar(
    modifier: Modifier = Modifier,
    containerColor: Color = CupertinoNavigationBarDefaults.containerColor,
    windowInsets: WindowInsets = WindowInsets.navigationBars,
    isTransparent: Boolean = false,
    isTranslucent: Boolean = LocalAppBarsState.current != null,
    divider: @Composable () -> Unit = {
        CupertinoNavigationBarDefaults.divider()
    },
    content: @Composable RowScope.() -> Unit
)
```

## `RowScope.CupertinoNavigationBarItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:185

```kotlin
@Composable
@ExperimentalCupertinoApi
fun RowScope.CupertinoNavigationBarItem(
    selected: Boolean,
    onClick: () -> Unit,
    icon: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: @Composable (() -> Unit)? = null,
    alwaysShowLabel: Boolean = true,
    pressIndicationEnabled: Boolean = false,
    colors: CupertinoNavigationBarItemColors = CupertinoNavigationBarDefaults.itemColors(),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() }
)
```

## `CupertinoNavigationBarItemColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:285

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoNavigationBarItemColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:297

```kotlin

override fun hashCode(): Int
```

## `CupertinoNavigationBarDefaults.itemColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:331

```kotlin
@Composable
@ReadOnlyComposable
fun itemColors(
        selectedIconColor: Color = CupertinoTheme.colorScheme.accent,
        selectedTextColor: Color = CupertinoTheme.colorScheme.accent,
        unselectedIconColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unselectedTextColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        disabledIconColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        disabledTextColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
    )
```

## `CupertinoNavigationBarDefaults.divider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoNavigationBar.kt:348

```kotlin
@Composable
fun divider()
```

## `CupertinoPickerState.currentSelectedItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:134

```kotlin

fun currentSelectedItem(itemsCount : Int) : Int
```

## `CupertinoPickerState.selectedItemState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:143

```kotlin

fun selectedItemState(itemsCount : Int) : State<Int>
```

## `CupertinoPickerState.selectedItemIndex` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:153

```kotlin
@Composable
fun selectedItemIndex(itemsCount : Int): Int
```

## `CupertinoPickerState.dispatchRawDelta` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:168

```kotlin

override fun dispatchRawDelta(delta: Float): Float
```

## `CupertinoPickerState.scroll` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:172

```kotlin

override suspend fun scroll(
        scrollPriority: MutatePriority,
        block: suspend ScrollScope.() -> Unit
    )
```

## `CupertinoPickerState.scrollToItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:205

```kotlin

suspend fun scrollToItem(index: Int)
```

## `CupertinoPickerState.animateScrollToItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:212

```kotlin

suspend fun animateScrollToItem(index: Int)
```

## `CupertinoPickerState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:216

```kotlin

fun Saver(): Saver<CupertinoPickerState, *>
```

## `rememberCupertinoPickerState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:230

```kotlin
@Composable
@ExperimentalCupertinoApi
fun rememberCupertinoPickerState(
    infinite: Boolean = true,
    initiallySelectedItemIndex: Int = 0
) : CupertinoPickerState
```

## `<T : Any> CupertinoWheelPicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:263

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
@ExperimentalCupertinoApi
fun <T : Any> CupertinoWheelPicker(
    state: CupertinoPickerState,
    items: List<T>,
    height: Dp = CupertinoPickerDefaults.Height,
    modifier: Modifier = Modifier,
    indicator: CupertinoPickerIndicator = CupertinoPickerDefaults.indicator(),
    containerColor: Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    },
    textStyle: TextStyle = CupertinoPickerDefaults.textStyle,
    key: ((T) -> Any)? = null,
    withRotation: Boolean = false,
    rotationTransformOrigin: TransformOrigin = TransformOrigin.Center,
    enabled : Boolean = true,
    horizontalAlignment: Alignment.Horizontal = Alignment.CenterHorizontally,
    content: @Composable (T) -> Unit
)
```

## `Modifier.cupertinoPickerIndicator` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:429

```kotlin
@ExperimentalCupertinoApi
fun Modifier.cupertinoPickerIndicator(
    state : CupertinoPickerState,
    indicator : CupertinoPickerIndicator
)
```

## `CupertinoPickerDefaults.indicatorOld` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:454

```kotlin
@Composable
fun indicatorOld(
        color : Color = CupertinoTheme.colorScheme.separator,
    ) : DrawScope.(itemHeight: Float) -> Unit
```

## `CupertinoPickerDefaults.indicator` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPicker.kt:476

```kotlin
@Composable
fun indicator(
        color : Color = CupertinoPickerTokens.IndicatorColor,
        shape: Shape = CupertinoPickerTokens.IndicatorShape,
        paddingValues: PaddingValues = CupertinoPickerTokens.IndicatorPaddingValues
    ) : CupertinoPickerIndicator
```

## `CupertinoScaffold` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoScaffold.kt:86

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoScaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    snackbarHost: @Composable () -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    floatingActionButtonPosition: FabPosition = FabPosition.End,
    containerColor: Color = CupertinoScaffoldDefaults.containerColor,
    contentColor: Color = CupertinoScaffoldDefaults.contentColor,
    contentWindowInsets: WindowInsets = CupertinoScaffoldDefaults.contentWindowInsets,
    appBarsBlurAlpha: Float = CupertinoScaffoldDefaults.AppBarsBlurAlpha,
    appBarsBlurRadius: Dp = CupertinoScaffoldDefaults.AppBarsBlurRadius,
    hasNavigationTitle: Boolean = false,
    content: @Composable (PaddingValues) -> Unit
)
```

## `FabPosition.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoScaffold.kt:438

```kotlin

override fun toString(): String
```

## `rememberCupertinoSearchTextFieldState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSearchTextField.kt:100

```kotlin
@Composable
fun rememberCupertinoSearchTextFieldState(
    initiallyExpanded: Boolean = true,
    scrollableState: ScrollableState? = null,
    collapse : (CupertinoSearchTextFieldState) -> Boolean = { !it.isFocused },
    blockScrollWhenFocusedAndEmpty : Boolean = true,
) : CupertinoSearchTextFieldState
```

## `CupertinoSearchTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSearchTextField.kt:161

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSearchTextField(
    value: String,
    onValueChange: (String) -> Unit,
    state: CupertinoSearchTextFieldState = rememberCupertinoSearchTextFieldState(),
    colors: CupertinoTextFieldColors = CupertinoSearchTextFieldDefaults.colors(),
    modifier: Modifier = Modifier,
    paddingValues: PaddingValues = CupertinoSearchTextFieldDefaults.PaddingValues,
    shape: Shape = CupertinoSearchTextFieldDefaults.shape,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = LocalTextStyle.current,
    keyboardOptions: KeyboardOptions = remember {
        KeyboardOptions(imeAction = ImeAction.Search)
    },
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    placeholder: @Composable () -> Unit = {
        CupertinoText("Search")
    },
    cancelButton: @Composable() (() -> Unit)? = {
        CupertinoSearchTextFieldDefaults
            .cancelButton(
                onValueChange = onValueChange,
                interactionSource = interactionSource
            )
    },
    leadingIcon: @Composable () -> Unit = {
        CupertinoSearchTextFieldDefaults.leadingIcon()
    },
    trailingIcon: @Composable () -> Unit = {},
)
```

## `CupertinoSearchTextFieldDefaults.leadingIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSearchTextField.kt:358

```kotlin
@Composable
fun leadingIcon(
        imageVector: ImageVector = CupertinoIcons.Outlined.MagnifyingGlass,
        rotateWithLayoutDirection: Boolean = true,
    )
```

## `CupertinoSearchTextFieldDefaults.cancelButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSearchTextField.kt:382

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@Composable
fun cancelButton(
        onValueChange: (String) -> Unit,
        colors: CupertinoButtonColors = plainButtonColors(),
        interactionSource: MutableInteractionSource,
        content: @Composable RowScope.() -> Unit = { CupertinoText("Cancel") },
    )
```

## `CupertinoSearchTextFieldDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSearchTextField.kt:406

```kotlin
@Composable
@ReadOnlyComposable
fun colors(
        focusedTextColor: Color = CupertinoTheme.colorScheme.label,
        unfocusedTextColor: Color = CupertinoTheme.colorScheme.label,
        disabledTextColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        errorTextColor: Color = CupertinoColors.systemRed,
        focusedContainerColor: Color = if (isDark())
            CupertinoTheme.colorScheme.tertiarySystemFill
        else CupertinoTheme.colorScheme.quaternarySystemFill,
        unfocusedContainerColor: Color = focusedContainerColor,
        disabledContainerColor: Color = unfocusedContainerColor,
        errorContainerColor: Color = disabledContainerColor,
        cursorColor: Color = CupertinoTheme.colorScheme.accent,
        errorCursorColor: Color = errorTextColor,
        selectionColors: TextSelectionColors =
            TextSelectionColors(cursorColor, cursorColor.copy(alpha = .25f)),
        focusedBorderColor: Color = Color.Transparent,
        unfocusedBorderColor: Color = focusedBorderColor,
        disabledBorderColor: Color = focusedBorderColor,
        errorBorderColor: Color = errorTextColor,
        focusedLeadingIconColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedLeadingIconColor: Color = focusedLeadingIconColor,
        disabledLeadingIconColor: Color = focusedLeadingIconColor,
        errorLeadingIconColor: Color = focusedLeadingIconColor,
        focusedTrailingIconColor: Color = focusedLeadingIconColor,
        unfocusedTrailingIconColor: Color = focusedTrailingIconColor,
        disabledTrailingIconColor: Color = focusedTrailingIconColor,
        errorTrailingIconColor: Color = focusedTrailingIconColor,
        focusedPlaceholderColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedPlaceholderColor: Color = focusedPlaceholderColor,
        disabledPlaceholderColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        errorPlaceholderColor: Color = focusedPlaceholderColor,
    ): CupertinoTextFieldColors
```

## `CupertinoSegmentedControl` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSegmentedControl.kt:90

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSegmentedControl(
    selectedTabIndex: Int,
    modifier: Modifier = Modifier,
    colors : CupertinoSegmentedControlColors = CupertinoSegmentedControlDefaults.colors(),
    shape : Shape = CupertinoSegmentedControlDefaults.shape,
    paddingValues: PaddingValues = CupertinoSegmentedControlDefaults.PaddingValues,
    indicator: @Composable (tabPositions: List<TabPosition>) -> Unit = @Composable { tabPositions ->
        CupertinoSegmentedControlIndicator(
            selectedTabIndex = selectedTabIndex,
            tabPositions = tabPositions,
            color = colors.indicatorColor,
            shape = shape,
            separatorColor = colors.separatorColor
        )
    },
    tabs: @Composable () -> Unit
)
```

## `CupertinoSegmentedControlIndicator` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSegmentedControl.kt:137

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSegmentedControlIndicator(
    selectedTabIndex: Int,
    tabPositions: List<TabPosition>,
    modifier: Modifier = Modifier,
    shape: Shape = CupertinoTheme.shapes.small,
    color: Color = CupertinoSegmentedControlDefaults.colors().indicatorColor,
    separatorColor : Color = CupertinoTheme.colorScheme.separator,
)
```

## `CupertinoSegmentedControlTab` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSegmentedControl.kt:209

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSegmentedControlTab(
    onClick: () -> Unit,
    isSelected : Boolean,
    modifier: Modifier = Modifier,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable () -> Unit,
)
```

## `CupertinoSegmentedControlDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSegmentedControl.kt:288

```kotlin
@Composable
@ReadOnlyComposable
fun colors(
        containerColor : Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        indicatorColor: Color = if (isDark())
            CupertinoColors.systemGray8(true)
        else CupertinoColors.White,
        contentColor: Color = CupertinoTheme.colorScheme.label,
        separatorColor: Color = CupertinoTheme.colorScheme.separator
    )
```

## `CupertinoSlider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:138

```kotlin
@Composable
fun CupertinoSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    steps: Int = 0,
    onValueChangeFinished: (() -> Unit)? = null,
    colors: CupertinoSliderColors = CupertinoSliderDefaults.defaultColorsFor(steps),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() }
)
```

## `CupertinoSlider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:211

```kotlin
@Composable
fun CupertinoSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    onValueChangeFinished: (() -> Unit)? = null,
    steps: Int = 0,
    colors: CupertinoSliderColors = CupertinoSliderDefaults.defaultColorsFor(steps),
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    thumb: @Composable (SliderPositions) -> Unit = {
        CupertinoSliderDefaults.Thumb(
            interactionSource = interactionSource,
            colors = colors,
            enabled = enabled
        )
    },
    track: @Composable (SliderPositions) -> Unit = { sliderPositions ->
        CupertinoSliderDefaults.Track(
            colors = colors,
            enabled = enabled,
            sliderPositions = sliderPositions
        )
    },
    /*@IntRange(from = 0)*/
)
```

## `CupertinoRangeSlider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:276

```kotlin
@Composable
fun CupertinoRangeSlider(
    value: ClosedFloatingPointRange<Float>,
    onValueChange: (ClosedFloatingPointRange<Float>) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    /*@IntRange(from = 0)*/
    steps: Int = 0,
    onValueChangeFinished: (() -> Unit)? = null,
    colors: CupertinoSliderColors = CupertinoSliderDefaults.defaultColorsFor(steps)
)
```

## `CupertinoRangeSlider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:364

```kotlin
@Composable
fun CupertinoRangeSlider(
    value: ClosedFloatingPointRange<Float>,
    onValueChange: (ClosedFloatingPointRange<Float>) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    onValueChangeFinished: (() -> Unit)? = null,
    steps: Int = 0,
    colors: CupertinoSliderColors = CupertinoSliderDefaults.defaultColorsFor(steps),
    startInteractionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    endInteractionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    startThumb: @Composable (SliderPositions) -> Unit = {
        CupertinoSliderDefaults.Thumb(
            interactionSource = startInteractionSource,
            colors = colors,
            enabled = enabled
        )
    },
    endThumb: @Composable (SliderPositions) -> Unit = {
        CupertinoSliderDefaults.Thumb(
            interactionSource = endInteractionSource,
            colors = colors,
            enabled = enabled
        )
    },
    track: @Composable (SliderPositions) -> Unit = { sliderPositions ->
        CupertinoSliderDefaults.Track(
            colors = colors,
            enabled = enabled,
            sliderPositions = sliderPositions
        )
    },
)
```

## `CupertinoSliderDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:845

```kotlin
@Composable
@ReadOnlyComposable
fun colors(
        thumbColor: Color = CupertinoColors.White,
        activeTrackColor: Color = CupertinoTheme.colorScheme.accent,
        activeTickColor: Color = CupertinoTheme.colorScheme.separator,
        inactiveTrackColor: Color = CupertinoTheme.colorScheme.separator,
        inactiveTickColor: Color = activeTickColor,
        disabledThumbColor: Color = thumbColor,
        disabledActiveTrackColor: Color = activeTrackColor.copy(alpha = .5f),
        disabledActiveTickColor: Color = activeTickColor,
        disabledInactiveTrackColor: Color = inactiveTrackColor.copy(alpha = .5f),
        disabledInactiveTickColor: Color = activeTickColor
    ): CupertinoSliderColors
```

## `CupertinoSliderDefaults.colorsSteps` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:898

```kotlin
@Composable
@ReadOnlyComposable
fun colorsSteps(
        thumbColor: Color = CupertinoColors.White,
        activeTrackColor: Color = CupertinoColors.systemGray,
        activeTickColor: Color = activeTrackColor,
        inactiveTrackColor: Color = activeTrackColor,
        inactiveTickColor: Color = activeTickColor,
        disabledThumbColor: Color = thumbColor,
        disabledActiveTrackColor: Color = activeTrackColor,
        disabledActiveTickColor: Color = activeTickColor,
        disabledInactiveTrackColor: Color = inactiveTrackColor,
        disabledInactiveTickColor: Color = activeTickColor
    ): CupertinoSliderColors
```

## `CupertinoSliderDefaults.defaultColorsFor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:923

```kotlin
@Composable
fun defaultColorsFor(steps: Int)
```

## `CupertinoSliderDefaults.Thumb` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:943

```kotlin
@Composable
fun Thumb(
        interactionSource: MutableInteractionSource,
        modifier: Modifier = Modifier,
        colors: CupertinoSliderColors = colors(),
        enabled: Boolean = true,
        thumbSize: DpSize = ThumbSize
    )
```

## `CupertinoSliderDefaults.Track` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:988

```kotlin
@Composable
fun Track(
        sliderPositions: SliderPositions,
        modifier: Modifier = Modifier,
        colors: CupertinoSliderColors = colors(),
        enabled: Boolean = true,
    )
```

## `CupertinoSliderColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:1369

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoSliderColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:1387

```kotlin

override fun hashCode(): Int
```

## `SliderPositions.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:1476

```kotlin

override fun equals(other: Any?): Boolean
```

## `SliderPositions.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSlider.kt:1486

```kotlin

override fun hashCode(): Int
```

## `SharedSwipeBoxController.collapse` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:157

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
fun collapse()
```

## `rememberCupertinoSwipeBoxState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:181

```kotlin
@Composable
@ExperimentalCupertinoApi
@Stable
fun rememberCupertinoSwipeBoxState(
    initialValue: CupertinoSwipeBoxValue = CupertinoSwipeBoxValue.Collapsed,
    sharedController : SharedSwipeBoxController? = GlobalSwipeBoxController,
    scrollableState: ScrollableState? = null,
    dismissThreshold: Float = CupertinoSwipeBoxDefaults.DismissThreshold,
    animationSpec : FiniteAnimationSpec<Float> = CupertinoSwipeBoxDefaults.AnimationSpec,
    confirmValueChange: (CupertinoSwipeBoxValue) -> Boolean = { true },
) : CupertinoSwipeBoxState
```

## `CupertinoSwipeBox` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:289

```kotlin
@OptIn(
@Composable
@ExperimentalCupertinoApi
fun CupertinoSwipeBox(
    state: CupertinoSwipeBoxState,
    items: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    restoreOnClick : Boolean = true,
    handleWidth : Dp = Dp.Unspecified,
    itemWidth: Dp = CupertinoSwipeBoxDefaults.ItemWidth,
    startToEndBehavior: SwipeBoxBehavior = SwipeBoxBehavior.Dismissible,
    endToStartBehavior: SwipeBoxBehavior = SwipeBoxBehavior.Dismissible,
    content: @Composable RowScope.() -> Unit,
)
```

## `CupertinoSwipeBoxItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:542

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSwipeBoxItem(
    color : Color,
    onClick : () -> Unit,
    modifier: Modifier = Modifier,
    enabled : Boolean = true,
    onClickLabel : String? = null,
    interactionSource : MutableInteractionSource = remember { MutableInteractionSource() },
    icon : @Composable () -> Unit,
    label : @Composable () -> Unit
)
```

## `CupertinoSwipeBoxItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:594

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSwipeBoxItem(
    color : Color,
    onClick : () -> Unit,
    modifier: Modifier = Modifier,
    enabled : Boolean = true,
    onClickLabel : String? = null,
    interactionSource : MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable ColumnScope.() -> Unit
)
```

## `CupertinoSwipeBoxState.requireOffset` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:697

```kotlin

fun requireOffset(): Float
```

## `CupertinoSwipeBoxState.snapTo` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:730

```kotlin

suspend fun snapTo(targetValue: CupertinoSwipeBoxValue)
```

## `CupertinoSwipeBoxState.animateTo` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:734

```kotlin

suspend fun animateTo(direction: CupertinoSwipeBoxValue)
```

## `CupertinoSwipeBoxState.reset` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:745

```kotlin

suspend fun reset()
```

## `CupertinoSwipeBoxState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwipeBox.kt:753

```kotlin

fun Saver(
            dismissThreshold: Float,
            animationSpec : FiniteAnimationSpec<Float>,
            confirmValueChange: (CupertinoSwipeBoxValue) -> Boolean,
            density: Density,
        )
```

## `CupertinoSwitch` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwitch.kt:93

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
fun CupertinoSwitch(
    checked : Boolean,
    onCheckedChange : (Boolean) -> Unit,
    modifier : Modifier = Modifier,
    thumbContent: @Composable (() -> Unit)? = null,
    colors : CupertinoSwitchColors = CupertinoSwitchDefaults.colors(),
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() }
)
```

## `CupertinoSwitchColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwitch.kt:277

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoSwitchColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwitch.kt:295

```kotlin

override fun hashCode(): Int
```

## `CupertinoSwitchDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoSwitch.kt:323

```kotlin
@Composable
@ReadOnlyComposable
fun colors(
        thumbColor: Color = Color.White,
        disabledThumbColor: Color = thumbColor,
        checkedTrackColor: Color = CupertinoColors.systemGreen,
        checkedIconColor: Color = CupertinoTheme.colorScheme.opaqueSeparator,
        uncheckedTrackColor: Color = CupertinoColors.Gray.copy(
            alpha = .33f
        ),
        uncheckedIconColor: Color = checkedIconColor,
        disabledCheckedTrackColor: Color = checkedTrackColor.copy(alpha = .33f),
        disabledCheckedIconColor: Color = checkedIconColor,
        disabledUncheckedTrackColor: Color = uncheckedTrackColor,
        disabledUncheckedIconColor: Color = checkedIconColor,
    ) : CupertinoSwitchColors
```

## `CupertinoTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:69

```kotlin
@Composable
fun CupertinoTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = LocalTextStyle.current,
    placeholder: @Composable (() -> Unit)? = null,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    contentAlignment: Alignment.Vertical = Alignment.CenterVertically,
    colors: CupertinoTextFieldColors = CupertinoTextFieldDefaults.colors()
)
```

## `CupertinoTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:147

```kotlin
@Composable
fun CupertinoTextField(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = LocalTextStyle.current,
    placeholder: @Composable (() -> Unit)? = null,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    contentAlignment: Alignment.Vertical = Alignment.CenterVertically,
    colors: CupertinoTextFieldColors = CupertinoTextFieldDefaults.colors()
)
```

## `CupertinoBorderedTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:224

```kotlin
@Composable
fun CupertinoBorderedTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = LocalTextStyle.current,
    placeholder: @Composable (() -> Unit)? = null,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    shape: Shape = CupertinoBorderedTextFieldDefaults.shape,
    strokeWidth: Dp = CupertinoBorderedTextFieldDefaults.StrokeWidth,
    paddingValues: PaddingValues = CupertinoBorderedTextFieldDefaults.PaddingValues,
    contentAlignment: Alignment.Vertical = Alignment.CenterVertically,
    colors: CupertinoTextFieldColors = CupertinoBorderedTextFieldDefaults.colors()
)
```

## `CupertinoBorderedTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:283

```kotlin
@Composable
fun CupertinoBorderedTextField(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle = LocalTextStyle.current,
    placeholder: @Composable (() -> Unit)? = null,
    leadingIcon: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable (() -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    shape: Shape = CupertinoBorderedTextFieldDefaults.shape,
    strokeWidth: Dp = CupertinoBorderedTextFieldDefaults.StrokeWidth,
    paddingValues: PaddingValues = CupertinoBorderedTextFieldDefaults.PaddingValues,
    contentAlignment: Alignment.Vertical = Alignment.CenterVertically,
    colors: CupertinoTextFieldColors = CupertinoBorderedTextFieldDefaults.colors()
)
```

## `CupertinoTextFieldColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:538

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoTextFieldColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:573

```kotlin

override fun hashCode(): Int
```

## `CupertinoBorderedTextFieldDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:655

```kotlin
@Composable
fun colors(
        focusedTextColor: Color = CupertinoTheme.colorScheme.label,
        unfocusedTextColor: Color = CupertinoTheme.colorScheme.label,
        disabledTextColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        errorTextColor: Color = CupertinoColors.systemRed,
        focusedContainerColor: Color = Color.Transparent,
        unfocusedContainerColor: Color = focusedContainerColor,
        disabledContainerColor: Color = unfocusedContainerColor,
        errorContainerColor: Color = disabledContainerColor,
        cursorColor: Color = CupertinoTheme.colorScheme.accent,
        errorCursorColor: Color = errorTextColor,
        selectionColors: TextSelectionColors =
            TextSelectionColors(cursorColor, cursorColor.copy(alpha = .25f)),
        focusedBorderColor: Color = CupertinoTheme.colorScheme.quaternaryLabel,
        unfocusedBorderColor: Color = focusedBorderColor,
        disabledBorderColor: Color = focusedBorderColor,
        errorBorderColor: Color = errorTextColor,
        focusedLeadingIconColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedLeadingIconColor: Color = focusedLeadingIconColor,
        disabledLeadingIconColor: Color = focusedLeadingIconColor,
        errorLeadingIconColor: Color = focusedLeadingIconColor,
        focusedTrailingIconColor: Color = focusedLeadingIconColor,
        unfocusedTrailingIconColor: Color = focusedTrailingIconColor,
        disabledTrailingIconColor: Color = focusedTrailingIconColor,
        errorTrailingIconColor: Color = focusedTrailingIconColor,
        focusedPlaceholderColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedPlaceholderColor: Color = focusedPlaceholderColor,
        disabledPlaceholderColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        errorPlaceholderColor: Color = focusedPlaceholderColor,
    ): CupertinoTextFieldColors
```

## `CupertinoTextFieldDefaults.colors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:778

```kotlin
@Composable
fun colors(
        focusedTextColor: Color = CupertinoTheme.colorScheme.label,
        unfocusedTextColor: Color = CupertinoTheme.colorScheme.label,
        disabledTextColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        errorTextColor: Color = CupertinoColors.systemRed,
        focusedContainerColor: Color = Color.Transparent,
        unfocusedContainerColor: Color = Color.Transparent,
        disabledContainerColor: Color = Color.Transparent,
        errorContainerColor: Color = Color.Transparent,
        cursorColor: Color = CupertinoTheme.colorScheme.accent,
        errorCursorColor: Color = CupertinoColors.systemRed,
        selectionColors: TextSelectionColors =
            TextSelectionColors(cursorColor, cursorColor.copy(alpha = .25f)),
        focusedBorderColor: Color = Color.Transparent,
        unfocusedBorderColor: Color = Color.Transparent,
        disabledBorderColor: Color = Color.Transparent,
        errorBorderColor: Color = Color.Transparent,
        focusedLeadingIconColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedLeadingIconColor: Color = focusedLeadingIconColor,
        disabledLeadingIconColor: Color = focusedLeadingIconColor,
        errorLeadingIconColor: Color = focusedLeadingIconColor,
        focusedTrailingIconColor: Color = focusedLeadingIconColor,
        unfocusedTrailingIconColor: Color = focusedTrailingIconColor,
        disabledTrailingIconColor: Color = focusedTrailingIconColor,
        errorTrailingIconColor: Color = focusedTrailingIconColor,
        focusedPlaceholderColor: Color = CupertinoTheme.colorScheme.secondaryLabel,
        unfocusedPlaceholderColor: Color = focusedPlaceholderColor,
        disabledPlaceholderColor: Color = CupertinoTheme.colorScheme.tertiaryLabel,
        errorPlaceholderColor: Color = focusedPlaceholderColor,
    ): CupertinoTextFieldColors
```

## `CupertinoTextFieldDefaults.DecorationBox` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTextField.kt:839

```kotlin
@Composable
fun DecorationBox(
        valueIsEmpty: Boolean,
        innerTextField: @Composable () -> Unit,
        enabled: Boolean,
        contentAlignment: Alignment.Vertical,
        interactionSource: InteractionSource,
        textLayoutResult: TextLayoutResult?,
        isError: Boolean = false,
        modifier: Modifier = Modifier,
        placeholder: @Composable (() -> Unit)? = null,
        leadingIcon: @Composable (() -> Unit)? = null,
        trailingIcon: @Composable (() -> Unit)? = null,
        colors: CupertinoTextFieldColors = colors()
    )
```

## `rememberCupertinoTimePickerState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePicker.kt:73

```kotlin
@Composable
@ExperimentalCupertinoApi
fun rememberCupertinoTimePickerState(
    initialHour: Int = 0,
    initialMinute: Int = 0,
    is24Hour: Boolean = PlatformDateFormat.is24HourFormat(defaultLocale()),
): CupertinoTimePickerState
```

## `CupertinoTimePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePicker.kt:92

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
@ExperimentalCupertinoApi
fun CupertinoTimePicker(
    state: CupertinoTimePickerState,
    height : Dp = CupertinoPickerDefaults.Height,
    indicator: CupertinoPickerIndicator = CupertinoPickerDefaults.indicator(),
    containerColor : Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    },
    modifier: Modifier = Modifier
)
```

## `CupertinoTimePickerState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePicker.kt:396

```kotlin

fun Saver(): Saver<CupertinoTimePickerState, *>
```

## `LazyListState.isTopBarTransparent` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:93

```kotlin
@Composable
@ExperimentalCupertinoApi
fun LazyListState.isTopBarTransparent(topPadding : Dp = 0.dp) : Boolean
```

## `cupertinoTranslucentTopBarColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:125

```kotlin
@Composable
@ExperimentalCupertinoApi
fun cupertinoTranslucentTopBarColor(color: Color, isTranslucent: Boolean, isTransparent: Boolean) : Color
```

## `CupertinoTopAppBar` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:168

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoTopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable (RowScope.() -> Unit) = {},
    windowInsets: WindowInsets = LocalTopAppBarInsets.current ?: CupertinoTopAppBarDefaults.windowInsets,
    isTransparent : Boolean = false,
    isTranslucent : Boolean = LocalAppBarsState.current != null,
    divider: @Composable () -> Unit = {
        if (!isTransparent) {
            CupertinoTopAppBarDefaults.divider()
        }
    },
    colors: CupertinoTopAppBarColors = CupertinoTopAppBarDefaults.topAppBarColors(),
)
```

## `CupertinoNavigationTitle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:245

```kotlin
@Composable
fun CupertinoNavigationTitle(
    modifier: Modifier = Modifier,
    maxFontScale : Float = NavTitleMaxFontScale,
    maxFontScaleDistance : Dp = NavTitleMaxFontScaleDistance,
    paddingValues: PaddingValues = CupertinoSectionDefaults.PaddingValues,
    content: @Composable () -> Unit
)
```

## `CupertinoTopAppBarColors.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:540

```kotlin

override fun equals(other: Any?): Boolean
```

## `CupertinoTopAppBarColors.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:553

```kotlin

override fun hashCode(): Int
```

## `CupertinoTopAppBarDefaults.divider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:779

```kotlin
@Composable
fun divider()
```

## `CupertinoTopAppBarDefaults.topAppBarColors` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTopBars.kt:803

```kotlin
@Composable
@ReadOnlyComposable
fun topAppBarColors(
        containerColor: Color = CupertinoTheme.colorScheme.tertiarySystemBackground,
        scrolledContainerColor: Color = Color.Transparent,
        navigationIconContentColor: Color = CupertinoTheme.colorScheme.accent,
        titleContentColor: Color = CupertinoTheme.colorScheme.label,
        actionIconContentColor: Color = CupertinoTheme.colorScheme.accent,
    ): CupertinoTopAppBarColors
```

## `Modifier.haze` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/HazePlatform.kt:51

```kotlin
@Composable
fun Modifier.haze(
    vararg area: Rect,
    backgroundColor: Color,
    tint: Color = HazeDefaults.tint(backgroundColor),
    blurRadius: Dp = HazeDefaults.blurRadius,
): Modifier
```

## `HazeDefaults.tint` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/HazePlatform.kt:82

```kotlin

fun tint(color: Color): Color
```

## `CupertinoDivider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Separator.kt:49

```kotlin
@Composable
@Deprecated(
fun CupertinoDivider(
    modifier: Modifier = Modifier,
    thickness : Dp = CupertinoDividerDefaults.Thickness,
    color : Color = CupertinoDividerDefaults.color
)
```

## `CupertinoHorizontalDivider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Separator.kt:56

```kotlin
@Composable
fun CupertinoHorizontalDivider(
    modifier: Modifier = Modifier,
    thickness : Dp = CupertinoDividerDefaults.Thickness,
    color : Color = CupertinoDividerDefaults.color
)
```

## `CupertinoVerticalDivider` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Separator.kt:76

```kotlin
@Composable
fun CupertinoVerticalDivider(
    modifier: Modifier = Modifier,
    thickness : Dp = CupertinoDividerDefaults.Thickness,
    color : Color = CupertinoDividerDefaults.color
)
```

## `CupertinoSurface` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Surface.kt:47

```kotlin
@Composable
fun CupertinoSurface(
    modifier: Modifier = Modifier,
    shape: Shape = RectangleShape,
    color: Color = CupertinoTheme.colorScheme.systemBackground,
    shadowElevation : Dp = 0.dp,
    contentColor: Color = LocalContentColor.current,
    content: @Composable () -> Unit
)
```

## `CupertinoSurface` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Surface.kt:80

```kotlin
@Composable
fun CupertinoSurface(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = RectangleShape,
    color: Color = CupertinoTheme.colorScheme.systemBackground,
    contentColor: Color = LocalContentColor.current,
    border: BorderStroke? = null,
    indication: Indication? = LocalIndication.current,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable () -> Unit
)
```

## `Surface` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Surface.kt:126

```kotlin
@Deprecated(
@Composable
fun Surface(
    modifier: Modifier = Modifier,
    shape: Shape = RectangleShape,
    color: Color = CupertinoTheme.colorScheme.systemBackground,
    shadowElevation : Dp = 0.dp,
    contentColor: Color = LocalContentColor.current,
    content: @Composable () -> Unit
)
```

## `Surface` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Surface.kt:150

```kotlin
@Deprecated(
@Composable
fun Surface(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    shape: Shape = RectangleShape,
    color: Color = CupertinoTheme.colorScheme.systemBackground,
    contentColor: Color = LocalContentColor.current,
    border: BorderStroke? = null,
    indication: Indication? = LocalIndication.current,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    content: @Composable () -> Unit
)
```

## `TabPosition.equals` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/TabRow.kt:186

```kotlin

override fun equals(other: Any?): Boolean
```

## `TabPosition.hashCode` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/TabRow.kt:196

```kotlin

override fun hashCode(): Int
```

## `TabPosition.toString` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/TabRow.kt:202

```kotlin

override fun toString(): String
```

## `TabRowDefaults.Modifier.tabIndicatorOffset` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/TabRow.kt:220

```kotlin

fun Modifier.tabIndicatorOffset(
        currentTabPosition: TabPosition
    ): Modifier
```

## `CupertinoText` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Text.kt:92

```kotlin
@Composable
fun CupertinoText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign = TextAlign.Unspecified,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = LocalTextStyle.current
)
```

## `CupertinoText` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Text.kt:149

```kotlin
@Deprecated(
@Composable
fun CupertinoText(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign = TextAlign.Unspecified,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = LocalTextStyle.current
)
```

## `CupertinoText` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Text.kt:241

```kotlin
@Composable
fun CupertinoText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign = TextAlign.Unspecified,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    minLines: Int = 1,
    inlineContent: Map<String, InlineTextContent> = mapOf(),
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = LocalTextStyle.current
)
```

## `CupertinoText` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Text.kt:299

```kotlin
@Deprecated(
@Composable
fun CupertinoText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    color: Color = Color.Unspecified,
    fontSize: TextUnit = TextUnit.Unspecified,
    fontStyle: FontStyle? = null,
    fontWeight: FontWeight? = null,
    fontFamily: FontFamily? = null,
    letterSpacing: TextUnit = TextUnit.Unspecified,
    textDecoration: TextDecoration? = null,
    textAlign: TextAlign = TextAlign.Unspecified,
    lineHeight: TextUnit = TextUnit.Unspecified,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
    maxLines: Int = Int.MAX_VALUE,
    inlineContent: Map<String, InlineTextContent> = mapOf(),
    onTextLayout: (TextLayoutResult) -> Unit = {},
    style: TextStyle = LocalTextStyle.current
)
```

## `ProvideTextStyle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Text.kt:348

```kotlin
@Composable
fun ProvideTextStyle(value: TextStyle, content: @Composable () -> Unit)
```

## `CupertinoLinkIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoLinkIcon.kt:54

```kotlin
@Composable
fun CupertinoLinkIcon(
    painter : Painter,
    modifier: Modifier = Modifier,
    containerColor: Color = CupertinoLabelIconDefaults.ContainerColor,
    tint : Color = CupertinoLabelIconDefaults.Tint,
    shape: Shape = CupertinoLabelIconDefaults.Shape,
    contentDescription : String? = null
)
```

## `CupertinoLinkIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoLinkIcon.kt:83

```kotlin
@Composable
fun CupertinoLinkIcon(
    imageVector : ImageVector,
    modifier: Modifier = Modifier,
    containerColor: Color = CupertinoLabelIconDefaults.ContainerColor,
    tint : Color = CupertinoLabelIconDefaults.Tint,
    shape: Shape = CupertinoLabelIconDefaults.Shape,
    contentDescription : String? = null
)
```

## `CupertinoLinkIcon` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoLinkIcon.kt:110

```kotlin
@Composable
fun CupertinoLinkIcon(
    bitmap: ImageBitmap,
    modifier: Modifier = Modifier,
    containerColor: Color = CupertinoLabelIconDefaults.ContainerColor,
    tint : Color = CupertinoLabelIconDefaults.Tint,
    shape: Shape = CupertinoLabelIconDefaults.Shape,
    contentDescription : String? = null
)
```

## `CupertinoSectionDefaults.paddingValues` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:90

```kotlin
@Composable
@ReadOnlyComposable
fun paddingValues(
        style: SectionStyle,
        includePaddingBetweenSections: Boolean
    ): PaddingValues
```

## `CupertinoSectionDefaults.shape` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:107

```kotlin
@Composable
@ReadOnlyComposable
fun shape(style: SectionStyle = LocalSectionStyle.current): CornerBasedShape
```

## `CupertinoSectionDefaults.titleColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:114

```kotlin
@Composable
@ReadOnlyComposable
fun titleColor(style: SectionStyle)
```

## `CupertinoSectionDefaults.titleTextStyle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:120

```kotlin
@Composable
@ReadOnlyComposable
fun titleTextStyle(style: SectionStyle = LocalSectionStyle.current)
```

## `CupertinoSectionDefaults.captionTextStyle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:132

```kotlin
@Composable
@ReadOnlyComposable
fun captionTextStyle(style: SectionStyle = LocalSectionStyle.current)
```

## `CupertinoSectionDefaults.captionColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:139

```kotlin
@Composable
@ReadOnlyComposable
fun captionColor(style: SectionStyle = LocalSectionStyle.current)
```

## `CupertinoSectionDefaults.containerColor` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:146

```kotlin
@Composable
@ReadOnlyComposable
fun containerColor(style: SectionStyle)
```

## `CupertinoSectionDefaults.PickerButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:151

```kotlin
@Composable
fun PickerButton(
        modifier: Modifier,
        expanded: Boolean,
        shape: Shape = CupertinoTheme.shapes.small,
        containerColor: Color = CupertinoTheme.colorScheme.quaternarySystemFill,
        activeContentColor: Color = CupertinoTheme.colorScheme.accent,
        contentColor: Color = CupertinoTheme.colorScheme.label,
        title: @Composable () -> Unit,
    )
```

## `CupertinoSectionDefaults.LabelChevron` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:180

```kotlin
@Composable
fun LabelChevron()
```

## `CupertinoSectionDefaults.TextFieldClearButton` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/CupertinoSectionDefaults.kt:193

```kotlin
@Composable
fun TextFieldClearButton(
        visible : Boolean,
        onClick : () -> Unit
    )
```

## `LazyListScope.section` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazyListSection.kt:68

```kotlin
@ExperimentalCupertinoApi
fun LazyListScope.section(
    style: SectionStyle? = null,
    state: SectionState? = null,
    enterTransition: EnterTransition = CupertinoSectionDefaults.EnterTransition,
    exitTransition: ExitTransition = CupertinoSectionDefaults.ExitTransition,
    shape : CornerBasedShape ?= null,
    color : Color = Color.Unspecified,
    title: @Composable (LazyItemScope.() -> Unit)? = null,
    caption: @Composable (LazyItemScope.() -> Unit)? = null,
    content: LazySectionScope.() -> Unit
)
```

## `LazyListScope.stickySection` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazyListSection.kt:143

```kotlin
@OptIn(ExperimentalFoundationApi::class)
@ExperimentalCupertinoApi
fun LazyListScope.stickySection(
    style: SectionStyle? = null,
    state: SectionState? = null,
    enterTransition: EnterTransition = CupertinoSectionDefaults.EnterTransition,
    exitTransition: ExitTransition = CupertinoSectionDefaults.ExitTransition,
    shape : CornerBasedShape ?= null,
    color : Color = Color.Unspecified,
    title: @Composable (LazyItemScope.(PaddingValues) -> Unit)? = null,
    caption: @Composable (LazyItemScope.() -> Unit)? = null,
    content: LazySectionScope.() -> Unit
)
```

## `LazySectionScope.item` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:106

```kotlin

fun item(
        key: Any? = null,
        contentType: Any? = null,
        dividerPadding : Dp = CupertinoSectionDefaults.DividerPadding,
        content: @Composable (padding : PaddingValues) -> Unit
    )
```

## `LazySectionScope.link` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:131

```kotlin
@ExperimentalCupertinoApi
fun LazySectionScope.link(
    onClick: () -> Unit,
    key: Any? = null,
    enabled: Boolean = true,
    icon: (@Composable () -> Unit)? = null,
    dividerPadding: Dp = if (icon != null)
        CupertinoSectionDefaults.DividerPaddingWithIcon
    else CupertinoSectionDefaults.DividerPadding,
    onClickLabel: String? = null,
    interactionSource: MutableInteractionSource? = null,
    caption : @Composable () -> Unit = {},
    trailingIcon : @Composable () -> Unit = {
        CupertinoSectionDefaults.LabelChevron()
    },
    title: @Composable () -> Unit,
)
```

## `LazySectionScope.dropdownMenu` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:179

```kotlin
@ExperimentalCupertinoApi
fun LazySectionScope.dropdownMenu(
    expanded: Boolean,
    onDismissRequest : () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    key: Any? = null,
    enabled: Boolean = true,
    icon: (@Composable () -> Unit)? = null,
    width: Dp = CupertinoDropdownMenuDefaults.SmallWidth,
    dividerPadding: Dp = if (icon != null)
        CupertinoSectionDefaults.DividerPaddingWithIcon
    else CupertinoSectionDefaults.DividerPadding,
    onClickLabel: String? = null,
    interactionSource: MutableInteractionSource? = null,
    selectedLabel : @Composable () -> Unit = {},
    title: @Composable () -> Unit,
    content : @Composable CupertinoMenuScope.() -> Unit
)
```

## `LazySectionScope.switch` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:260

```kotlin
@ExperimentalCupertinoApi
fun LazySectionScope.switch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    key: Any? = null,
    enabled: Boolean = true,
    colors : CupertinoSwitchColors ?= null,
    icon: (@Composable () -> Unit)? = null,
    dividerPadding: Dp = if (icon != null)
        CupertinoSectionDefaults.DividerPaddingWithIcon
    else CupertinoSectionDefaults.DividerPadding,
    interactionSource: MutableInteractionSource? = null,
    thumbContent: @Composable (() -> Unit)? = null,
    title: @Composable () -> Unit,
)
```

## `LazySectionScope.datePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:308

```kotlin
@ExperimentalCupertinoApi
fun LazySectionScope.datePicker(
    state: CupertinoDatePickerState,
    expanded : Boolean,
    onExpandedChange : (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    style : DatePickerStyle? = null,
    enabled: Boolean = true,
    icon: (@Composable () -> Unit)? = null,
    dividerPadding: Dp = if (icon != null)
        CupertinoSectionDefaults.DividerPaddingWithIcon
    else CupertinoSectionDefaults.DividerPadding,
    buttonColor : Color = Color.Unspecified,
    button : @Composable (
        buttonModifier : Modifier,
        titleModifier: Modifier,
        text : String
    ) -> Unit = { buttonModifier, titleModifier, text ->
        CupertinoSectionDefaults.PickerButton(
            modifier = buttonModifier,
            containerColor = buttonColor,
            expanded = expanded,
            title = {
                CupertinoText(
                    text = text,
                    modifier = titleModifier
                )
            }
        )
    },
    title: @Composable () -> Unit,
)
```

## `LazySectionScope.timePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:372

```kotlin
@ExperimentalCupertinoApi
fun LazySectionScope.timePicker(
    state: CupertinoTimePickerState,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: @Composable() (() -> Unit)? = null,
    dividerPadding: Dp = if (icon != null)
        CupertinoSectionDefaults.DividerPaddingWithIcon
    else CupertinoSectionDefaults.DividerPadding,
    buttonColor : Color = Color.Unspecified,
    button: @Composable (buttonModifier: Modifier, titleModifier: Modifier, text: String) -> Unit = { buttonModifier, titleModifier, text ->
        CupertinoSectionDefaults.PickerButton(
            modifier = buttonModifier,
            containerColor = buttonColor,
            expanded = expanded,
            title = {
                CupertinoText(
                    text = text,
                    modifier = titleModifier
                )
            }
        )
    },
    title: @Composable () -> Unit,
)
```

## `LazySectionScope.textField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:425

```kotlin

fun LazySectionScope.textField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle? = null,
    placeholder: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable ((InteractionSource) -> Unit)? = {
        val focused by it.collectIsFocusedAsState()

        val updatedValueChange by rememberUpdatedState(onValueChange)

        CupertinoSectionDefaults.TextFieldClearButton(
            visible = focused && value.isNotEmpty(),
            onClick = {
                updatedValueChange.invoke("")
            }
        )
    },
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource? = null,
    dividerPadding: Dp = CupertinoSectionDefaults.DividerPadding,
    colors: CupertinoTextFieldColors? = null,
)
```

## `LazySectionScope.items` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:503

```kotlin

inline fun LazySectionScope.items(
    count : Int,
    key: (Int) -> Any? = { null },
    contentType: (Int) -> Any? = { null },
    dividerPadding : Dp = CupertinoSectionDefaults.DividerPadding,
    crossinline content: @Composable (idx : Int, padding : PaddingValues) -> Unit
)
```

## `<T> LazySectionScope.items` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/LazySectionScope.kt:528

```kotlin

inline fun <T> LazySectionScope.items(
    items : Collection<T>,
    key: (T) -> Any? = { null },
    contentType: (T) -> Any? = { null },
    dividerPadding : Dp = CupertinoSectionDefaults.DividerPadding,
    crossinline content: @Composable (item : T, padding : PaddingValues) -> Unit
)
```

## `CupertinoSection` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/Section.kt:65

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoSection(
    modifier : Modifier = Modifier,
    style: SectionStyle = LocalSectionStyle.current,
    state: SectionState = rememberSectionState(canCollapse = true),
    enterTransition: EnterTransition = CupertinoSectionDefaults.EnterTransition,
    exitTransition: ExitTransition = CupertinoSectionDefaults.ExitTransition,
    shape : CornerBasedShape = CupertinoSectionDefaults.shape(style),
    color: Color = if (style.grouped)
        CupertinoSectionDefaults.Color
    else Color.Transparent,
    dividerPadding: PaddingValues = PaddingValues(
        start = CupertinoSectionDefaults.DividerPadding
    ),
    contentPadding : PaddingValues = CupertinoSectionDefaults.paddingValues(
        style = style,
        includePaddingBetweenSections = true
    ),
    title : (@Composable () -> Unit)? = null,
    caption : (@Composable () -> Unit)? = null,
    content : @Composable SectionScope.() -> Unit
)
```

## `SectionScope.SectionItem` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:75

```kotlin
@Composable
@ExperimentalCupertinoApi
fun SectionScope.SectionItem(
    modifier: Modifier = Modifier,
    paddingValues: PaddingValues = CupertinoSectionDefaults.PaddingValues,
    leadingContent: @Composable () -> Unit = {},
    trailingContent: @Composable () -> Unit = {},
    title: @Composable () -> Unit
)
```

## `SectionScope.SectionLink` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:123

```kotlin
@ExperimentalCupertinoApi
@Composable
fun SectionScope.SectionLink(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: @Composable () -> Unit = {},
    onClickLabel: String? = null,
    indication: Indication? = LocalIndication.current,
    interactionSource: MutableInteractionSource? = null,
    caption : @Composable () -> Unit = {},
    chevron : @Composable () -> Unit = {
        CupertinoSectionDefaults.LabelChevron()
    },
    title: @Composable () -> Unit,
)
```

## `SectionScope.SectionDropdownMenu` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:168

```kotlin
@ExperimentalCupertinoApi
@Composable
fun SectionScope.SectionDropdownMenu(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: @Composable () -> Unit = {},
    onClickLabel: String? = null,
    interactionSource: MutableInteractionSource? = null,
    selectedLabel : @Composable () -> Unit = {},
    title: @Composable () -> Unit,
    menu : @Composable (PaddingValues) -> Unit,
)
```

## `SectionScope.SectionDatePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:218

```kotlin
@ExperimentalCupertinoApi
@Composable
fun SectionScope.SectionDatePicker(
    state: CupertinoDatePickerState,
    expanded : Boolean,
    modifier: Modifier = Modifier,
    onExpandedChange : (Boolean) -> Unit,
    enabled: Boolean = true,
    leadingContent: @Composable () -> Unit = {},
    buttonColor : Color = Color.Unspecified,
    button : @Composable (
        buttonModifier : Modifier,
        titleModifier: Modifier,
        text : String
    ) -> Unit = { buttonModifier, titleModifier, text ->
        CupertinoSectionDefaults.PickerButton(
            modifier = buttonModifier,
            containerColor = buttonColor,
            expanded = expanded,
            title = {
                CupertinoText(
                    text = text,
                    modifier = titleModifier
                )
            }
        )
    },
    picker : @Composable () -> Unit,
    title: @Composable () -> Unit,
)
```

## `SectionScope.SectionTimePicker` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:276

```kotlin
@ExperimentalCupertinoApi
@Composable
fun SectionScope.SectionTimePicker(
    state: CupertinoTimePickerState,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    buttonColor : Color = Color.Unspecified,
    leadingContent: @Composable () -> Unit = {},
    button: @Composable (buttonModifier: Modifier, titleModifier: Modifier, text: String) -> Unit =
        { buttonModifier, titleModifier, text ->
            CupertinoSectionDefaults.PickerButton(
                modifier = buttonModifier,
                containerColor = buttonColor,
                expanded = expanded,
                title = {
                    CupertinoText(
                        text = text,
                        modifier = titleModifier
                    )
                }
            )
        },
    picker : @Composable () -> Unit,
    title: @Composable () -> Unit,
)
```

## `SectionScope.SectionTextField` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionScope.kt:325

```kotlin
@ExperimentalCupertinoApi
@Composable
fun SectionScope.SectionTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    textStyle: TextStyle? = null,
    placeholder: @Composable (() -> Unit)? = null,
    trailingIcon: @Composable ((InteractionSource) -> Unit)? = {
        val focused by it.collectIsFocusedAsState()

        val updatedValueChange by rememberUpdatedState(onValueChange)

        CupertinoSectionDefaults.TextFieldClearButton(
            visible = focused && value.isNotEmpty(),
            onClick = {
                updatedValueChange.invoke("")
            }
        )
    },
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    interactionSource: MutableInteractionSource? = null,
    colors: CupertinoTextFieldColors? = null,
)
```

## `rememberSectionState` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionState.kt:15

```kotlin
@Composable
fun rememberSectionState(
    initiallyCollapsed: Boolean = false,
    canCollapse: Boolean = true
) : SectionState
```

## `SectionState.toggle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionState.kt:40

```kotlin

fun toggle()
```

## `SectionState.collapse` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionState.kt:46

```kotlin

fun collapse()
```

## `SectionState.expand` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionState.kt:50

```kotlin

fun expand()
```

## `SectionState.Companion.Saver` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionState.kt:55

```kotlin

fun Saver(): Saver<SectionState, *>
```

## `ProvideSectionStyle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionStyle.kt:50

```kotlin
@Composable
fun ProvideSectionStyle(style: SectionStyle, content : @Composable () -> Unit)
```

## `String.sectionTitle` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionStyle.kt:58

```kotlin
@Composable
fun String.sectionTitle(style: SectionStyle = LocalSectionStyle.current)
```

## `Modifier.sectionContainerBackground` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/section/SectionStyle.kt:65

```kotlin

fun Modifier.sectionContainerBackground(style: SectionStyle? = null)
```

## `CupertinoTheme` — cupertino / commonMain

cupertino/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoTheme.kt:36

```kotlin
@OptIn(InternalCupertinoApi::class, ExperimentalCupertinoApi::class)
@Composable
fun CupertinoTheme(
    colorScheme: ColorScheme = if (isSystemInDarkTheme())
        darkColorScheme() else lightColorScheme(),
    shapes: Shapes = Shapes(),
    typography: Typography = Typography(),
    content : @Composable () -> Unit
)
```

## `FullscreenPopupProperties` — cupertino / skikoMain

cupertino/src/skikoMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogs.skiko.kt:30

```kotlin
@OptIn(ExperimentalComposeUiApi::class)
@Composable
@ReadOnlyComposable
actual fun FullscreenPopupProperties(
    dismissOnBackPress: Boolean,
    dismissOnClickOutside: Boolean,
    usePlatformDefaultWidth: Boolean,
) : PopupProperties
```

## `AdaptationScope.cupertino` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Adaptation.kt:45

```kotlin

fun cupertino(block: @Composable C.() -> Unit)
```

## `AdaptationScope.material` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Adaptation.kt:52

```kotlin

fun material(block: @Composable M.() -> Unit)
```

## `Adaptation.cupertino` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Adaptation.kt:65

```kotlin

override fun cupertino(block: @Composable C.() -> Unit)
```

## `Adaptation.material` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Adaptation.kt:69

```kotlin

override fun material(block: @Composable M.() -> Unit)
```

## `AdaptiveAlertDialog` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveAlertDialog.kt:47

```kotlin
@ExperimentalAdaptiveApi
@OptIn(ExperimentalCupertinoApi::class)
@Composable
fun AdaptiveAlertDialog(
    onDismissRequest: () -> Unit,
    title: @Composable () -> Unit,
    message: (@Composable () -> Unit)? = null,
    properties: DialogProperties = DialogProperties(),
    adaptation : AdaptationScope<CupertinoAlertAdaptation, MaterialAlertAdaptation>.() -> Unit = {},
    buttons: AlertDialogActionsScope.() -> Unit
)
```

## `AdaptiveAlertDialogNative` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveAlertDialogNative.kt:43

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveAlertDialogNative(
    onDismissRequest: () -> Unit,
    title: String,
    message: String,
    properties: DialogProperties = DialogProperties(),
    adaptation : AdaptationScope<CupertinoAlertAdaptationNative, MaterialAlertAdaptationNative>.() -> Unit = {},
    buttons: NativeAlertDialogActionsScope.() -> Unit
)
```

## `AdaptiveButton` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveButton.kt:54

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    border: BorderStroke? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoButtonAdaptation, MaterialButtonAdaptation>.() -> Unit = {},
    content: @Composable() (RowScope.() -> Unit)
)
```

## `AdaptiveTextButton` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveButton.kt:105

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveTextButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    border: BorderStroke? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoButtonAdaptation, MaterialButtonAdaptation>.() -> Unit = {},
    content: @Composable() (RowScope.() -> Unit)
)
```

## `AdaptiveTonalButton` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveButton.kt:156

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveTonalButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    border: BorderStroke? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoButtonAdaptation, MaterialButtonAdaptation>.() -> Unit = {},
    content: @Composable() (RowScope.() -> Unit)
)
```

## `AdaptiveCheckbox` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveCheckbox.kt:23

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveCheckbox(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation : AdaptationScope<CupertinoCheckBoxAdaptation,MaterialCheckBoxAdaptation>.() -> Unit = {}
)
```

## `AdaptiveTriStateCheckbox` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveCheckbox.kt:59

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveTriStateCheckbox(
    state: ToggleableState,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation : AdaptationScope<CupertinoCheckBoxAdaptation,MaterialCheckBoxAdaptation>.() -> Unit = {}
)
```

## `AdaptiveDatePicker` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveDatePicker.kt:57

```kotlin
@OptIn(ExperimentalCupertinoApi::class, ExperimentalMaterial3Api::class,
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveDatePicker(
    state : CupertinoDatePickerState,
    modifier: Modifier = Modifier,
    adaptation: AdaptationScope<CupertinoDatePickerAdaptation, MaterialDatePickerAdaptation>. () -> Unit = {}
)
```

## `AdaptiveDivider` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveDivider.kt:45

```kotlin
@Deprecated(
@Composable
@ExperimentalAdaptiveApi
fun AdaptiveDivider(
    modifier: Modifier = Modifier,
    adaptation: AdaptationScope<DividerAdaptation,DividerAdaptation>.() -> Unit = {}
)
```

## `AdaptiveHorizontalDivider` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveDivider.kt:53

```kotlin
@Composable
@ExperimentalAdaptiveApi
fun AdaptiveHorizontalDivider(
    modifier: Modifier = Modifier,
    adaptation: AdaptationScope<DividerAdaptation,DividerAdaptation>.() -> Unit = {}
)
```

## `AdaptiveVerticalDivider` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveDivider.kt:81

```kotlin
@Composable
@ExperimentalAdaptiveApi
fun AdaptiveVerticalDivider(
    modifier: Modifier = Modifier,
    adaptation: AdaptationScope<DividerAdaptation,DividerAdaptation>.() -> Unit = {}
)
```

## `AdaptiveIconButton` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveIconButton.kt:40

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoIconButtonAdaptation, MaterialIconButtonAdaptation>.() -> Unit = {},
    content: @Composable (() -> Unit)
)
```

## `AdaptiveFilledIconButton` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveIconButton.kt:78

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveFilledIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoIconButtonAdaptation, MaterialIconButtonAdaptation>.() -> Unit = {},
    content: @Composable (() -> Unit)
)
```

## `AdaptiveNavigationBar` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveNavigationBar.kt:48

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveNavigationBar(
    modifier: Modifier = Modifier,
    windowInsets: WindowInsets = NavigationBarDefaults.windowInsets,
    adaptation: AdaptationScope<CupertinoNavigationBarAdaptation, MaterialNavigationBarAdaptation>.() -> Unit = {},
    content: @Composable RowScope.() -> Unit
)
```

## `RowScope.AdaptiveNavigationBarItem` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveNavigationBar.kt:85

```kotlin
@OptIn(ExperimentalCupertinoApi::class, ExperimentalAdaptiveApi::class)
@Composable
fun RowScope.AdaptiveNavigationBarItem(
    selected: Boolean,
    onClick: () -> Unit,
    icon: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    label: @Composable (() -> Unit)? = null,
    alwaysShowLabel: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoNavigationBarItemAdaptation, MaterialNavigationBarItemAdaptation>.() -> Unit = {},
)
```

## `AdaptiveCircularProgressIndicator` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveProgressIndicator.kt:44

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveCircularProgressIndicator(
    modifier: Modifier = Modifier,
    adaptationScope: AdaptationScope<
        CupertinoCircularProgressIndicatorAdaptation,
        MaterialCircularProgressIndicatorAdaptation
    >.() -> Unit = {}
)
```

## `AdaptiveScaffold` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveScaffold.kt:45

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveScaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    snackbarHost: @Composable () -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    floatingActionButtonPosition: FabPosition = FabPosition.End,
    contentWindowInsets: WindowInsets = CupertinoScaffoldDefaults.contentWindowInsets,
    adaptation : AdaptationScope<ScaffoldAdaptation,ScaffoldAdaptation>.() -> Unit = {},
    content: @Composable (PaddingValues) -> Unit
)
```

## `AdaptiveScaffold` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveScaffold.kt:98

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveScaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    snackbarHost: @Composable () -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    floatingActionButtonPosition: FabPosition = FabPosition.End,
    containerColor: Color = Color.Unspecified,
    contentColor: Color = Color.Unspecified,
    contentWindowInsets: WindowInsets = CupertinoScaffoldDefaults.contentWindowInsets,
    content: @Composable (PaddingValues) -> Unit
)
```

## `AdaptiveSlider` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveSlider.kt:66

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveSlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    steps: Int = 0,
    onValueChangeFinished: (() -> Unit)? = null,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation : AdaptationScope<CupertinoSliderAdaptation, MaterialSliderAdaptation>.() -> Unit = {}
)
```

## `AdaptiveRangeSlider` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveSlider.kt:134

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveRangeSlider(
    value: ClosedFloatingPointRange<Float>,
    onValueChange: (ClosedFloatingPointRange<Float>) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    valueRange: ClosedFloatingPointRange<Float> = 0f..1f,
    steps: Int = 0,
    onValueChangeFinished: (() -> Unit)? = null,
    adaptation : AdaptationScope<CupertinoSliderAdaptation, MaterialSliderAdaptation>.() -> Unit = {}
)
```

## `AdaptiveSurface` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveSurface.kt:36

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveSurface(
    modifier: Modifier = Modifier,
    shape: Shape = RectangleShape,
    color: Color = Color.Unspecified,
    contentColor: Color = Color.Unspecified,
    shadowElevation : Dp = 0.dp,
    content: @Composable () -> Unit
)
```

## `AdaptiveSwitch` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveSwitch.kt:54

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveSwitch(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    thumbContent: @Composable (() -> Unit)? = null,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    adaptation: AdaptationScope<CupertinoSwitchAdaptation, MaterialSwitchAdaptation>.() -> Unit = {},
)
```

## `AdaptiveTheme` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:64

```kotlin
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveTheme(
    target: Theme = DefaultTheme,
    material: MaterialThemeSpec = MaterialThemeSpec.Default(),
    cupertino: CupertinoThemeSpec = CupertinoThemeSpec.Default(),
    content: @Composable () -> Unit,
)
```

## `AdaptiveTheme` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:134

```kotlin
@ExperimentalAdaptiveApi
@Deprecated(
@Composable
fun AdaptiveTheme(
    target: Theme = DefaultTheme,
    material: @Composable (content: @Composable () -> Unit) -> Unit = {
        MaterialTheme(content = it)
    },
    cupertino: @Composable (content: @Composable () -> Unit) -> Unit = {
        CupertinoTheme(content = it)
    },
    content: @Composable () -> Unit,
)
```

## `MaterialThemeSpec.copy` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:172

```kotlin
@Immutable
@ExperimentalAdaptiveApi
fun copy(
        colorScheme: MaterialColorScheme = this.colorScheme,
        shapes: MaterialShapes = this.shapes,
        typography: MaterialTypography = this.typography
    )
```

## `MaterialThemeSpec.toString` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:182

```kotlin

override fun toString(): String
```

## `MaterialThemeSpec.Companion.Default` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:188

```kotlin
@Composable
fun Default(
            colorScheme: MaterialColorScheme = MaterialTheme.colorScheme,
            shapes: MaterialShapes = MaterialTheme.shapes,
            typography: MaterialTypography = MaterialTheme.typography,
        )
```

## `CupertinoThemeSpec.copy` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:203

```kotlin
@Immutable
@ExperimentalAdaptiveApi
fun copy(
        colorScheme : CupertinoColorScheme = this.colorScheme,
        shapes : CupertinoShapes = this.shapes,
        typography : CupertinoTypography = this.typography
    )
```

## `CupertinoThemeSpec.toString` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:213

```kotlin

override fun toString(): String
```

## `CupertinoThemeSpec.Companion.Default` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTheme.kt:218

```kotlin
@Composable
fun Default(
            colorScheme: CupertinoColorScheme = CupertinoTheme.colorScheme,
            shapes: CupertinoShapes = CupertinoTheme.shapes,
            typography: CupertinoTypography = CupertinoTheme.typography,
        )
```

## `AdaptiveTopAppBar` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveTopAppBar.kt:43

```kotlin
@OptIn(ExperimentalMaterial3Api::class, ExperimentalCupertinoApi::class)
@ExperimentalAdaptiveApi
@Composable
fun AdaptiveTopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable (RowScope.() -> Unit) = {},
    windowInsets: WindowInsets = CupertinoTopAppBarDefaults.windowInsets,
    adaptation: AdaptationScope<CupertinoTopAppBarAdaptation, MaterialTopAppBarAdaptation>.() -> Unit = {}
)
```

## `AdaptiveWidget` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveWidget.kt:25

```kotlin
@Composable
@ExperimentalAdaptiveApi
fun AdaptiveWidget(
    material : @Composable () -> Unit,
    cupertino : @Composable () -> Unit
)
```

## `<C,M> AdaptiveWidget` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/AdaptiveWidget.kt:37

```kotlin
@Composable
@ExperimentalAdaptiveApi
fun <C,M> AdaptiveWidget(
    adaptation : Adaptation<C, M>,
    material : @Composable (M) -> Unit,
    cupertino : @Composable (C) -> Unit,
    adaptationScope : AdaptationScope<C, M>.() -> Unit,
)
```

## `Shapes.copy` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:34

```kotlin
@Immutable
fun copy(
        extraSmall: CornerBasedShape = this.extraSmall,
        small: CornerBasedShape = this.small,
        medium: CornerBasedShape = this.medium,
        large: CornerBasedShape = this.large,
        extraLarge: CornerBasedShape = this.extraLarge,
    )
```

## `Shapes.toMaterial` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:49

```kotlin

fun Shapes.toMaterial() : MaterialShapes
```

## `Shapes.toCupertino` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:57

```kotlin

fun Shapes.toCupertino() : CupertinoShapes
```

## `CupertinoShapes.toMaterial` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:65

```kotlin

fun CupertinoShapes.toMaterial() : MaterialShapes
```

## `CupertinoShapes.toAdaptive` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:73

```kotlin

fun CupertinoShapes.toAdaptive() : Shapes
```

## `MaterialShapes.toCupertino` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:81

```kotlin

fun MaterialShapes.toCupertino() : CupertinoShapes
```

## `MaterialShapes.toAdaptive` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Shapes.kt:89

```kotlin

fun MaterialShapes.toAdaptive() : Shapes
```

## `Color?.takeOrElse` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/Util.adaptive.kt:23

```kotlin

inline fun Color?.takeOrElse(block: () -> Color): Color
```

## `AdaptiveIcons.vector` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/icons/AdaptiveIcons.kt:88

```kotlin
@Composable
fun vector(
        material: () -> ImageVector,
        cupertino: () -> ImageVector
    ): ImageVector
```

## `AdaptiveIcons.painter` — cupertino-adaptive / commonMain

cupertino-adaptive/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/adaptive/icons/AdaptiveIcons.kt:105

```kotlin
@Composable
fun painter(
        material: () -> ImageVector,
        cupertino: () -> String
    ): Painter
```

## `Color.accessible` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/Accessibility.kt:46

```kotlin

fun Color.accessible(isDark : Boolean) : Color
```

## `rememberCupertinoHapticFeedback` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoHapticFeedback.kt:25

```kotlin
@Composable
expect fun rememberCupertinoHapticFeedback(): HapticFeedback
```

## `<T> cupertinoTween` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTween.kt:31

```kotlin

fun <T> cupertinoTween(
    durationMillis: Int = CupertinoTransitionDuration,
    delayMillis: Int = 0,
    easing: Easing = CupertinoEasing
) : TweenSpec<T>
```

## `SystemBarAppearance` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/SystemBarAppearance.kt:24

```kotlin
@Composable
@InternalCupertinoApi
expect fun SystemBarAppearance(dark: Boolean)
```

## `ColorScheme.copy` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/ColorScheme.kt:52

```kotlin
@Immutable
fun copy(
        accent : Color = this.accent,
        label : Color = this.label,
        secondaryLabel : Color = this.secondaryLabel,
        tertiaryLabel : Color = this.tertiaryLabel,
        quaternaryLabel : Color = this.quaternaryLabel,
        systemFill : Color = this.systemFill,
        secondarySystemFill : Color = this.secondarySystemFill,
        tertiarySystemFill : Color = this.tertiarySystemFill,
        quaternarySystemFill : Color = this.quaternarySystemFill,
        placeholderText : Color = this.placeholderText,
        separator : Color = this.separator,
        opaqueSeparator : Color = this.opaqueSeparator,
        link : Color = this.link,
        systemGroupedBackground : Color = this.systemGroupedBackground,
        secondarySystemGroupedBackground : Color = this.secondarySystemGroupedBackground,
        tertiarySystemGroupedBackground : Color = this.tertiarySystemGroupedBackground,
        systemBackground : Color = this.systemBackground,
        secondarySystemBackground : Color = this.secondarySystemBackground,
        tertiarySystemBackground : Color = this.tertiarySystemBackground,
    )
```

## `lightColorScheme` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/ColorScheme.kt:96

```kotlin

fun lightColorScheme(
    accent : Color = ColorSchemeTokens.lightAccent,
    label : Color = ColorSchemeTokens.lightLabel,
    secondaryLabel : Color = ColorSchemeTokens.lightSecondaryLabel,
    tertiaryLabel : Color = ColorSchemeTokens.lightTertiaryLabel,
    quaternaryLabel : Color = ColorSchemeTokens.lightQuaternaryLabel,
    systemFill : Color = ColorSchemeTokens.lightSystemFill,
    secondarySystemFill : Color = ColorSchemeTokens.lightSecondarySystemFill,
    tertiarySystemFill : Color = ColorSchemeTokens.lightTertiarySystemFill,
    quaternarySystemFill : Color = ColorSchemeTokens.lightQuaternarySystemFill,
    placeholderText : Color = ColorSchemeTokens.lightPlaceholderText,
    separator : Color = ColorSchemeTokens.lightSeparator,
    opaqueSeparator : Color =  ColorSchemeTokens.lightOpaqueSeparator,
    link : Color = ColorSchemeTokens.lightLink,
    systemGroupedBackground : Color = ColorSchemeTokens.lightSystemGroupedBackground,
    secondarySystemGroupedBackground : Color = ColorSchemeTokens.lightSecondarySystemGroupedBackground,
    tertiarySystemGroupedBackground : Color = ColorSchemeTokens.lightTertiarySystemGroupedBackground,
    systemBackground : Color = ColorSchemeTokens.lightSystemBackground,
    secondarySystemBackground : Color = ColorSchemeTokens.lightSecondarySystemBackground,
    tertiarySystemBackground : Color = ColorSchemeTokens.lightTertiarySystemBackground,
) : ColorScheme
```

## `darkColorScheme` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/ColorScheme.kt:139

```kotlin

fun darkColorScheme(
    accent : Color = ColorSchemeTokens.darkAccent,
    label : Color = ColorSchemeTokens.darkLabel,
    secondaryLabel : Color = ColorSchemeTokens.darkSecondaryLabel,
    tertiaryLabel : Color = ColorSchemeTokens.darkTertiaryLabel,
    quaternaryLabel : Color = ColorSchemeTokens.darkQuaternaryLabel,
    systemFill : Color = ColorSchemeTokens.darkSystemFill,
    secondarySystemFill : Color = ColorSchemeTokens.darkSecondarySystemFill,
    tertiarySystemFill : Color = ColorSchemeTokens.darkTertiarySystemFill,
    quaternarySystemFill : Color = ColorSchemeTokens.darkQuaternarySystemFill,
    placeholderText : Color = ColorSchemeTokens.darkPlaceholderText,
    separator : Color = ColorSchemeTokens.darkSeparator,
    opaqueSeparator : Color =  ColorSchemeTokens.darkOpaqueSeparator,
    link : Color = ColorSchemeTokens.darkLink,
    systemGroupedBackground : Color = ColorSchemeTokens.darkSystemGroupedBackground,
    secondarySystemGroupedBackground : Color = ColorSchemeTokens.darkSecondarySystemGroupedBackground,
    tertiarySystemGroupedBackground : Color = ColorSchemeTokens.darkTertiarySystemGroupedBackground,
    systemBackground : Color = ColorSchemeTokens.darkSystemBackground,
    secondarySystemBackground : Color = ColorSchemeTokens.darkSecondarySystemBackground,
    tertiarySystemBackground : Color = ColorSchemeTokens.darkTertiarySystemBackground,
) : ColorScheme
```

## `isInitializedCupertinoTheme` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/ColorScheme.kt:191

```kotlin
@Composable
@InternalCupertinoApi
fun isInitializedCupertinoTheme() : Boolean
```

## `CupertinoColors.systemRed` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:187

```kotlin

fun CupertinoColors.systemRed(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemOrange` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:195

```kotlin

fun CupertinoColors.systemOrange(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemYellow` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:204

```kotlin

fun CupertinoColors.systemYellow(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGreen` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:214

```kotlin

fun CupertinoColors.systemGreen(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemMint` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:227

```kotlin

fun CupertinoColors.systemMint(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemTeal` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:241

```kotlin

fun CupertinoColors.systemTeal(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemCyan` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:254

```kotlin

fun CupertinoColors.systemCyan(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemBlue` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:267

```kotlin

fun CupertinoColors.systemBlue(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemIndigo` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:280

```kotlin

fun CupertinoColors.systemIndigo(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemPurple` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:293

```kotlin

fun CupertinoColors.systemPurple(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemPink` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:307

```kotlin

fun CupertinoColors.systemPink(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemBrown` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:318

```kotlin

fun CupertinoColors.systemBrown(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:331

```kotlin

fun CupertinoColors.systemGray(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray2` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:342

```kotlin

fun CupertinoColors.systemGray2(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray3` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:355

```kotlin

fun CupertinoColors.systemGray3(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray4` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:368

```kotlin

fun CupertinoColors.systemGray4(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray5` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:381

```kotlin

fun CupertinoColors.systemGray5(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray6` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:394

```kotlin

fun CupertinoColors.systemGray6(
    dark: Boolean,
    highContrast : Boolean = Accessibility.isHighContrastEnabled
)
```

## `CupertinoColors.systemGray7` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:407

```kotlin

fun CupertinoColors.systemGray7(dark: Boolean)
```

## `CupertinoColors.systemGray8` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/CupertinoColors.kt:411

```kotlin

fun CupertinoColors.systemGray8(dark: Boolean)
```

## `Shapes.copy` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/Shapes.kt:37

```kotlin

fun copy(
        extraSmall: CornerBasedShape = this.extraSmall,
        small: CornerBasedShape = this.small,
        medium: CornerBasedShape = this.medium,
        large: CornerBasedShape = this.large,
        extraLarge: CornerBasedShape = this.extraLarge,
    )
```

## `Typography.copy` — cupertino-core / commonMain

cupertino-core/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/theme/Typography.kt:76

```kotlin

fun copy(
        largeTitle : TextStyle = this.largeTitle,
        title1 : TextStyle = this.title1,
        title2 : TextStyle = this.title2,
        title3 : TextStyle = this.title3,
        headline : TextStyle = this.headline,
        body : TextStyle = this.body,
        callout : TextStyle = this.callout,
        subhead : TextStyle = this.subhead,
        footnote : TextStyle = this.footnote,
        caption1 : TextStyle = this.caption1,
        caption2 : TextStyle = this.caption2,
    )
```

## `UIColor.toComposeColor` — cupertino-core / iosMain

cupertino-core/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCoreUtil.kt:30

```kotlin
@OptIn(ExperimentalForeignApi::class)
fun UIColor.toComposeColor() : Color
```

## `Color.toUIColor` — cupertino-core / iosMain

cupertino-core/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoCoreUtil.kt:53

```kotlin

fun Color.toUIColor() : UIColor
```

## `SystemBarAppearance` — cupertino-core / iosMain

cupertino-core/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/SystemBarAppearance.ios.kt:35

```kotlin
@Composable
@InternalCupertinoApi
actual fun SystemBarAppearance(dark: Boolean)
```

## `SystemBarAppearance` — cupertino-core / iosMain

cupertino-core/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/SystemBarAppearance.ios.kt:47

```kotlin
@Composable
@InternalCupertinoApi
fun SystemBarAppearance(dark: Boolean, viewController: UIViewController)
```

## `rememberCupertinoHapticFeedback` — cupertino-core / iosMain

cupertino-core/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/UIKitHapticFeedback.kt:32

```kotlin
@Composable
actual fun rememberCupertinoHapticFeedback() : HapticFeedback
```

## `rememberCupertinoHapticFeedback` — cupertino-core / nonIosMain

cupertino-core/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoHapticFeedback.kt:25

```kotlin
@Composable
actual fun rememberCupertinoHapticFeedback(): HapticFeedback
```

## `SystemBarAppearance` — cupertino-core / nonIosMain

cupertino-core/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/SystemBarAppearance.nonIos.kt:24

```kotlin
@Composable
@InternalCupertinoApi
actual fun SystemBarAppearance(dark: Boolean)
```

## `<C : Any,T : Any> cupertinoPredictiveBackAnimation` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/CupertinoPredictiveBack.kt:47

```kotlin
@ExperimentalDecomposeApi
@Composable
fun <C : Any,T : Any> cupertinoPredictiveBackAnimation(
    backHandler: BackHandler,
    onBack : () -> Unit,
    fallbackAnimation: StackAnimation<C, T>? = stackAnimation(
        animator = cupertinoStackAnimator(),
        disableInputDuringAnimation = true
    )
) : StackAnimation<C,T>
```

## `cupertinoPredictiveBackAnimatable` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/CupertinoPredictiveBack.kt:67

```kotlin
@ExperimentalDecomposeApi
fun cupertinoPredictiveBackAnimatable(
    initialBackEvent: BackEvent
) : PredictiveBackAnimatable
```

## `cupertinoStackAnimator` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/CupertinoPredictiveBack.kt:102

```kotlin

fun cupertinoStackAnimator(
    animationSpec: FiniteAnimationSpec<Float> = cupertinoTween(
        durationMillis = 500
    )
) : StackAnimator
```

## `Modifier.cupertinoPredictiveEnter` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/CupertinoPredictiveBack.kt:129

```kotlin

fun Modifier.cupertinoPredictiveEnter(progress: () -> Float) : Modifier
```

## `Modifier.cupertinoPredictiveExit` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/CupertinoPredictiveBack.kt:145

```kotlin

fun Modifier.cupertinoPredictiveExit(progress: () -> Float) : Modifier
```

## `<C : Any, T : Any> NativeChildren` — cupertino-decompose / commonMain

cupertino-decompose/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/NativeChildren.kt:40

```kotlin
@Composable
expect fun <C : Any, T : Any> NativeChildren(
    stack: Value<ChildStack<C, T>>,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    animation: StackAnimation<C, T>? = null,
    content: @Composable (child: Child.Created<C, T>) -> Unit,
)
```

## `<C : Any, T : Any> NativeChildren` — cupertino-decompose / iosMain

cupertino-decompose/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/NativeChildren.ios.kt:29

```kotlin
@Composable
actual fun <C : Any, T : Any> NativeChildren(
    stack: Value<ChildStack<C, T>>,
    onBack: () -> Unit,
    modifier: Modifier,
    animation: StackAnimation<C, T>?,
    content: @Composable (child: Child.Created<C, T>) -> Unit,
)
```

## `<C : Any, T : Any> UIKitChildren` — cupertino-decompose / iosMain

cupertino-decompose/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/UIKitChildren.kt:65

```kotlin
@OptIn(ExperimentalComposeApi::class)
@Composable
fun <C : Any, T : Any> UIKitChildren(
    stack: Value<ChildStack<C, T>>,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    configuration : ComposeUIViewControllerConfiguration.() -> Unit = {
        onFocusBehavior = OnFocusBehavior.DoNothing
        platformLayers = false
    },
    content: @Composable (child: Child.Created<C, T>) -> Unit,
)
```

## `<C : Any, T : Any> NativeChildren` — cupertino-decompose / nonIosMain

cupertino-decompose/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/decompose/NativeChildren.nonIos.kt:30

```kotlin
@Composable
actual fun <C : Any, T : Any> NativeChildren(
    stack: Value<ChildStack<C, T>>,
    onBack: () -> Unit,
    modifier: Modifier,
    animation: StackAnimation<C, T>?,
    content: @Composable (child: Child.Created<C, T>) -> Unit,
)
```

## `CupertinoDatePickerNative` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePickerNative.kt:28

```kotlin
@Composable
@ExperimentalCupertinoApi
expect fun CupertinoDatePickerNative(
    state: CupertinoDatePickerState,
    modifier: Modifier = Modifier,
    style: DatePickerStyle = DatePickerStyle.Wheel(),
    containerColor : Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    }
)
```

## `CupertinoDateTimePickerNative` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePickerNative.kt:28

```kotlin
@Composable
@ExperimentalCupertinoApi
expect fun CupertinoDateTimePickerNative(
    state: CupertinoDateTimePickerState,
    modifier: Modifier = Modifier,
    style: DatePickerStyle = DatePickerStyle.Wheel(),
    containerColor : Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    }
)
```

## `CupertinoAlertDialogNative` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:44

```kotlin
@Composable
expect fun CupertinoAlertDialogNative(
    onDismissRequest : () -> Unit,
    title: String?,
    message: String? = null,
    containerColor : Color = CupertinoColors.systemGray7,
    shape: Shape = CupertinoDialogsDefaults.Shape,
    properties: DialogProperties = DialogProperties(),
    buttonsOrientation: Orientation = Orientation.Horizontal,
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `CupertinoActionSheetNative` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:69

```kotlin
@Composable
expect fun CupertinoActionSheetNative(
    visible : Boolean,
    onDismissRequest : () -> Unit,
    title : String? = null,
    message : String? = null,
    containerColor : Color = CupertinoColors.systemGray7,
    secondaryContainerColor : Color = CupertinoTheme.colorScheme.tertiarySystemBackground,
    properties: DialogProperties = DialogProperties(),
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `NativeAlertDialogActionsScope.action` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:86

```kotlin

fun action(
        onClick : () -> Unit,
        style : AlertActionStyle = AlertActionStyle.Default,
        enabled : Boolean = true,
        title : String
    )
```

## `NativeAlertDialogActionsScope.default` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:97

```kotlin

fun NativeAlertDialogActionsScope.default(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : String
)
```

## `NativeAlertDialogActionsScope.destructive` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:111

```kotlin

fun NativeAlertDialogActionsScope.destructive(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : String
)
```

## `NativeAlertDialogActionsScope.cancel` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.kt:125

```kotlin

fun NativeAlertDialogActionsScope.cancel(
    onClick : () -> Unit,
    enabled : Boolean = true,
    title : String
)
```

## `CupertinoTimePickerNative` — cupertino-native / commonMain

cupertino-native/src/commonMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePickerNative.kt:29

```kotlin
@Composable
@ExperimentalCupertinoApi
expect fun CupertinoTimePickerNative(
    state: CupertinoTimePickerState,
    modifier: Modifier = Modifier,
    height : Dp = CupertinoPickerDefaults.Height,
    containerColor : Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    }
)
```

## `CupertinoColorPickerNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoColorPickerNative.ios.kt:30

```kotlin
@Composable
@ExperimentalCupertinoApi
fun CupertinoColorPickerNative(
    color : Color,
    onColorChanged : (Color) -> Unit,
    onDismissRequest : () -> Unit,
    supportsAlpha : Boolean = true,
)
```

## `CupertinoDatePickerNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePickerNative.ios.kt:57

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoDatePickerNative(
    state: CupertinoDatePickerState,
    modifier: Modifier,
    style: DatePickerStyle,
    containerColor : Color,
)
```

## `CupertinoDateTimePickerNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePickerNative.ios.kt:30

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoDateTimePickerNative(
    state: CupertinoDateTimePickerState,
    modifier: Modifier,
    style: DatePickerStyle,
    containerColor : Color
)
```

## `CupertinoAlertDialogNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.ios.kt:43

```kotlin
@Composable
@NonRestartableComposable
actual fun CupertinoAlertDialogNative(
    onDismissRequest : () -> Unit,
    title: String?,
    message: String?,
    containerColor : Color,
    shape: Shape,
    properties: DialogProperties,
    buttonsOrientation: Orientation,
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `CupertinoActionSheetNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.ios.kt:61

```kotlin
@Composable
actual fun CupertinoActionSheetNative(
    visible : Boolean,
    onDismissRequest : () -> Unit,
    title : String?,
    message : String?,
    containerColor : Color,
    secondaryContainerColor : Color,
    properties: DialogProperties,
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `<T> CupertinoPickerNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoPickerNative.kt:33

```kotlin
@Composable
@ExperimentalCupertinoApi
fun <T> CupertinoPickerNative(
    state: CupertinoPickerState,
    items: List<T>,
    modifier: Modifier = Modifier,
    height: Dp = CupertinoPickerDefaults.Height,
    containerColor: Color = LocalContainerColor.current.takeOrElse {
        CupertinoTheme.colorScheme.secondarySystemGroupedBackground
    },
    enabled : Boolean = true,
    content: (T) -> String
)
```

## `CupertinoTimePickerNative` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePickerNative.ios.kt:37

```kotlin
@OptIn(InternalCupertinoApi::class)
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoTimePickerNative(
    state: CupertinoTimePickerState,
    modifier: Modifier,
    height : Dp,
    containerColor : Color
)
```

## `CupertinoIcons.named` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/NativeIcons.kt:43

```kotlin
@Composable
fun CupertinoIcons.named(systemName : String) : Painter
```

## `ImageBitmap.Companion.systemImage` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/NativeIcons.kt:56

```kotlin

fun ImageBitmap.Companion.systemImage(systemName: String) : ImageBitmap
```

## `UIImage.toComposeImageBitmap` — cupertino-native / iosMain

cupertino-native/src/iosMain/kotlin/io/github/alexzhirkevich/cupertino/NativeIcons.kt:64

```kotlin
@OptIn(ExperimentalForeignApi::class)
fun UIImage.toComposeImageBitmap() : ImageBitmap
```

## `CupertinoDatePickerNative` — cupertino-native / nonIosMain

cupertino-native/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDatePickerNative.nonIos.kt:26

```kotlin
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoDatePickerNative(
    state: CupertinoDatePickerState,
    modifier: Modifier,
    style: DatePickerStyle,
    containerColor : Color
)
```

## `CupertinoDateTimePickerNative` — cupertino-native / nonIosMain

cupertino-native/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDateTimePickerNative.nonIos.kt:26

```kotlin
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoDateTimePickerNative(
    state: CupertinoDateTimePickerState,
    modifier: Modifier,
    style: DatePickerStyle,
    containerColor : Color
)
```

## `CupertinoAlertDialogNative` — cupertino-native / nonIosMain

cupertino-native/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.nonIos.kt:28

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@Composable
actual fun CupertinoAlertDialogNative(
    onDismissRequest : () -> Unit,
    title: String?,
    message: String?,
    containerColor : Color,
    shape: Shape,
    properties: DialogProperties,
    buttonsOrientation: Orientation,
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `CupertinoActionSheetNative` — cupertino-native / nonIosMain

cupertino-native/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoDialogsNative.nonIos.kt:52

```kotlin
@OptIn(ExperimentalCupertinoApi::class)
@Composable
actual fun CupertinoActionSheetNative(
    visible : Boolean,
    onDismissRequest : () -> Unit,
    title : String?,
    message : String?,
    containerColor : Color,
    secondaryContainerColor : Color,
    properties: DialogProperties,
    buttons : NativeAlertDialogActionsScope.() -> Unit
)
```

## `CupertinoTimePickerNative` — cupertino-native / nonIosMain

cupertino-native/src/nonIosMain/kotlin/io/github/alexzhirkevich/cupertino/CupertinoTimePickerNative.nonIos.kt:27

```kotlin
@Composable
@ExperimentalCupertinoApi
actual fun CupertinoTimePickerNative(
    state: CupertinoTimePickerState,
    modifier: Modifier,
    height : Dp,
    containerColor : Color
)
```