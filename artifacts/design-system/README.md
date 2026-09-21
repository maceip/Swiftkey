# Supplied design-system verification

The authoritative archive is `design-system-main.zip`, SHA-256
`70a50c1df4a2b07487e8fb8aba1263a7f91c319174ba67935bb8c3d2fb9512aa`.
Source, attribution and font provenance are preserved under `vendor/design-system`.

`verification.json` records the current browser/build evidence. The 43 real Swift
phone surfaces were rendered by the shipped browser adapter in light/dark mode,
at measured 320/1440 browser widths and normal/140% layout scaling. All 344
combinations fit horizontally. Full fingerprints and disabled expired approvals
were inspected. Host Grotesk and JetBrains Mono loaded from local routes.

An isolated Vapor authority on port 18190 completed admin login, account creation,
and workspace navigation. It used disposable state and synthetic preview admin
credentials. No live membership was modified by this browser test.

SwiftKeyUI 27, SwiftUICore 124 (serial), Compose desktop 10 and SwiftKeyServer 77 tests
passed. The normal parallel core run exposed an existing global animation
transaction test race; the serial run passed. Android APK build and `install -r`
on the connected Pixel passed. Client state hashes were compared before launch;
no provisioning or reset was performed. Native visual verification remains
pending because the device is locked. This evidence does not prove physical
v2 pairing or autoresearch improvement on real data.
