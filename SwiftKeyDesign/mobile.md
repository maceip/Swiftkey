# SwiftKey native presentation

The current native UI ports the supplied component design system through shared
Swift views. It uses purple accents, rounded cards and controls, actual Host
Grotesk and JetBrains Mono resources, and explicit light/dark color pairs. The
earlier green, system-font, light-only identity screen is historical.

## Current shared values

The runtime constants are in
`SwiftKeyUI/Sources/SwiftKeyUI/SwiftKeyAppearance.swift`, not a duplicate file in
the Android demo. [tokens.json](tokens.json) records both appearances, including
the dark code surface `#252326`. Shared body text is 16px/28px with +0.3px
tracking; headings use weight 560 and −0.3px tracking. Controls use an 8px
radius, cards 12px, page insets 20px and card insets 16px. The focused identity
view is constrained to 520px before its outer insets.

`SwiftKeyIdentityView` presents the SwiftKey mark, a hardware-identity heading,
explanation and the complete public key. `SwiftKeyPublicKeyView` preserves byte
order, groups bytes in rows of eight and provides a compact 13px/21px treatment
for inset workspace cards; the full identity treatment uses 14px/24px. It does
not truncate, generate or validate keys. The view can scroll.

`PhoneProtocolView` and `WorkspaceView` reuse the same typography, cards,
status labels and action surfaces across available, waiting, error and recovery
states. Styled action labels explicitly select plain button rendering; a custom
label alone does not suppress a requested native bordered/prominent style.

## Platform boundary

- `AndroidSwiftUI/Demo/App.swiftpm/Sources/HardwareKeyView.swift` obtains verified
  public key bytes through the existing hardware adapter and starts the
  serialized legacy protocol runner. Rendering never creates a replacement key.
- Shared views live in `SwiftKeyUI/Sources/SwiftKeyUI/`. Application state,
  authorization and operation recovery remain in `SwiftKeyApplication` and the
  protocol clients; presentation tokens do not change those rules.
- `AndroidSwiftUI/SwiftUICore` serializes named fonts, numeric weights, tracking,
  absolute line height and adaptive colors. Compose interprets those values,
  including inherited text and field styling.
- `AndroidSwiftUI/composeui/src/androidMain/kotlin/com/pureswift/swiftui/SwiftUIHostView.kt`
  selects the system appearance and host typography. Native sheets remain
  host-owned, including secure-window and transient invitation handling.
- Android bundles font instances under `Demo/app/src/main/res/font/`. Matching
  desktop resources live under `composeui/src/desktopMain/resources/fonts/`.
  Weights 400/500/560/600/700 are explicit static instances; their provenance and
  complete licenses are in [font-sources.md](font-sources.md).

Desktop previews use synthetic public bytes. They can exercise the Swift → JNI
→ Compose rendering path and glyph layout, but they are not Android hardware
attestation, physical screen or protocol acceptance evidence. No current iOS
execution is claimed by this document.

## Verification boundaries

Current acceptance must exercise light and dark appearance, an OS appearance
switch, narrow layouts, enlarged text, complete keys, focus, errors and native
secure sheets. A preserving app update must retain installed keys and app state.
Signing/package identity, installation and actual hardware observations must be
recorded separately from source/build/test success in
[BUILD_STATUS.md](../BUILD_STATUS.md).

These existing images are **historical synthetic fixtures for the older green
identity design**, retained without modification:

- [360px identity preview](previews/android-renderer-fixture.png)
- [320px enlarged-text preview](previews/android-large-text-fixture.png)
- [Old enlarged view scrolled to its final byte](previews/android-large-text-scrolled-fixture.png)

The former test counts, old temporary build logs, old “no connected devices”
statement and earlier dark-color mismatch are not current acceptance results.
The explicit adaptive-color implementation addresses the source-level theme
contract; actual phone appearance still needs evidence from the current build.
