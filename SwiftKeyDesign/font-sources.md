# SwiftKey font sources and notices

## Active component-system fonts

Host Grotesk and JetBrains Mono implement the typography declared by
`vendor/design-system/src/lib/tokens/typography.ts`. Their source bytes were
provided in `/Users/mac/Downloads/typesafe-with-code.zip`, SHA-256
`43d2205ac296d824261608b885d64c5fc37d761727bcf41f9e4d56e629ef2388`.
The newer `design-system-main.zip` selects these families but does not contain
the font binaries. The old archive's other typefaces are not the active design.

| Family | Source entry suffix | Browser resource and route | Variable weight axis |
| --- | --- | --- | --- |
| Host Grotesk | `public/fonts/typesafe/google/HostGrotesk-400.woff2` | `SwiftKeyServer/Sources/SwiftKeyServer/Resources/host-grotesk.woff2` → `/fonts/host-grotesk.woff2` | 300–800 |
| JetBrains Mono | `public/fonts/typesafe/google/JetBrainsMono-400.woff2` | `SwiftKeyServer/Sources/SwiftKeyServer/Resources/jetbrains-mono.woff2` → `/fonts/jetbrains-mono.woff2` | 100–800 |

The browser copies are byte-for-byte identical to those zip entries:

- Host Grotesk: `5662dcd15d8c7dc5bf2168baa71072e509c5b97167554b861293f68e1aa6dde8`.
- JetBrains Mono: `1e06740a02a443fb7f3eeda8fcaa685a0f6c620e3f01e6666e847295469ce3ad`.

Native `.ttf` resources were generated with FontTools 4.65.0 at explicit weights
400, 500, 560, 600 and 700. These are static instances derived from the supplied
variable font, not independently downloaded font releases. Android bundles
`host_grotesk_<weight>.ttf` and `jetbrains_mono_<weight>.ttf` in
`AndroidSwiftUI/Demo/app/src/main/res/font/`; matching desktop copies live in
`AndroidSwiftUI/composeui/src/desktopMain/resources/fonts/`. Full source and
output hashes are in [`FONTS.json`](../vendor/design-system/FONTS.json).

The source and generated font name tables retain these author notices:

- Copyright 2023 The Host Grotesk Project Authors
  (<https://github.com/Element-Type/HostGrotesk>).
- Copyright 2020 The JetBrains Mono Project Authors
  (<https://github.com/JetBrains/JetBrainsMono>).

Both upstream projects supply SIL Open Font License 1.1. Complete, unmodified
texts were retrieved from the projects' official repositories and retained:

- [Host Grotesk OFL](licenses/Host-Grotesk-OFL.txt), from
  <https://raw.githubusercontent.com/Element-Type/HostGrotesk/main/OFL.txt>.
  License SHA-256: `386b93abff8765eeae26a8e4cf58421e724e15cd5317cec8101df84e4693687e`.
- [JetBrains Mono OFL](licenses/JetBrains-Mono-OFL.txt), from
  <https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/OFL.txt>.
  License SHA-256: `a76abf002c49097d146e86740a3105a5d00450b1592e820a1109a8c5680cd697`.

Keep these copyright notices and complete licenses with source and binary
redistributions, including the generated native instances. Font licenses are
separate from the design-system package's declared MIT license. The supplied
WOFF2 and native files have copyright/license-URL metadata, but no complete
license-text name-table entry; release packaging must therefore carry the
standalone texts rather than relying on that URL alone.

Use `font-display: swap` with suitable fallback. The supplied font files do not
promise coverage of every script. The two public routes are explicit,
same-origin server assets; no external font service is contacted at runtime.

## Retained historical console fonts

Space Grotesk and IBM Plex Mono supported the previous console design. Their
files and notices remain in the source tree, but they are no longer selected by
the current CSS or exposed by the current HTTP font allowlist.

Retrieved 2026-09-19 from the official Google Fonts stylesheet and font CDN:
<https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300..700&family=IBM+Plex+Mono:wght@400&display=swap>.

- Space Grotesk, variable normal 300–700, Latin subset, 22,320 bytes:
  <https://fonts.gstatic.com/s/spacegrotesk/v22/V8mDoQDjQSkFtoMM3T6r8E7mPbF4C_k3HqU.woff2>.
  Font SHA-256: `a0d054c4af557de20afd6ca59f47ab353bcaec49c63ff04b6c9d39d0f8910557`.
  [OFL notice](licenses/Space-Grotesk-OFL.txt), from
  <https://raw.githubusercontent.com/google/fonts/main/ofl/spacegrotesk/OFL.txt>.
  License SHA-256: `564ce565c371c5e5bbf286006565a7c9aa55a9f56e7ca58d56e05d649dd61a72`.
- IBM Plex Mono, normal 400, Latin subset, 10,052 bytes:
  <https://fonts.gstatic.com/s/ibmplexmono/v20/-F63fjptAgt5VM-kVkqdyU8n1i8q131nj-o.woff2>.
  Font SHA-256: `c36f509c0a8f9f85f29cb44bc8701d8a9e0b14c499e77a884f789ead7093a7ac`.
  [OFL notice](licenses/IBM-Plex-Mono-OFL.txt), from
  <https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexmono/OFL.txt>.
  License SHA-256: `7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da`.
