# Historical renderer verification

This directory preserves component-showcase development evidence, not SwiftKey
product screenshots. Build hashes, captures and results below describe their
recorded checkpoints, not the latest app. Original evidence is retained unchanged.
See [SwiftKey hardware acceptance](../phone-v2-hardware/README.md) for actual
pairing and account use, and [build status](../../BUILD_STATUS.md) for current work.

The complete upstream source at `f66875aa6f3848b30c38e42a89fc99c9ac24a585`
is vendored into AndroidSwiftUI: 1,911 original files and nine declared source
patches. All six modules build for Android and desktop. The
[bridge contract](../../AndroidSwiftUI/docs/cupertino/README.md) and
[coverage matrix](../../AndroidSwiftUI/docs/cupertino/BRIDGE-COVERAGE.md)
describe the 127 distinct Swift surfaces, 879 shared icons, serializable options,
state ownership and platform limitations.

[Browse the historical renderer gallery](screenshots/index.html),
[visual review](render-review.md) and [render audit](render-audit.json):
338 cases, 367 current images, including 29 popup roots.

## Final checks

| Evidence | Result |
| --- | --- |
| `swift-tests.log` | 141 serial SwiftUICore tests passed, including presentation lifecycle and typed helper contracts |
| `shared-ui-tests.json` / `.log` | 27 shared product UI tests passed against the final core |
| `android-desktop-tests.json` / `.log` | 401 desktop Kotlin tests passed: 338 catalog cases, 14 basic, 12 presentation, 7 state bridge, 11 text entry, 10 existing renderer and 9 upstream picker regressions |
| `android-popup-properties-test.json` / `.log` | One Android actual-implementation unit test passed: modal focus and explicit dismissal/width policies; host Android tracing stubs do not establish device accessibility |
| `quiet-refresh-application-tests.log` | Current 43 Application tests passed: peer-proposal discovery, invitation expiry/local re-projection, one deferred action or QR request, and rejection of the original consent after the review changes |
| `invitation-expiry-application-tests.log` / `../phone-v2-hardware/polling-application-tests.log` | Earlier 40- and 38-test checkpoints retained for their corresponding fixes |
| `vendor-build.json` / `.log` | Original all-module compilation checkpoint: all 12 Android/desktop tasks passed; subsequent compilation results are in current test/build logs |
| `swift-fixtures/` | 254 actual Swift-rendered open/closed fixtures covering 127 surfaces |
| `screenshots/` | Actual Compose/Skia renders at 360 × 720, including popup roots; representative dark/enlarged type and 48 Material3 variants |
| `android-apk-build.json` / `.log` | Complete ARM64 Swift/JNI crossbuild and Android debug assembly passed |
| `android-install.json` / `android-launch.json` | Historical `4ca2c9a` Pixel installation and cold launch; client files unchanged before that launch, device then locked |
| `android-hardware/xiaomi-install.json` | Preceding `43537a5` APK installed; both legacy client files unchanged before launch |
| `android-hardware/xiaomi-fixed/verification.json` | Corrected `4060284` selected-control smoke: dialog focus/Cancel/Back, bounded sheets, fast text input and identity return |
| `android-hardware/pixel-fixed/verification.json` | Corrected `43537a5` selected-control smoke: dialog focus/Back, sheet states/bounds, exact text retention, one-step cursor edit and return navigation |
| `android-hardware/pixel-final-install.json` / `xiaomi-final-install.json` | Current `2a1a736` installed on both phones; all four legacy/v2 private configuration and state files hash-identical before first launch |
| `../phone-v2-hardware/final-expiry-verification.json` | Current Pixel inspection automatically expires with recovery visible; no restart or manual refresh |
| `../phone-v2-hardware/pixel-inspection-stability.json` | Four current Pixel samples retain identical Join button bounds without a busy banner |
| `../phone-v2-hardware/xiaomi/quiet-poll/verification.json` | Two current Xiaomi pre-expiry QR samples retain identical bounds; five samples omit the busy banner. The intended 15-second geometry check was interrupted by expiry |
| `../phone-v2-hardware/genesis-review-verification.json` / `after-first-genesis-approval.json` / `after-second-genesis-approval.json` | Current hardware pairing/joint genesis passed on isolated Vapor: matching reviews; first approval leaves 0 accounts/owners/credentials, second commits 1 account/2 owners/0 credentials with a verified ledger |
| `../phone-v2-hardware/pixel-first-sign-in.json` / `both-independent-sign-ins.json` | Independent phone sign-ins pass: credential count 0 → 1 → 2 with the same account/two owners; root/authority signatures, delegation bindings and admitted root matches verify |

