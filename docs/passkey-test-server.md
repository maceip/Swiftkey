# Browser passkey interoperability test

The opt-in Vapor test page runs standard WebAuthn registration and authentication against `brokenhandsio/swift-webauthn` **1.0.0-beta.1** (`909cf4193cde7d64196553c4245ab647a68aaaca`). The browser ceremony pattern follows [Vapor-PasskeyDemo](https://github.com/brokenhandsio/Vapor-PasskeyDemo), reviewed at `2d23601469d8c9736073a6bc49dd6a24492eff65`. This is an interoperability harness, not a production login service.

The standalone executable does not read any SwiftKey authority configuration, database, account, ledger, root key, owner session or workload credential. Its bounded actor stores test credentials and browser sessions only in memory. Restarting it forgets every registration. A passkey left in the phone's provider after a restart will no longer be recognized by this server.

## Run locally

From the repository root, in Bash:

```bash
source scripts/androidswiftui-env.sh
export SWIFTKEY_PASSKEY_TEST_ENABLED=1
export SWIFTKEY_PASSKEY_RP_ID=localhost
export SWIFTKEY_PASSKEY_ORIGIN=http://localhost:18202
"$SWIFTKEY_SWIFT" run --package-path SwiftKeyServer swiftkey-passkey-test-server
```

Open **http://localhost:18202/passkeys/test** in a browser that supports WebAuthn. Use `localhost` exactly; the server rejects a different Host header, including `127.0.0.1`. The standalone listener binds only `127.0.0.1`, never a public interface. It requires an explicit unprivileged localhost port. No admin/bootstrap secret is needed.

For an authorized Android device connected through ADB:

```bash
adb -s DEVICE_SERIAL reverse tcp:18202 tcp:18202
```

Open the same `http://localhost:18202/passkeys/test` URL in the phone's browser. Localhost is the browser's development secure-context exception. An ordinary HTTP LAN address is not a substitute. Enable SwiftKey in Android's credential-provider settings, then:

1. Enter a disposable test display name and select **Create passkey**.
2. Choose SwiftKey if the browser offers multiple providers and complete the phone's verification prompt.
3. The page must report **Passkey registered**. Registration alone does not authenticate a session.
4. Select **Sign in with passkey**, select the saved credential, and complete verification again.
5. The page reports **Signature verified** only after the independent server accepts the fresh challenge, origin, RP hash, user handle, UP/UV flags, counter and signature.
6. **Clear test sign-in** clears only this temporary browser session's signed-in name. It does not delete the phone's passkey or change SwiftKey account membership.

A browser/provider cancellation or a server rejection stays visibly unsuccessful. A successful software fixture test is not evidence that Android settings, browser integration, biometric confirmation or StrongBox have been exercised on a physical device.

## Configuration and HTTP contract

The existing `swiftkey-server` also installs these routes when all three environment variables above are set. It uses a separate in-memory store; it never maps passkeys to existing SwiftKey accounts. Prefer the standalone executable for isolated acceptance work. With the authority executable, the configured origin must correspond to its actual browser-facing port/HTTPS reverse proxy.

When the flag is absent or `0`, no passkey routes are installed. Partial or malformed configuration fails startup. The RP ID must equal the configured origin hostname. HTTPS is accepted by the reusable adapter; plain HTTP is accepted only for `localhost`. Origin paths, credentials, queries, fragments and wildcards are rejected. The standalone executable intentionally does not implement TLS or proxy configuration.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/passkeys/test` | Browser page; external script and stylesheet |
| GET | `/passkeys/test/bootstrap` | Establish/reuse a temporary HttpOnly, SameSite=Strict cookie and return its CSRF token |
| POST | `/passkeys/test/registration/options` | Body `{ "username": "Test phone" }`; returns `{ ceremonyID, publicKey }` |
| POST | `/passkeys/test/registration/verify` | Body `{ ceremonyID, credential }`; checks a standard registration response |
| POST | `/passkeys/test/authentication/options` | Body `{}`; returns fresh discoverable-credential request options |
| POST | `/passkeys/test/authentication/verify` | Body `{ ceremonyID, credential }`; verifies a standard assertion |
| POST | `/passkeys/test/signout` | Body `{}`; clears the temporary signed-in display name |

POST requests require the exact configured `Origin`, one session cookie, `Content-Type: application/json` and `X-SwiftKey-Test-CSRF` from bootstrap. The page handles those details. All byte fields in WebAuthn wire responses are unpadded base64url. Missing `userHandle` is rejected because this harness uses discoverable credentials. No fallback username lookup is performed.

Credentials use ES256/P-256. Options require discoverable credentials and user verification; the server independently requires UP and UV. Registration checks `id == rawId == embedded credentialId`; authentication binds the stored key and user handle and enforces counter advancement when nonzero. Backup eligibility is immutable, and backup state cannot be set without eligibility. Cross-origin/embedded ceremonies and authenticator extensions are intentionally unsupported in this bounded harness.

Challenges expire after 120 seconds, are consumed on verification attempts, and bind to their session and ceremony type. New options supersede that session's pending options. Sessions last 30 minutes. Limits are 100 sessions, 200 credentials, 200 pending ceremonies, 120 API requests/minute globally, 40/minute per known session and 131,072 body bytes. Restart to clear a full test store. Rate/session checks occur before body collection; responses are `no-store` and the page disallows framing and inline scripts.

**Attestation boundary:** the pinned upstream package supports only `fmt: "none"` here. The RP therefore does not verify Android Key Attestation or prove StrongBox provenance. Backup flags and UV are verified protocol assertions, not independent hardware attestations. The Android provider's hardware checks must be tested separately. This test does not implement NFC, CTAP USB HID, BLE transport or FIDO certification.

## Validation and provenance

```bash
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" test --package-path SwiftKeyServer --filter SwiftKeyPasskeyTestTests
"$SWIFTKEY_SWIFT" test --package-path SwiftKeyServer
```

The tests produce actual P-256 assertions and cover a successful HTTP registration/authentication round trip, required options, replay, session/CSRF binding, expiry, superseded challenges, duplicate registration, counter rollback, wrong RP/origin/challenge/user handle, invalid signatures, inconsistent IDs and flags, oversized bodies and security headers.

`SwiftKeyServer/Tests/SwiftKeyPasskeyTestTests/Fixtures/android-engine.json` is public test output from the actual Kotlin WebAuthn engine using an ephemeral software signing key. It contains no private key. Swift's separate RP library verifies that engine's registration and assertion, including the original browser client data reattached after Android's provider hash-only operation. This fixture is an engine interoperability check, not a hardware claim.

The library's Apache-2.0 license/notice and the demo's MIT license are retained under `SwiftKeyServer/ThirdPartyNotices/`. The browser UI is a new implementation using the existing SwiftKey design tokens. Bundled font licenses remain with the test page's resources.
