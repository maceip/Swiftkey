# SwiftKey for iOS — executable mock

A native SwiftUI app and an embedded AuthenticationServices credential-provider
extension. The mock uses real P-256 signatures with **software test keys** and
explicit simulated user verification. It does not claim Secure Enclave storage,
Face ID approval, production passkey support or synchronization.

The host and extension share the same coordinator and app-group store. Test keys
are restricted to `swiftkey.mock` and `localhost`, separated from all Android and
SwiftKey authority state. Mock mode is available only in **Debug simulator builds**;
the iPhone and Release builds fail closed. Production device-bound passkeys remain
unsupported by Apple's provider contract; this mock lets us build and exercise the
app, protocol and platform adapter while that deployment choice is unresolved.
[Apple platform guidance](https://developer.apple.com/forums/thread/829541).

## Build and run

Xcode 26.4.1 was used locally. No Apple Developer account is needed for the simulator.
The scripts select Xcode's toolchain only for their subprocesses; the Android Swift
toolchain and global Xcode selection are unchanged.

```bash
bash scripts/ios.sh run           # build, install and launch a dedicated simulator
bash scripts/ios.sh test          # simulator unit/UI tests
bash scripts/ios.sh device-build  # unsigned iPhone app + extension; mock disabled
xcrun swift test --package-path SwiftKeyPasskeys
```

`SIMULATOR_UDID` selects an existing device if desired. Otherwise the script creates
or reuses **SwiftKey Passkeys Mock**, leaving existing simulator devices untouched.
`SWIFTKEY_IOS_HEADLESS=1` suppresses opening Simulator.app. Build products and logs are
in `iOS/DerivedData/`; `SWIFTKEY_IOS_DERIVED_DATA` changes that location.

Open `iOS/SwiftKey.xcodeproj`, select the **SwiftKeyMock** scheme, and run for an iOS
simulator. `scripts/ios/generate-project.py` regenerates the checked-in project using
only Python's standard library after source files are added or removed.
`scripts/ios-simulator.sh` now forwards to the product mock instead of the old renderer
catalog. Historical catalog captures remain under `ios-simulator/evidence/`.

## Exercise the app

Create a mock passkey, inspect the website/account, approve, then explicitly simulate
verification. The saved credential survives app relaunches. Open it to inspect its
public details, sign a fresh challenge, simulate a failed verification, cancel, or
remove the test credential. The UI always identifies mock mode. Nothing is sent to
a website and no existing account is enrolled.

The extension implements the actual Apple registration, credential-list and assertion
entry points. It requires user interaction; silent requests never return a credential.
The host harness exercises the same coordinator without pretending the system invoked
an extension. Simulator UI success and signed test fixtures do not establish a Safari
or physical-device credential-provider ceremony.

The app and extension use `group.com.maceip.swiftkey.mock` and the AutoFill credential
provider entitlement. Simulator builds are ad-hoc signed; Xcode embeds simulated
entitlements in the app and extension executables. Physical deployment would
need a developer team and matching provisioning, as well as a supported production
key/synchronization policy; an unsigned `.app` is a compilation artifact, not an
installable iPhone release.

## Layout

- `App/`: native product UI with shared purple design tokens and bundled fonts.
- `Shared/`: app-group storage, mock coordinator and identity-store adapter.
- `Extension/`: `ASCredentialProviderViewController` adapter.
- `Tests/`: simulator unit and UI checks.
- `../SwiftKeyPasskeys/`: bounded mock WebAuthn engine and cryptographic tests.

CI builds and tests the simulator app, compiles the disabled-mock iPhone target and
uploads `SwiftKeyMock-simulator.zip` plus test results. This archive is for the iOS
simulator, not an IPA or an App Store release.

[Verified builds, tests and actual app screenshots](../artifacts/ios-mock/README.md)
record the simulator run and unsigned iPhone compilation.