The current debug APK is 339,809,795 bytes, SHA-256
`2a1a736512343cdf617bed94af2711d83f54f3035f5bcff3ce6559524a514667`.
Installation passed on both phones, preserving all four existing legacy/v2
configuration and state files before first launch. Expiry and stable-polling
checks passed within the sample limits above. Physical mutual pairing and joint
genesis and independent sign-in/epoch issuance also passed on the isolated Vapor authority.
Build outputs and private app files are excluded from Git. Hashes alone record
client-file preservation; their contents were not published.

The catalog exercises real upstream widgets through Swift-exported RenderNodes.
Focused tests cover native callbacks, IME state, theme inheritance, dialog action
semantics/dismissal, sheet bounds, swipe controllers, 64-bit dates, PM preservation,
external picker updates, lazy row demand, Decompose lifetimes and haptic commands.
UIKit-only surfaces show explicit capability diagnostics. Desktop named application
resource loading is unavailable; the shared vector icon set works on both targets.

The preceding `43537a5` build was installed on both phones for isolated acceptance. Earlier Pixel
captures exposed three real defects: modal popups did not own Android focus,
older Swift echoes overwrote recent text input, and hidden sheets painted below
their preview. Corrected Xiaomi `4060284` and Pixel `43537a5` evidence exercises
these fixes. They contain the same tested Kotlin code as current `2a1a736`.
Later Swift changes keep active ceremonies polling, re-project unjoined invitation
expiry locally, and keep the UI stable during quiet reads. A single explicit
action or QR request waits for the read with its original binding; QR display
also verifies the original observer/foreground and current native context. See the
[hardware evidence index](android-hardware/README.md) for exact build boundaries,
baseline failures, corrected captures and remaining limits.

Physical two-phone v2 pairing and joint genesis passed on this final APK using
native Copy link/manual import, with no operator-seeded account. See the
[ceremony evidence](../phone-v2-hardware/README.md). Both phones then independently
obtained verified epoch credentials. The authority was isolated on port 18191;
optical camera scanning, v2 workload submission and further membership/recovery
cases are outside this completed scope.
A recorded Pixel navigation back
gesture proves the route callback, but complete predictive animation/cancellation
and physical haptic feedback are not claimed. The earlier
[installed Android/Vapor acceptance](../vapor-hardware/README.md) remains separate.
No live authority cutover or existing-account migration is established here.

`integration.json` and `vendor-verification.json` retain the initial checkpoint
(389 tests, eight patches and the `4ca2c9a` APK where applicable). They are
historical records, not the current summary. Current counts/hash are in
`android-desktop-tests.json` and `android-apk-build.json`; rerun the verifier below
against the present nine-patch source. `android-install.json` and its locked-device
launch record must likewise not be relabeled as current two-phone evidence.

See `desktop-test-timeout-note.md` for the bounded wait workaround in the pinned
Compose test runtime. Popup tests create a real 360 × 720 window; resizing only a
scene would leave the underlying test window at 1024 pixels and give misleading
bounds evidence.

To verify vendored source provenance, run:

```sh
python3 AndroidSwiftUI/scripts/verify-cupertino-vendor.py
```
