# Native iOS catalog

Run from the SwiftKey workspace:

```sh
scripts/ios-simulator.sh run
```

`build` builds without installing or launching. `SIMULATOR_UDID` can select a
different available iPhone/iPad simulator. The default is the existing iPhone
17 Pro running iOS 26.4. The script uses Xcode's Apple toolchain independently
of the Android Swift toolchain and does not change global toolchain settings.

The application is the existing SwiftUI demo, built by Xcode directly from an
`.iOSApplication` Swift package. The script refreshes a generated `App.swiftpm`
copy of `AndroidSwiftUI/Demo/App.swiftpm`, including assets, before each build.
The App entry point, Catalog, Text counter, and all other common screens stay
as shared source. No catalog screens are excluded. This is a native SwiftUI
app, not the Compose/JNI renderer.

Small native compatibility adapters are kept here, outside the upstream repo:

- `NativeAdapters.swift` maps the demo's interpreter-only unknown modifier to
  the same red outline and supplies native text headers/footers for its Section
  convenience initializer. Its alert/dialog overloads translate the shared
  button-array syntax into real SwiftUI alerts and confirmation dialogs.
- Its custom-view registry counterpart renders an interactive half-step star
  rating, a dashed rounded border around SwiftUI children, and the unregistered
  view diagnostic. These examples use native SwiftUI, with real state callbacks.
- The generated copy of `ControlStylePlaygrounds.swift` changes only the
  `.checkbox` toggle style to a native checkbox style supported on iOS.
- `MapPlaygrounds.swift` replaces the Android-specific map initializer with
  interactive MapKit maps using the same regions, marker coordinates and colors.

Upstream Swift source files are not edited. The generated package and DerivedData
are disposable. Build logs, launch output and the simulator screenshot are saved
under `evidence/`.

Bundle ID: `com.swiftkey.catalog.demo`.
