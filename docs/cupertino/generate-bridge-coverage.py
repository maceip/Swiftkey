#!/usr/bin/env python3
"""Regenerate the callable-level Swift bridge disposition from the pinned inventory."""
import csv
import json
import re
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[2]
directory = root / 'docs/cupertino'
sources = root / 'SwiftUICore/Sources/SwiftUICore/Cupertino'
catalog_source = (sources / 'CupertinoCatalogView.swift').read_text()
surfaces = set(re.findall(r'^    case \w+ = "([^"]+)"', catalog_source, re.M))
wrappers = {}
for path in sources.glob('*.swift'):
    if path.name == 'CupertinoCatalogView.swift':
        continue
    text = path.read_text()
    for hit in re.finditer(r'CupertinoComponent\("([^"]+)"', text):
        declarations = list(re.finditer(r'public (?:struct|enum) (\w+)', text[:hit.start()]))
        if declarations:
            wrappers.setdefault(hit.group(1), declarations[-1].group(1))
wrappers.update({
    'Surface': 'CupertinoComponent("Surface", …)',
    'LazyListScope.section': 'CupertinoLazySection(sticky: false, …)',
    'LazyListScope.stickySection': 'CupertinoLazySection(sticky: true, …)',
    'LazySectionScope.items': 'CupertinoLazyItems',
    'CupertinoText': 'CupertinoText (String / CupertinoAnnotatedText)',
    'CupertinoIcon': 'CupertinoIcon (CupertinoSymbol / CupertinoIconResource)',
    'CupertinoLinkIcon': 'CupertinoLinkIcon (CupertinoSymbol / CupertinoIconResource)',
    'Modifier.haze': 'View.cupertinoHaze',
    'Modifier.cupertinoPickerIndicator': 'View.cupertinoPickerIndicator',
    'Modifier.sectionContainerBackground': 'View.cupertinoSectionContainerBackground',
    'Modifier.cupertinoPredictiveEnter': 'View.cupertinoPredictiveEnter',
    'Modifier.cupertinoPredictiveExit': 'View.cupertinoPredictiveExit',
    'TabRowDefaults.Modifier.tabIndicatorOffset': 'View.cupertinoTabIndicatorOffset',
})
for prefix in ('AlertDialogActionsScope', 'NativeAlertDialogActionsScope'):
    for action in ('action', 'default', 'destructive', 'cancel'):
        wrappers[f'{prefix}.{action}'] = f'CupertinoAlertAction(kind: .{action}, native: {str(prefix.startswith("Native")).lower()}, …)'
for name in surfaces:
    if name.startswith(('CupertinoBottomSheetDefaults.', 'CupertinoDropdownMenuDefaults.', 'CupertinoNavigationBarDefaults.', 'CupertinoTopAppBarDefaults.', 'CupertinoSearchTextFieldDefaults.', 'CupertinoSectionDefaults.', 'CupertinoSliderDefaults.', 'CupertinoTextFieldDefaults.')):
        wrappers[name] = name.rsplit('.', 1)[0] + '.' + name.rsplit('.', 1)[1][0].upper() + name.rsplit('.', 1)[1][1:]

state_families = [
    ('CupertinoSheetState', 'Binding<CupertinoSheetValue>, CupertinoCommand<CupertinoSheetCommand>, CupertinoPresentationDetent'),
    ('CupertinoDatePickerState', 'Binding<CupertinoDateSelection>'),
    ('CupertinoDateTimePickerState', 'Binding<CupertinoDateTimeSelection>'),
    ('CupertinoTimePickerState', 'Binding<CupertinoTimeSelection>'),
    ('CupertinoPickerState', 'CupertinoWheelPicker selectedItem: Binding<Int>'),
    ('CupertinoSwipeBoxState', 'Binding<CupertinoSwipeValue>, CupertinoCommand<CupertinoSwipeCommand>'),
    ('SectionState', 'CupertinoSection / CupertinoLazySection collapsed: Binding<Bool>'),
]

