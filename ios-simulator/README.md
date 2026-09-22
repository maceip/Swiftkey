# Historical native renderer catalog

The product iOS app is now [SwiftKey Mock](../iOS/README.md). Run it with:

```sh
bash scripts/ios.sh run
```

The compatibility command `scripts/ios-simulator.sh run` launches that same product
app. It no longer stages or launches the old renderer catalog.

`NativeAdapters.swift`, `MapPlaygrounds.swift` and `evidence/` remain historical
renderer-development sources and captures. They are not compiled into the current
SwiftKey iOS app or credential-provider extension.
