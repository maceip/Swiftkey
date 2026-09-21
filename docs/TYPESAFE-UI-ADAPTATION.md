# SwiftKey adaptation of the supplied component design system

## Current source and superseded reference

The current UI reference is the user-supplied
`/Users/mac/Downloads/prompt-prep-outputs/design-system-main.zip`, retained in
[`vendor/design-system`](../vendor/design-system). Its SHA-256 is
`70a50c1df4a2b07487e8fb8aba1263a7f91c319174ba67935bb8c3d2fb9512aa`.
[`SOURCE.json`](../vendor/design-system/SOURCE.json) records the archive,
upstream repository declaration, package version and provenance limits.

This supersedes the earlier retro landing-page adaptation described here from
`/Users/mac/Downloads/typesafe-with-code.zip` (SHA-256
`43d2205ac296d824261608b885d64c5fc37d761727bcf41f9e4d56e629ef2388`).
Square black titlebars, Lisa Terminal, Die Grotesk C, halftone sections and the
old pink/sage marketing-page layout are no longer the SwiftKey visual contract.
That earlier archive remains the source of the two selected Google Fonts files;
it does not supply the active component implementation.

The new archive declares `@maximeheckel/design-system` version `4.2.3` and
[MaximeHeckel/design-system](https://github.com/MaximeHeckel/design-system) as
its repository. It includes customized theme and typography files. The archive
is the reference snapshot; its version string does not establish equivalence
to an unmodified upstream release. No upstream commit was supplied. Its
`package.json` declares MIT, but the archive contains no standalone license or
copyright notice. This record preserves that declaration without inventing an
upstream copyright holder, year or license text.

## Shared visual contract

Tokens come from the archived `src/lib/themes/{light,dark}.ts` and
`src/lib/tokens/`. Shared Swift colors use the converted sRGB values of the
OKLCH declarations, rather than the approximate hex comments in the archive.

| Element | SwiftKey treatment |
| --- | --- |
| Display and body | Host Grotesk; ordinary weight 400, controls 500, headings 560 |
| Technical text | JetBrains Mono; weight 400, explicit other weights when needed |
| Type scale | Archive 14/16/18/20/24/32/44px; shared operational headings 32px with 48px line height, body 16/28px (+0.3px tracking), controls 14/21px (zero tracking), technical text 13/21px (zero tracking) |
| Radii | 4/8/12/16px; shared controls 8px, cards 12px, browser connection panel 16px |
| Canvas, light/dark | `#FFFFFF` / `#1E1E1E` |
| Card, light/dark | `#FFFFFF` / `#252326` |
| Code surface, light/dark | `#FDFCFE` / `#252326` |
| Primary text, light/dark | `#1E1E1E` / `#FCFCFC` |
| Secondary text, light/dark | `#6B6B6B` / `#ABBAB9` |
| Border, light/dark | `#E5E5E5` / `#2F2D30` |
| Accent, light/dark | `#A02AB8` / `#D28FE2` |
| Text on accent, light/dark | White / `#1E1E1E`; dark mode uses dark text on the pale purple surface |
| Interaction | Visible keyboard focus, disabled/busy states, rounded controls, system appearance changes, reduced-motion support |

The source's component dimensions are adapted to operational phone UI: shared
button labels have a minimum 45px touch height instead of the archive's 34px
button height. SwiftKey retains its name, protocol text, full public keys,
receipt details and action semantics. Decorative or showcase examples are not
presented as working authority operations.

## Runtime architecture and fonts

`SwiftKeyUI/Sources/SwiftKeyUI/SwiftKeyAppearance.swift` and
`SwiftKeyComponents.swift` define shared colors, typography and reusable
components. `WorkspaceView`, `PhoneProtocolView`, `SwiftKeyIdentityView` and
`SwiftKeyPublicKeyView` retain Swift composition and application callbacks.
The archived React/Stitches implementation is reference material, not a new
web application dependency or a second source of protocol state.

`AndroidSwiftUI/SwiftUICore` carries named font families, exact numeric font
weights, tracking, absolute line height and adaptive colors through the view
node protocol. Static colors remain supported. An adaptive color carries
`[lightARGB, darkARGB]`. The browser keeps both variants in CSS `light-dark()`
and changes with the OS appearance without fetching another tree. Compose
resolves the pair from the active appearance. Browser CSS and the Android host
also style native controls, focus indicators and surrounding chrome.

The browser bundles unchanged variable WOFF2 files and serves only these
explicit same-origin font routes:

- `/fonts/host-grotesk.woff2`: Host Grotesk, weight axis 300–800.
- `/fonts/jetbrains-mono.woff2`: JetBrains Mono, weight axis 100–800.

The files named `HostGrotesk-400.woff2` and `JetBrainsMono-400.woff2` in the old
archive are variable fonts despite their filenames. FontTools 4.65.0 was used
to instantiate native TrueType resources at weights 400, 500, 560, 600 and 700.
Android resources are under `AndroidSwiftUI/Demo/app/src/main/res/font/`;
matching desktop test resources are under
`AndroidSwiftUI/composeui/src/desktopMain/resources/fonts/`. Android and desktop
copies have matching hashes. Native adapters resolve the declared family and
weight; they do not depend on fonts installed on the device. Unknown families
fall back to a system font. Missing glyphs still require platform fallback.

[`FONTS.json`](../vendor/design-system/FONTS.json) records source archive and
font hashes, exact zip entries, variable ranges, output paths, native instance
hashes, copyright notices and license provenance.
[`SwiftKeyDesign/font-sources.md`](../SwiftKeyDesign/font-sources.md) describes
the active and retained historical font resources. Browser runtime font
loading does not contact Google Fonts or a model service.

Custom Swift button labels preserve an explicitly requested bordered or
prominent style. Shared components that draw their own surfaces explicitly use
`.buttonStyle(.plain)`; label shape does not silently disable native chrome.
Child styles take precedence over an inherited style.

## Verification and limits

The browser adapter regression suite covers adaptive colors, font-family
resolution/fallback, exact weight 560, tracking/line height, explicit button
styles and inheritance, together with the existing callback, input, focus,
secret handling and clipboard-fallback checks. Those checks passed during
implementation. Source/font provenance checks verify archive and WOFF2 hashes,
embedded author notices and Android/desktop resource agreement.

These checks do not establish complete visual or interaction parity. Product
acceptance must inspect the rendered workspace at 1440px, 390px and 320px,
light and dark appearance including an in-place OS switch, keyboard focus,
large text, validation failures, long public keys and native secure sheets.
Native compilation, installation and physical-device observations must be
reported separately. Earlier reference previews and the pre-redesign Vapor
hardware acceptance do not demonstrate the restyled app on a phone.

This is a shared Swift port of the design system's relevant tokens and
components, not execution of every archived React component. Browser and
Compose have different text rasterization and layout engines. Font resources
and exact weights reduce that difference; unsupported layout/media primitives
or unexercised catalog states must not be described as visually verified.
Cupertino support remains a separate native renderer dependency and does not
replace the shared Swift application layer.

## Separate TypeSafe text research

[`tools/DesignResearch/research.py`](../tools/DesignResearch/research.py) is an
optional command-line experiment for evaluating written component descriptions
against supplied evidence and human labels. Its TypeSafe SDK and model calls
are not dependencies of the browser, Swift views, phone app, or authority
protocol. The design-system archive and this text experiment are separate
inputs with separate purposes.

The experiment accepts text descriptions and evidence excerpts, separates
development and held-out component groups, freezes selected features before
evaluation, and reports agreement with the supplied human labels. It does not
render screenshots or measure pixel similarity, usability or accessibility.
Schema validation alone does not authenticate label provenance, and no model
quality claim follows from installing its dependencies or passing offline
checks. Live calls require the tool's explicit `--live` mode and request
budget; UI interaction never invokes it. No experiment scores are claimed by
this adaptation document.
