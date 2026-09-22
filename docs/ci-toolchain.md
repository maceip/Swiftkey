# Android CI toolchain

`bash scripts/ci/setup-android-toolchain.sh` prepares the same paths and versions
used by `scripts/androidswiftui.sh`. Run it on an ARM64 macOS runner after
`actions/setup-java` selects Temurin 21 and `android-actions/setup-android` provides
`sdkmanager`. This reuses the Java/Android setup pattern from the user's Triplex
Android workflow; the Swift installation is the additional step this project needs.

| Component | Pin |
| --- | --- |
| Host Swift and Swift Android SDK | 6.3.2, matching `AndroidSwiftUI/.swift-version` |
| Host runner | `macos-26` (ARM64) |
| Apple SDK | Xcode 26.4.1 at `/Applications/Xcode_26.4.1.app` |
| Java | Temurin 21, provided by the workflow |
| Android compile SDK / build tools | API 35 / 35.0.0 |
| Android NDK | 27.3.13750724 (r27d) |
| APK Swift target | `aarch64-unknown-linux-android28` |

The workflow selects Xcode 26.4.1 explicitly because Vapor's pinned
`swift-configuration` dependency uses Foundation APIs absent from the old
Xcode 16.4 SDK. Host Swift remains pinned separately at 6.3.2. Java/Android
versions are also selected explicitly. See [runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and the [macOS 26 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).

## Download verification

The installer uses the official Swift 6.3.2 package linked by
[Swift.org's macOS release page](https://www.swift.org/install/macos/). It checks
SHA-256 `3dd8da736318b6f0a5d7c01b039dd8511f7994cababf9b10534dce1b19ccdca7`
and verifies its trusted macOS installer signature names
`Swift Open Source (V9AUD2URP3)` before installing for the current user. This package
digest was recorded from the signed official release; it is not presented as a
checksum field in the Swift release API.

The Android SDK checksum
`939e933549d12d28f2e0bf71019d734d309859e9773c572657ce565a81f85d68`
is published in the `android-sdk` entry for 6.3.2 in the
[official release metadata](https://www.swift.org/api/v1/install/releases.json),
documented by [Swift's API](https://www.swift.org/openapi/).
`swift sdk install --checksum` verifies that archive. No separate PGP-verification
claim is made. The host compiler and SDK must match exactly, as explained in
[Swift's Android guide](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).
The guide now describes a newer release; this repository deliberately retains
6.3.2 and its NDK setup script.

The existing AndroidSwiftUI upstream workflow uses Skip to obtain Swift. This
helper installs the same official Swift artifacts directly, avoiding an additional
unpinned Homebrew/Skip installation and leaving global Swiftly selection unchanged.
Android packages are installed with Google's
[sdkmanager](https://developer.android.com/tools/sdkmanager), with explicit API,
build-tools and NDK versions and CI license acceptance.

## Cache and local checks

The tracked `AndroidSwiftUI/Package.resolved` and
`AndroidSwiftUI/Demo/swift/Package.resolved` files preserve all 14 direct and
transitive remote dependency revisions used by host bridge generation and the
Android app. Their dependency pins match; their root-manifest hashes differ.
Fresh runners use normal SwiftPM lockfile resolution with the pinned compiler,
so they retain the tested graph instead of starting from current branch tips.

Reusable installation paths are:

- `~/Library/Developer/Toolchains/swift-6.3.2-RELEASE.xctoolchain`
- `~/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle`
- `$ANDROID_HOME/ndk/27.3.13750724`

Key trusted Actions caches by runner OS/architecture, the Swift/NDK versions and
the installer file's hash. Do not restore broad cross-version caches. Existing
installations are checked for their exact release identity and required files;
this is not a re-hash of every cached compiler binary. Incomplete installations
fail instead of silently overwriting them. Recreate that CI cache if needed.

The Swift SDK contains absolute NDK symlinks. Every install run regenerates them
against the selected runner NDK, including the clang resource link, then runs the
same `doctor` checks used locally. Downloaded host packages are removed after
installation. The script does not clear app/authority data or remove other
toolchains. It exports the selected paths through `GITHUB_ENV` and `GITHUB_PATH`
for following workflow steps.

Run a read-only validation of an existing developer installation with:

```bash
source scripts/androidswiftui-env.sh
bash scripts/ci/setup-android-toolchain.sh --check
```

`--check` performs no downloads, installation, symlink repair or Actions environment
writes. Successful local validation does not establish that a fresh hosted runner
completed installation; that remains a workflow result.

Allow disk headroom for the compiler, SDK, NDK, Gradle and SwiftPM outputs. Local
installed sizes are approximately 4.6 GB + 1.1 GB + 2.4 GB before build products.
The installer does not delete unrelated runner software to make space.
