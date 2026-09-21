# Compose Cupertino in AndroidSwiftUI

AndroidSwiftUI vendors the complete [Compose Cupertino](https://github.com/alexzhirkevich/compose-cupertino) source at `f66875aa6f3848b30c38e42a89fc99c9ac24a585`. All six modules are built locally for Android and desktop: core, widgets, native fallbacks, adaptive widgets, Decompose navigation, and extended icons. The upstream examples, documentation, and license notices are retained under `vendor/compose-cupertino`; separate build scripts under `gradle/cupertino` align the modules with this checkout's toolchain.

## Use from Swift

Import `SwiftUICore`. `CupertinoCatalogView()` is the interactive component catalog; `CupertinoSurfaceName.allCases` enumerates its distinct visual surfaces. `CupertinoSymbol.allCases` enumerates the shared icon names.

Typed wrappers use Swift bindings for editable values. `CupertinoComponent` is the lower-level bridge for supported upstream options, named slots, and typed callbacks:

```swift
CupertinoComponent("CupertinoButton",
    actions: ["onClick": .void { print("Pair device") }],
    slots: [CupertinoSlot("content") { Text("Pair device") }])
```

The renderer calls upstream Compose implementations. Application registrations in `ComposableRegistry` can override an individual name. Unknown names and invalid scope usage produce visible diagnostics.

## State and content contract

- A component is a `Composable` node with `props.name` matching the upstream name. A scope member retains its prefix, such as `SectionScope.SectionLink`.
- Slots are `CupertinoSlot` child nodes with exact parameter names. Slot identity and callback identity use names, so adding an optional leading slot or action does not reassign other callbacks.
- Scalars and colors use the existing typed bridge. Adaptive colors are `[lightARGB, darkARGB]`. Structured option objects use canonical JSON strings; Kotlin also accepts JSON objects/arrays.
- Text editing values preserve text, selection, and composing range. String echoes preserve the IME cursor and composing region. IME callbacks retain their actual action names.
- Local edits remain authoritative while earlier Swift echoes are in flight, including regular and lazy section fields. Android modal dialogs own window focus; bounded sheet previews clip hidden content outside their frame.
- Date callbacks carry 64-bit UTC milliseconds in JSON, avoiding truncation through the integer callback channel. Time and date-time callbacks carry hour/minute fields. Dates use UTC calendar days.
- Sheet/swipe commands use a changing `commandID`; changing unrelated props does not replay a command. Synchronous transition vetoes use an `allowedValues` whitelist because a cross-runtime notification cannot synchronously return a Boolean.
- Lazy sections use the existing Swift item provider, stable row keys, and content version. Swift row rendering occurs on demand for visible items.
- Navigation uses actual Decompose child stacks and child lifecycles. Swift owns the entries array; back events request that Swift update it. Android predictive-back events feed the actual Cupertino predictive animation; desktop supports Escape. Navigation must have a bounded size.

## Platform behavior

`Cupertino…Native` controls with upstream non-iOS implementations use those real Compose fallbacks on Android/desktop. UIKit-only color picker, native picker, UIKit children, and arbitrary SF Symbol lookup are explicitly unavailable on these targets. The 879 shared vector/adaptive symbols are included.

Icon `painterResource` and `imageBitmapResource` overloads resolve named application resources through the existing Android asset loader. Desktop has no named-asset resolver and shows a specific unavailable-resource diagnostic for those overloads; all 879 built-in vector/adaptive symbols resolve on both targets.

Upstream's Android haze implementation provides tint; desktop uses its Skia blur. Date-time pager rendering composes the upstream date pager and time picker together because the vendored date-time pager branch is unimplemented. It preserves one bridge date/time selection. Platform differences are not hidden behind fake native controls.

`CupertinoSystemBarAppearance` supplies Android light/dark status and navigation icon appearance and restores the previous window flags when its scope leaves composition. Desktop has no mobile system bars. `CupertinoHapticFeedback` dispatches supported host haptic types only when a new command ID is supplied; `onPerformed` reports dispatch, not physical motor feedback. UIKit-specific haptic types are explicitly unavailable.

Default adaptive rendering selects Cupertino and follows the surrounding light/dark appearance. An explicit `AdaptiveTheme` can select Material3. Explicit themes and Swift inherited typography/custom fonts remain available. SwiftKey's product design tokens are maintained separately from the library's default Cupertino appearance.

The raw public Kotlin API remains available to custom factories, including native Kotlin objects such as interaction sources and animation specifications. The Swift bridge projects those objects into named slots, serializable options, state holders, and commands; it does not serialize executable Kotlin closures or UIKit objects.

## Audit and validation

- `component-matrix.csv`, `functions.json`, and `api-signatures.md`: pinned upstream callable inventory, including overloads and helpers.
- `icons.csv`: every shared vector/adaptive icon.
- `license-inventory.json`: upstream license inventory.
- `BRIDGE-COVERAGE.md`: disposition of upstream declarations and bridge entry points.
- `vendor/compose-cupertino/SWIFTKEY-PATCHES.json`: exact local source modifications with original and modified hashes.
- `../../composeui/src/desktopTest`: real Compose interaction, state, icon, and render tests.
- `../../gradle/cupertino/cupertino/src/desktopTest`: regression tests against upstream picker internals.
- `../../gradle/cupertino/cupertino/src/androidUnitTest`: evaluates the Android popup-properties implementation, including focus and explicit dismissal policies. Android tracing is stubbed in this host test; actual window behavior is checked separately on hardware.

`python3 scripts/verify-cupertino-vendor.py` verifies all 1,911 pinned source files and nine declared local patches. `vendor.patch` records the changes; original and modified hashes are retained in the manifests. Android host apps must enable core library desugaring (as this checkout's demo does) for the vendored date/time implementation on older supported Android versions.

From the repository parent, source `scripts/androidswiftui-env.sh` in Bash. Then run:

```bash
source scripts/androidswiftui-env.sh
cd AndroidSwiftUI
./gradlew verifyCupertinoBuild :cupertino:desktopTest :cupertino:testDebugUnitTest :composeui:desktopTest :composeui:compileDebugKotlinAndroid
cd SwiftUICore
"$SWIFTKEY_SWIFT" test --no-parallel
```

The host test evidence is separate from an exercised Android hardware session. See the parent repository's `artifacts/cupertino` and `BUILD_STATUS.md` for the actual verification status.

The current SwiftKey APK build is `2a1a736` (339,809,795 bytes; the full digest is
in the parent `artifacts/cupertino/android-apk-build.json`). Validation currently
records 141 SwiftUICore, 401 desktop Kotlin, one Android popup-properties,
43 Application and 27 shared UI tests. The latest changes are in the Swift phone
host: invitation reviews advance locally when they expire, quiet refresh keeps
the displayed layout stable, and one explicit action or QR effect waits for the
read with its original binding. QR effects additionally verify the original
observer and foreground state. Kotlin remains at the tested revision.

Corrected selected-control device checks are recorded for Xiaomi `4060284` and
Pixel `43537a5`. Current `2a1a736` is installed on both phones with all four
existing legacy/v2 files preserved before launch. Pixel inspection expires
automatically with recovery visible; Pixel's four polling samples and Xiaomi's
two pre-expiry QR samples retain their control bounds without a busy banner.
Xiaomi's longer planned geometry check was interrupted by expiry. Physical
StrongBox pairing and joint genesis also passed against an isolated Vapor
authority: matching reviews, zero accounts after the first approval, then one
account/two owners after the second, with a verified ledger. Native Copy link and
manual import carried the invitation. Both phones then independently obtained
epoch credentials with verified root/authority signatures and delegation bindings.
This ran on isolated Vapor port 18191; optical camera scanning and v2 workload
submission are not claimed. These selected-control and protocol checks do not
establish all 127 surfaces on hardware, and remain separate from host test counts.
