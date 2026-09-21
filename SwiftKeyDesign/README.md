# SwiftKey component design system

SwiftKey's current visual reference is the supplied `design-system-main.zip`,
retained in [`vendor/design-system`](../vendor/design-system). The active system
uses adaptive white/charcoal surfaces, a purple accent, rounded cards and
controls, Host Grotesk and JetBrains Mono on both browser and native hosts.

The source, archive digest, superseded retro TypeSafe reference, adaptation
boundaries and verification requirements are documented in
[the adaptation record](../docs/TYPESAFE-UI-ADAPTATION.md). The earlier green
“Fieldwork” palette and the subsequent square pink/sage concept are historical.

## Current contract

[`tokens.json`](tokens.json) records the actual shared Swift color pairs,
spacing, radii and typography, plus the browser shell's distinct layout and
control dimensions. `SwiftKeyUI/Sources/SwiftKeyUI/SwiftKeyAppearance.swift`
is the runtime source of shared semantic values. Important pairs are:

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#FFFFFF` | `#1E1E1E` |
| Card | `#FFFFFF` | `#252326` |
| Code surface | `#FDFCFE` | `#252326` |
| Primary text | `#1E1E1E` | `#FCFCFC` |
| Secondary text | `#6B6B6B` | `#ABBAB9` |
| Border | `#E5E5E5` | `#2F2D30` |
| Accent | `#A02AB8` | `#D28FE2` |
| Text on accent | `#FFFFFF` | `#1E1E1E` |

The body uses Host Grotesk 16px/28px with +0.3px tracking. Shared headings use
weight 560 and −0.3px tracking; action labels use weight 500 and zero tracking.
JetBrains Mono renders complete public key bytes and technical identifiers.
Cards use a 12px radius and controls 8px. Both hosts follow system appearance;
light/dark behavior is implemented in the renderer rather than delegated to
Android's automatic recoloring of a light-only screen.

Fonts are bundled for both browser and native rendering. Source hashes, static
native weights, author notices and license texts are documented in
[font-sources.md](font-sources.md). Fonts are never requested from an external
service during UI use.

## Shared implementation

`SwiftKeyUI` owns workspace and phone composition, labels, formatting, bindings
and conditional actions. `SwiftKeyApplication` owns state/actions and service
contracts. Compose and the generic DOM adapter consume the SwiftUICore view
node protocol, including adaptive colors and named fonts. Browser Swift runs
in an isolated server session, not browser WebAssembly.

The browser resources contain the admin-token shell, primitive styles and
transport/rendering glue. JavaScript does not own account eligibility or
credential validation. Tokens stay in page memory and clear on disconnect.
Clipboard and download behavior remain explicit host effects. Authentication
and authorization remain server responsibilities.

Native adapters supply bundled font resources, appearance, secure invitation
sheets and other platform effects. Cupertino is a separate native component
library; it does not replace the shared Swift protocol views. The optional
TypeSafe text-description research tool is also separate from UI runtime and
does not certify visual quality.

## Historical assets and evidence

`root-key.svg`, other original artwork and the images in `previews/` are retained
historical design assets. They were not regenerated for the current component
system. They must not be used as evidence of its present light/dark appearance,
fonts, current phone surfaces or device installation.

Earlier results in [`artifacts/swiftkey-design`](../artifacts/swiftkey-design/README.md)
and historical native previews describe their original builds. Current build,
installation and observed behavior belong in [`BUILD_STATUS.md`](../BUILD_STATUS.md)
and the current design-system evidence directory. Passing source or adapter
checks does not establish pixel equivalence or physical-phone visual acceptance.
See [mobile.md](mobile.md) for the current native implementation boundary.
