# Android website passkeys

SwiftKey implements an Android 14+ Credential Manager provider for standard browser
WebAuthn registration and authentication. It is separate from the SwiftKey two-phone
account authority and its four-hour epoch credentials. The provider is implemented
and covered by automated tests; a physical StrongBox phone must still pass the
browser acceptance sequence below before hardware interoperability is claimed.

## Use

1. Install SwiftKey on a StrongBox-capable Android 14+ phone with a secure screen lock.
2. Open **Website passkeys**, then **Enable SwiftKey in Android Settings**. Enable
   SwiftKey as a password/passkey provider in the system settings.
3. In a website's account/security settings, choose **Add a passkey** and select
   SwiftKey in Android's provider picker.
4. Check the website and account shown by SwiftKey. Approve and authenticate using
   Android's strong biometric or device-credential prompt.
5. Later choose that credential in the browser's normal sign-in flow and verify again.

Saved passkeys can be removed from the Website passkeys screen. Removal deletes this
phone's credential and hardware key, not the website account. Register another way
to sign in before deleting a passkey. Reinstalling, clearing app data, losing the phone
or invalidating its hardware keys can make these credentials unusable.

## Key and request policy

- A new random 32-byte credential ID and independent **P-256/ES256 StrongBox key** are
  created for every registration. Private keys are non-exportable. There is no TEE
  or software fallback, no global website key and no automatic rotation.
- Every key requires hardware-enforced, per-use authentication. A `Signature`
  operation is passed to `BiometricPrompt.CryptoObject`; only that exact operation
  can complete the captured payload. Registration commits metadata only after an
  authenticated proof with the new key. Cancellation removes uncommitted keys.
- Assertions sign `authenticatorData || clientDataHash`. The browser's supplied
  hash is used exactly. Credential Manager receives an empty `clientDataJSON`
  placeholder for the browser to replace with its original client data.
- The provider accepts web origins only from OS-supplied `CallingAppInfo` whose
  package and signing certificate pass AndroidX's privileged-caller validation.
  The browser validates the RP/origin relationship, including Related Origin
  Requests. An arbitrary app cannot claim a browser origin using a package name.
- Native Android app requests without an authenticated web origin are currently
  rejected. Digital Asset Links support is not implemented.
- A private approval activity receives system requests through explicit mutable
  PendingIntents. Random, single-use, expiring selections bind the complete
  request, client-data hash, caller identity and selected credential. Process death
  invalidates outstanding selections; restart the request in the browser.
- Stored credentials are discoverable and device-bound: **BE=0, BS=0**, `signCount=0`,
  UP/UV set only in responses released after consent and authentication. There is
  no claim of clone detection from counters. Registration uses `fmt: none` and a
  zero AAGUID; the website does **not** receive proof of StrongBox provenance.
- Public credential metadata is atomically stored in `noBackupFilesDir`; private
  keys remain in AndroidKeyStore. Corrupt/missing metadata fails closed and preserves
  existing keys. Process leases protect in-flight registrations during recovery.

The provider supports `credProps`. Unsupported optional extensions are ignored
without claiming results. Required unsupported protections, required large blobs,
enterprise attestation and payment-specific ceremonies fail. Websites requiring
attestation, synchronized passkeys, other algorithms or unsupported extensions may
not accept SwiftKey.

No NFC, Bluetooth or USB transport is implemented. The provider can receive requests
routed by Android, including system hybrid flows where supported; cross-device use
has not been physically verified. Third-party websites do not need the custom
SwiftKey authority. Two-phone pairing does not synchronize website passkeys.

iOS remains unavailable. Apple's credential-provider extension currently does not
allow device-bound passkeys, so an equivalent Secure Enclave policy needs a supported
platform path; changing backup flags would misrepresent the credential.
[Apple platform guidance](https://developer.apple.com/forums/thread/829541).

## Privileged caller trust snapshot

`res/raw/passkey_privileged_apps.json` is a bundled snapshot from Google's
[privileged caller list](https://www.gstatic.com/gpm-passkeys-privileged-apps/apps.json),
retrieved 2026-09-21. Original SHA-256:
`0891ee2507894999ead3eb4f42e17936a2e8ed8f8fd95592535c9811ef319481`.
Only entries with `build: release` were retained; empty app entries were removed.
This includes release browsers and the Google Play Services system hybrid delegate.
No network list update occurs during authentication. Review package/certificate
changes before updating the bundled trust snapshot; do not add debug certificates.

## Verification and physical acceptance

Host tests independently decode registration CBOR/COSE, reconstruct public keys and
verify real EC signatures. Storage tests exercise pending/committed recovery, RP and
key binding, metadata corruption, replay, cancellation and preservation of existing
keys. These tests use test-only ephemeral keys and do not prove StrongBox behavior.
Android instrumentation checks the manifest boundary, forged browser certificates,
invalid selections and product navigation. A conditional hardware test checks that
an unauthenticated StrongBox signature fails; it skips on unsupported devices.

The [isolated Vapor test server](passkey-test-server.md) uses the requested
[`brokenhandsio/swift-webauthn`](https://github.com/brokenhandsio/swift-webauthn) verifier
and browser-flow patterns from
[`Vapor-PasskeyDemo`](https://github.com/brokenhandsio/Vapor-PasskeyDemo). It stores only
in-memory test credentials and never opens authority state.

Physical acceptance still required:

1. Use `adb reverse tcp:18202 tcp:18202`, start the isolated server, and open
   `http://localhost:18202/passkeys/test` in a supported release browser on the phone.
2. Enable SwiftKey; create a credential through the real Android picker and prompt.
   Verify registration server-side, then sign in and verify the assertion.
3. Restart SwiftKey and the browser, keeping the test server alive; sign in again.
4. Cancel and fail biometric prompts, retry, and verify no signature is returned on
   failure. Attempt excluded registration and another RP/account; verify isolation.
5. Repeat against an independent website supporting device-bound ES256 passkeys.
   Test any desktop/system hybrid path separately before claiming it works.

Never substitute emulator software keys or mark synthetic cryptographic fixtures as
physical provider success. See [protocol diagrams](protocol.md).
