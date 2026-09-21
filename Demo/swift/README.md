# SwiftAndroidApp

A description of this package.

## Pairing-first Android host

The launch screen keeps the existing identity surface and adds **Pair phones ·
v2**. Entering that flow does not generate a key, migrate a legacy account,
erase enrollment state, or approve anything. **Prepare this phone** uses the
separate retained StrongBox alias `swiftkey.attested-root.v2`; v1 aliases and
files remain untouched. A hardware signature operation always validates the
stored StrongBox entry and never falls back to a software key.

`AndroidPhoneProtocolBridge` supplies `ClientPlatform` to `PairingClient`, then
connects `NativePhoneProtocolService` and `PhoneProtocolStore` to the shared
`PhoneProtocolView`. The process coordinator survives Activity recreation,
serializes user actions, and refreshes pending operations every two seconds.
Polling never confirms peers, approves proposals or starts a new ceremony.
Current binding and deadline are checked again before native secret presentation.

**Trusted authority** accepts separately provisioned public JSON containing
`serverURL`, `serverPublicKey` (base64 uncompressed P-256 key), `audience`
(`swiftkey-authority-v2`), and optional `workloadAudience` (default `swiftkey.local`).
A QR link never sets any trust pin. Configuration and the protocol recovery
journal live in Android's backup-excluded app-private directory:

- `no_backup/swiftkey-pairing-v2-config.json`
- `no_backup/swiftkey-pairing-v2-state.json`

Writes use `AtomicFile`, mode 0600, fsync, and committed readback verification.
The configuration sheet cannot change authority once a v2 root or journal
exists. Missing/unreadable state and hardware failures are reported; no reset
control is provided. Production transport requires HTTPS to the exact configured
origin, bounded JSON and no redirects. Debug builds additionally allow an
explicit `http://127.0.0.1:PORT` for `adb reverse`. Transport permits `/v2/*` and
only `/v1/challenges` + `/v1/epochs` for the retained epoch-credential operations.

`PhoneProtocolHost` implements the explicit native effects: an actual QR bitmap,
permission-aware QR camera scanner, secure manual entry, explicit share/copy,
and automatic expiry/dismissal. QR and manual dialogs disable screenshots and
saved view/autofill state; the camera saves no image. Imported links cross a
single-use in-memory queue and are never logged or inserted in the Swift view
tree. Copy happens only after the user taps **Copy link**; expiry clears only
that same clipboard value. External sharing is explicit and the authority still
enforces capability expiry. Camera denial offers manual import.

Host unit tests cover trust-origin routing, unsupported v1 governance paths,
loopback restrictions, invitation size and binding/expiry guards, plus exact QR
encode/decode roundtrip. These tests and APK compilation do not establish a
physical two-phone StrongBox ceremony. No device installation or reprovisioning
is performed by the build.

```sh
source scripts/androidswiftui-env.sh
./AndroidSwiftUI/gradlew -p AndroidSwiftUI :demo-app:testDebugUnitTest
./scripts/androidswiftui.sh android-build
```
