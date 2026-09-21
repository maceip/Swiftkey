# iOS launch evidence — 2026-09-19

Command: `scripts/ios-simulator.sh run`

- Xcode: 26.4.1 (17E202), Apple toolchain.
- Simulator: iPhone 17 Pro, iOS 26.4.1 (23E254a).
- Device ID: `BE17EFB3-4CF9-4A09-91C1-21F7942871C8`.
- App bundle: `com.swiftkey.catalog.demo`.
- Built app: `../DerivedData/Build/Products/Debug-iphonesimulator/DemoApp.app`.
- `build.log` ends with `BUILD SUCCEEDED`.
- `launch.log` records the successful simulator launch and process ID.
- `catalog.png` was captured with `xcrun simctl io … screenshot` after launch
  and visually inspected: the native Catalog heading and component rows are
  visible, including Text.
- `simctl get_app_container` found the installed app; process 36793 was still
  running during the verification.
- The staged Catalog.swift and ControlPlaygrounds.swift matched their upstream
  shared sources byte for byte with `cmp`.

This establishes a real native build, installation, launch and visible Catalog.
It does not establish the Text counter tap sequence or exercise every adapter
screen; no simulator tap driver is installed in the current environment.
