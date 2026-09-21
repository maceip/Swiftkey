# Compose Cupertino verification

The complete upstream source at `f66875aa6f3848b30c38e42a89fc99c9ac24a585`
is vendored into AndroidSwiftUI: 1,911 original files and eight declared source
patches. All six modules build for Android and desktop. The
[bridge contract](../../AndroidSwiftUI/docs/cupertino/README.md) and
[coverage matrix](../../AndroidSwiftUI/docs/cupertino/BRIDGE-COVERAGE.md)
describe the 127 distinct Swift surfaces, 879 shared icons, serializable options,
state ownership and platform limitations.

[Browse the screenshot gallery](screenshots/index.html),
[visual review](render-review.md) and [hash audit](render-audit.json):
338 cases, 367 current images, including 29 popup roots.

## Final checks

| Evidence | Result |
| --- | --- |
| `swift-tests.log` | 141 serial SwiftUICore tests passed, including presentation lifecycle and typed helper contracts |
| `shared-ui-tests.json` / `.log` | 27 shared product UI tests passed against the final core |
| `android-desktop-tests.json` / `.log` | 389 native Kotlin tests passed: 338 catalog cases, 14 basic, 11 presentation, 7 state bridge, 10 existing renderer and 9 upstream picker regressions |
| `vendor-build.json` / `.log` | All 12 Android/desktop module compilation tasks passed |
| `swift-fixtures/` | 254 actual Swift-rendered open/closed fixtures covering 127 surfaces |
| `screenshots/` | Actual Compose/Skia renders at 360 × 720, including popup roots; representative dark/enlarged type and 48 Material3 variants |
| `android-apk-build.json` / `.log` | Complete ARM64 Swift/JNI crossbuild and Android debug assembly passed |
| `android-install.json` | Final APK installed on Pixel 11 Pro XL, private configuration and protocol files unchanged before launch |
| `android-launch.json` | Cold process launch, startup error count and keyguard status |

The final debug APK is 339,678,723 bytes, SHA-256
`4ca2c9a859a0ebeb1facdf65f3329e2e049f956431f4902908bd9fdd0e346e47`.
Build outputs and private app files are excluded from Git. Hashes alone record
client-file preservation; their contents were not published.

The catalog exercises real upstream widgets through Swift-exported RenderNodes.
Focused tests cover native callbacks, IME state, theme inheritance, dialog action
semantics/dismissal, sheet bounds, swipe controllers, 64-bit dates, PM preservation,
external picker updates, lazy row demand, Decompose lifetimes and haptic commands.
UIKit-only surfaces show explicit capability diagnostics. Desktop named application
resource loading is unavailable; the shared vector icon set works on both targets.

The phone remains locked and asleep. These records establish installation and
process startup, not on-device visual/gesture acceptance. Physical two-phone v2
pairing, Android predictive-back gesture exercise and haptic motor feedback remain
pending. The earlier [installed Android/Vapor acceptance](../vapor-hardware/README.md)
is separate evidence; no live authority migration or new account provisioning
was performed for this integration.

See `desktop-test-timeout-note.md` for the bounded wait workaround in the pinned
Compose test runtime. Popup tests create a real 360 × 720 window; resizing only a
scene would leave the underlying test window at 1024 pixels and give misleading
bounds evidence.

To verify vendored source provenance, run:

```sh
python3 AndroidSwiftUI/scripts/verify-cupertino-vendor.py
```