def disposition(row):
    api = re.sub(r'^<.*?>\s+', '', row['api'])
    if row['source_set'] == 'iosMain':
        return 'unsupported-platform', 'CupertinoUIKitSurface / platform capability documentation', None, 'UIKit-only source; no Android or desktop substitution is advertised.'
    if api in surfaces:
        return 'visual-surface', wrappers.get(api, api), api, 'Typed Swift view or modifier projection plus named slots; not a promise that every Kotlin parameter has a Swift equivalent.'
    if api.startswith('SharedSwipeBoxController.'):
        return 'state-projection', 'CupertinoSharedSwipeBoxController(collapseCommandID:content:)', 'SharedSwipeBoxController', 'The composition owns a real shared upstream controller; command IDs trigger collapse once.'
    if api.startswith('remember'):
        state = api.removeprefix('remember')
        if state == 'CupertinoIndication':
            return 'native-helper', 'Upstream Cupertino controls', None, 'Actual upstream indication remains internal; a Kotlin Indication object cannot cross the JSON bridge.'
        if state == 'CupertinoBottomSheetScaffoldState':
            return 'state-projection', 'CupertinoBottomSheetScaffold', None, 'Native remember state is retained in composition; Swift owns the sheet value and explicit commands.'
        if state == 'CupertinoSearchTextFieldState':
            return 'state-projection', 'CupertinoSearchTextField + Binding<String>', None, 'Focus/interaction state remains in the actual native text field; Swift receives text and explicit submit events.'
        for family, swift in state_families:
            if state == family:
                return 'state-projection', swift, None, 'Renderer creates the real remembered state; Swift values update it and receive typed callbacks.'
    for family, swift in state_families:
        if api.startswith(family + '.'):
            low_level = any(x in api for x in ('requireOffset', 'dispatchRawDelta', '.scroll', 'selectedItemState', 'currentSelectedItem', 'selectedItemIndex', '.Saver'))
            if low_level:
                return 'native-helper', swift, None, 'Compose scroll geometry, saver, and live state object remain native. Swift selects by value/index; raw suspension and offset APIs are not separately exported.'
            return 'state-projection', swift, None, 'Selection/collapse/sheet/swipe mutations map to Swift bindings or explicit command props. Native state identity is retained.'
    if api == 'String.sectionTitle':
        return 'value-projection', 'String.cupertinoSectionTitle(style:)', None, 'Same uppercase rule with an explicit style; Swift does not read Compose locals.'
    if api.startswith(('AdaptationScope.', 'Adaptation.')):
        return 'value-projection', 'CupertinoAdaptation + CupertinoComponent.adaptation', None, 'JSON cupertino/material overrides for supported renderer options; arbitrary Kotlin adaptation lambdas are not serialized.'
    if api in ('cupertinoPredictiveBackAnimation', 'cupertinoPredictiveBackAnimatable', 'cupertinoStackAnimator'):
        return 'native-helper', 'CupertinoNativeChildren(animation:animationDurationMillis:)', 'NativeChildren', 'Real upstream animator and Decompose lifecycles are selected natively; Swift supplies entries and responds to onBack.'
    if api.startswith(('PresentationDetent.', 'CupertinoSheetValue.', 'PresentationStyle.', 'DatePickerStyle.')):
        return 'value-projection', 'CupertinoPresentationDetent / CupertinoSheetValue / CupertinoDatePickerStyle; component props', None, 'Swift values describe the options; density conversion and Compose value-object methods remain in the upstream renderer.'
    if api.startswith('CupertinoPickerDefaults.indicator'):
        return 'native-helper', 'CupertinoWheelPicker indicatorStyle prop; View.cupertinoPickerIndicator', None, 'Upstream draw factories execute natively; drawing lambdas are not JSON values.'
    if api in ('AdaptiveIcons.vector', 'AdaptiveIcons.painter'):
        return 'value-projection', 'CupertinoSymbol adaptive_* cases, CupertinoIcon', 'CupertinoIcon', 'All 46 adaptive registry properties select actual upstream vectors under AdaptiveTheme.'
    if api in ('Color?.takeOrElse', 'Color.accessible'):
        return 'native-helper', 'Optional Color / upstream adaptive theme', None, 'Default and accessibility-dependent color resolution remains native; theme colors can be supplied as light/dark PropValue.color pairs.'
    if api == 'isInitializedCupertinoTheme':
        return 'native-helper', 'CupertinoTheme / AdaptiveTheme', None, 'Renderer consumes Compose-local theme availability; no false Swift-side mirror of native locals is exposed.'
    if api in ('calculatePagerHeight', 'LazyListState.isTopBarTransparent', 'cupertinoTranslucentTopBarColor', 'cupertinoTranslucentBottomBarColor', 'HazeDefaults.tint', 'cupertinoTween'):
        return 'native-helper', 'Upstream picker / bars / haze / animation', None, 'Upstream layout, scroll, tint, or timing helper stays native. Swift passes supported options rather than serializing executable Kotlin objects.'
    if api.startswith(('CupertinoColors.', 'ColorScheme.', 'Shapes.', 'Typography.', 'CupertinoShapes.', 'MaterialShapes.', 'MaterialThemeSpec.', 'CupertinoThemeSpec.')) or api in ('lightColorScheme', 'darkColorScheme'):
        return 'theme-projection', 'CupertinoThemeOptions, CupertinoColorRole, CupertinoShapeSize, Font', None, 'Real light/dark/adaptive defaults remain native; Swift overrides semantic colors, shape radii, and typography family. This is not a duplicate Kotlin theme-object API.'
    if 'Colors.' in api or 'Defaults.' in api or api.startswith(('SliderPositions.', 'TabPosition.', 'FabPosition.')):
        return 'native-helper', 'Typed options and CupertinoComponent props / upstream defaults', None, 'Default factories, equality/hash/copy, measured positions, and color providers execute natively. Unsupported function/object parameters are not emulated.'
    raise ValueError('Unclassified public API: ' + api)

