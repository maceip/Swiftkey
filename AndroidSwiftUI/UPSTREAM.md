# Renderer source provenance

`AndroidSwiftUI/` is ordinary source in the SwiftKey repository. Clone and build
SwiftKey from `main`; no submodule initialization or renderer branch checkout is
required. The directory layout and relative package paths remain unchanged.

## AndroidSwiftUI

- Upstream: [PureSwift/AndroidSwiftUI](https://github.com/PureSwift/AndroidSwiftUI).
- Upstream base: [`e12fb09a906921506a84287f53117ccbf4357102`](https://github.com/PureSwift/AndroidSwiftUI/commit/e12fb09a906921506a84287f53117ccbf4357102).
- SwiftKey integration snapshot: [`5713ff8ac1886a7fa289baf8e0f459af04d3b335`](https://github.com/maceip/Swiftkey/commit/5713ff8ac1886a7fa289baf8e0f459af04d3b335).
- License: [MIT, copyright PureSwift](LICENSE).

The integration adds the shared SwiftKey phone host, adaptive design, complete
Compose Cupertino wrappers/catalog, and tested input, popup and refresh fixes.
All 2,220 tracked files, including executable modes and four symlinks, were
imported from that snapshot without content changes. Subsequent documentation
updates explain the ordinary-directory layout. Earlier renderer history remains
available through the integration commit; the historical `androidswiftui` branch
is no longer part of the build or checkout workflow.

## Compose Cupertino

The complete pinned upstream source is in `vendor/compose-cupertino/`:

- [Upstream source and revision](vendor/compose-cupertino/SWIFTKEY-SOURCE.json).
- [All 1,911 upstream file hashes](vendor/compose-cupertino/SWIFTKEY-FILES.json).
- [Nine declared local patches](vendor/compose-cupertino/SWIFTKEY-PATCHES.json).
- [Reproducible patch](docs/cupertino/vendor.patch) and [license](vendor/compose-cupertino/LICENSE.txt).

Verify every imported Cupertino file and declared patch from the SwiftKey root:

```sh
python3 AndroidSwiftUI/scripts/verify-cupertino-vendor.py
```