rows = []
for index, source in enumerate(csv.DictReader((directory / 'component-matrix.csv').open()), start=1):
    status, swift, native, note = disposition(source)
    rows.append(dict(inventoryRow=index, module=source['module'], sourceSet=source['source_set'], api=source['api'],
                     source=source['source'], line=int(source['line']), disposition=status, swift=swift, nativeSurface=native, note=note))
assert len(rows) == 325
assert sum(row['sourceSet'] == 'commonMain' for row in rows) == 316
counts = dict(sorted(Counter(row['disposition'] for row in rows).items()))
(directory / 'bridge-coverage.json').write_text(json.dumps(dict(upstreamCommit='f66875aa6f3848b30c38e42a89fc99c9ac24a585', inventoryRows=325, sharedRows=316, iosOnlyRows=9, catalogSurfaces=len(surfaces), symbols=879, dispositions=counts, rows=rows), indent=2) + '\n')
intro = '''# Swift Cupertino bridge coverage

This is a callable-by-callable disposition of the pinned upstream inventory: **316 shared callable rows and 9 UIKit-only rows**. Overloads and value-object helpers are separate inventory rows; they are not separate widgets. The catalog has **SURFACES distinct bridge surfaces**, including named-slot and scoped adapters, and the symbol registry has **833 Cupertino + 46 adaptive names**.

The bridge invokes the vendored Compose implementations. Swift exports typed views, bindings, structured event values, theme options, commands, and named slots. It is **not an arbitrary Kotlin ABI**: `InteractionSource`, coroutine/scroll scopes, `DrawScope` lambdas, state savers, measured positions, arbitrary Compose `Shape`/`Brush`/animation instances, and executable adaptation lambdas stay in Kotlin. A generic component permits renderer-supported options; a prop being serializable does not imply the renderer supports it.

`visual-surface` means a concrete renderer dispatch plus Swift view/modifier projection. `state-projection` and `value-projection` preserve the relevant state/value operation across the bridge. `native-helper` and `theme-projection` identify behavior supplied by real upstream internals, with explicit limits in each row. `unsupported-platform` means the upstream API is UIKit-only and is not faked on Android or desktop.

## Wire contract

- A component emits `Composable` with exact `props.name`; overloads use distinct prop/value representations.
- Named children emit `CupertinoSlot`, `props.name`, and ordinary rendered Swift children. Scoped entries stay in their upstream parent and retain builder order.
- Action IDs use stable `/action/<name>` paths, never dictionary ordinals. Scalar events use the matching callback type. Range, editing, date, time, sheet, and swipe events use bounded JSON strings.
- Dates use signed 64-bit milliseconds in JSON. Editing ranges use UTF-16 offsets. Bindings reject malformed/out-of-range events; disabled/read-only typed controls gate writes.
- Lazy section items carry `count`, `keys`, `contentVersion`, and a real on-demand `itemProvider`; their rows are not eager placeholder widgets.
- Sheet/swipe/haptic commands require identifiers so recomposition does not repeat effects. UIKit-specific haptic types remain unsupported on Android. Desktop has no system-bar window controls.

## Default-slot contracts

The twelve typed default helpers expose only parameters their actual native implementations consume. Dividers, picker-leading icon, and label chevron have no actions. The search cancel button takes `Binding<String>` and handles native `onValueChange("")`; the clear button has a real click callback. Slider thumb/track helpers reuse their parent slider's colors, measured positions, and interaction source; only thumb dimensions and enabled state are local. The section picker label is passive and exposes expanded state, shape, colors, and title. DecorationBox requires an `innerTextField` slot and accepts its actual enabled/error/alignment and text-field color roles. Use standard Swift modifiers for supported layout decoration; arbitrary Kotlin objects remain native.

## Runnable example

```swift
import SwiftUICore

struct Preferences: View {
    @State private var enabled = true
    @State private var name = "Phone"
    @State private var volume = 0.5

    var body: some View {
        CupertinoTheme {
            VStack(spacing: 16) {
                CupertinoSwitch(checked: $enabled)
                CupertinoTextField(value: $name, slots: [
                    CupertinoSlot("placeholder") { CupertinoText("Device name") }
                ])
                CupertinoSlider(value: $volume)
                CupertinoButton("Save", enabled: enabled) { /* application action */ }
            }
        }
    }
}
```

`CupertinoCatalogView(surface: .cupertinoButton, showsPicker: true)` is public. The Android app has a **Cupertino component catalog** entry and a return action; this does not mutate identity or pairing state. The existing general component catalog also links it. `initiallyPresented: true` is available for fixture/render tests.

Alert visibility is owned in Swift: the four typed alert wrappers emit the native node only while their `visible` binding is true. A raw `CupertinoComponent("CupertinoAlertDialog", …)` follows upstream conditional-composition semantics; a `visible` prop does not hide it. Action sheets have a real upstream `visible` parameter and remain composed for their transition.

Scoped menu contracts differ intentionally: `CupertinoSectionDropdownMenu` takes a `menu` slot containing an actual `CupertinoDropdownMenu`, whose content contains ordered menu entries. `CupertinoLazyDropdownMenu` already creates its native dropdown; its `content` slot takes menu entries directly. Putting a bare `CupertinoMenuAction` into an ordinary composable slot has no menu receiver and is invalid. The catalog and regression tests cover both forms.

The catalog uses a bounded preview region rather than nesting whole-screen scaffolds and lazy containers in a vertical scroll view. Hosts should likewise give scaffolds and sheet containers finite height.

## Verification and scope limits

Swift tests validate all catalog trees, stable callback identities/fresh captures, ordered action builders, editing/range/date validation, disabled gates, command state, and actual lazy row providers. The optional `CUPERTINO_FIXTURE_DIR` test environment variable exports both closed/open actual Swift trees. Static exported lazy providers require a host callback registry to resolve rows. These evaluator tests alone do not prove native layout or physical haptics/camera behavior; native renderer and hardware evidence are recorded separately.

Specialized parameters remain **projections**: arbitrary pager text-style objects, custom draw lambdas, animation specs, rich Compose interaction objects, generic adaptive lambdas, and direct native-state methods are not accepted as Swift closures. Use supported explicit properties/named slots or extend the Kotlin adapter. All UIKit-only APIs are listed below. `Surface` is the upstream legacy alias and is accessible through the explicit generic component; prefer typed `CupertinoSurface` in new code.

Regenerate this file and the machine-readable map with `python3 docs/cupertino/generate-bridge-coverage.py` from `AndroidSwiftUI`. The source inventory is `component-matrix.csv`; detailed parameter/default signatures remain there.

## Callable map

| # | Module / API | Disposition | Swift API or owner | Notes |
|---|---|---|---|---|
'''.replace('SURFACES',str(len(surfaces)))
def cell(s): return s.replace('|','\\|').replace('\n',' ')
lines = [intro]
for row in rows:
    lines.append('| ' + ' | '.join(cell(str(x)) for x in [row['inventoryRow'], row['module'] + ' / `' + row['api'] + '`', row['disposition'], '`' + row['swift'] + '`', row['note']]) + ' |\n')
(directory / 'BRIDGE-COVERAGE.md').write_text(''.join(lines))
print(json.dumps(dict(catalogSurfaces=len(surfaces), **counts), sort_keys=True))
