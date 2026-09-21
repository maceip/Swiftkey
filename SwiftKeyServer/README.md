# SwiftKeyServer

The opt-in Android pairing-first v2 implementation is described in
[the build guide](../docs/PHONE-V2-BUILD.md). It uses the existing transactional
ledger, strict v2 envelopes, joint account genesis, dual-consent owner changes
and root-authenticated recovery. Enabling v2 retires unused legacy first-device
provisioning permanently. The legacy provisioning instructions below apply only
to authorities that have not enabled that cutover.

Browser adapter regression checks (from the workspace root):
`node SwiftKeyServer/browser-tests/adapter.test.cjs`.

A loopback Swift HTTP authority for the shared SwiftKey protocol, using Vapor 4.122.2,
Swift Crypto, Swift Certificates and SwiftASN1. The wire contract is in [WIRE.md](WIRE.md).

Vapor owns HTTP routing, middleware and the async server lifecycle. The existing
Swift authority and SQLite ledger remain the application and persistence layers;
this framework change requires no data migration. `SwiftKeyHTTP.configure(...)`
registers the same 37 routes, including the two bundled fonts. The executable
keeps its existing command-line options and binds only the validated loopback
address from configuration. Arbitrary Vapor serve flags cannot override it.

All routes use explicit bounded collection after authentication/rate guards,
with the existing JSON codecs and error envelope. Request decompression and
default request logging are disabled. Protocol routes reject duplicate
Authorization headers. Idle connections close after 30 seconds of inactivity.
See [migration evidence](../artifacts/vapor-migration/README.md)
for the server suite and a real HTTP executable/restart check.

## Run and inspect

From the workspace root:

```sh
scripts/swiftkey-protocol.sh server
# Separate terminal:
scripts/swiftkey-protocol.sh status
scripts/swiftkey-protocol.sh ledger
```

Open `http://127.0.0.1:18088/` for the local console. Connect with the private
`.state/admin-token` under `SwiftKeyServer/`; the server script creates it and
`.state/bootstrap-token` if absent. These are different credentials: the admin
token permits registry reads and account creation, while a bootstrap/enrollment
token permits enrollment only. Both files must remain owned private regular
files. The status/ledger commands read the admin token internally and print
only public responses, never the bearer value or a command-line token argument.

The browser keeps its admin token only in page memory, clearing it on disconnect
or page exit. This is an operator console, not a device-key consumer login.
The application runs through [SwiftKeyApplication](../SwiftKeyApplication/README.md)
and [SwiftKeyUI](../SwiftKeyUI/README.md): Swift owns state/actions, filtering,
form validation, labels, conditional controls and view composition. Each browser
session has an isolated `SwiftUICore.ViewHost`; a generic DOM adapter renders
its primitive tree and returns typed callbacks. This is server-driven Swift,
not a separate JavaScript application or browser WebAssembly runtime.

Views cover accounts, enrolled public roots, retained credentials, authority
snapshots and paginated ledger events. Explicit actions can verify a credential
against current authority policy or export public credentials/ledger pages.
Verification does not execute a workload or consume its nonce. The browser
does not generate private keys or replace root-authorized operations. Android
uses the same identity/public-key components; the full workspace compiles there,
but a native administrative session is not connected yet.

Creating an account returns one `enrollmentToken` valid for 900 seconds. The
console displays it only for that provisioning result; copy it before dismissing.
The shared store can export a private `EnrollmentBundle` with the endpoint,
audience, authority pin and expected account ID. A new client's
`ClientConfiguration.bootstrapToken` drives the original
`/v1/bootstrap/challenge` and `/v1/bootstrap/enroll` routes. The
server stores only the token hash, and account/ledger reads never return it.
Real hardware enrollment is still required; account creation alone adds no
trusted device. Existing-root authorization still governs epoch issuance and
membership changes.

For an admin-created account with no device records, **New enrollment invitation** issues a
fresh 900-second token and reserved device ID for the same account, invalidating
the previous unused invitations/challenges. Active and revoked-only accounts
and the special initial/global-bootstrap account cannot use this route. It does not replace a hardware key or rebind a key already
attested to an old challenge; that situation requires explicit client
provisioning recovery. The new bearer appears only in this response.
`AccountSummary.canReissueInvitation` is the authority's explicit eligibility
decision, so the UI does not offer replacement for an initial/bootstrap account.

## Swift operator enrollment handoff

From the workspace root, after installing the debug APK on a fresh authorized
USB device, create an account in the workspace and choose **Export enrollment
bundle**. Keep that download private. Before its invitation expires:

```sh
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" run --package-path SwiftKeyServer swiftkey-operator provision-android \
  --bundle-file /absolute/private/enrollment.json \
  --pin-file /Users/mac/SwiftKey/SwiftKeyServer/.state/server-public-key.txt \
  --serial DEVICE_SERIAL
```

The operator checks version/expiry, expected-account binding, the separately
supplied authority pin, loopback endpoint and device authorization. It refuses
existing client configuration or protocol state, writes private configuration
atomically via `adb run-as`, establishes the port reverse and launches the app.
It does not clear app data or replace a hardware root. A process launch is not
enrollment proof: refresh the workspace and check the actual accepted device
root and credential. The wrapper also invokes this Swift operator:

```sh
ANDROID_SERIAL=DEVICE_SERIAL scripts/swiftkey-protocol.sh configure-android /absolute/private/enrollment.json
```

An explicit bundle is required; the former global-bootstrap shortcut is removed.

The bundle contains a one-use secret; do not put it in logs, Git or public
evidence. Expired or partially completed provisioning needs an explicit recovery
decision. There is no QR/deep-link provisioning flow or public deployment.

Direct launch from this directory with Swift 6.3.2 is also supported:

```sh
swift build -j 6
.build/debug/swiftkey-server --config config/device.json \
  --bootstrap-token-file /absolute/private/bootstrap-token \
  --admin-token-file /absolute/private/admin-token
```

The checked-in policy uses loopback port 18088, the demo package and its debug
signing-certificate SHA256. `.state/server-public-key.txt` contains the authority's
base64 X9.63 public pin. Android reaches it through
`adb reverse tcp:18088 tcp:18088`. This is local development, not a public/TLS
or production-signing deployment. Mobile UI and iOS are unchanged by the console.

## SQLite state and ledger

`authority.sqlite3` stores a private singleton authority snapshot, public
`ledger_events`, and private `ledger_commits` checkpoints. One WAL transaction
with FULL synchronization/fullfsync commits the snapshot and its events together;
acknowledgment follows the commit. Every successful authority state mutation
has an event. Denied requests do not fabricate accepted-operation events.

Events chain canonical SHA-256 hashes. Commit checkpoints bind each snapshot's
digest to the event head and preceding commit. Startup validates the chains and
latest snapshot; subsequent commits check the existing snapshot and heads before
writing. SQL triggers reject updates/deletes to event and commit rows. The
owned 0700 directory, owned 0600 database/WAL/SHM files, NOFOLLOW checks and exclusive
process lock remain required. A persistence failure blocks subsequent mutations
until restart. This is private storage, not an exportable public database.

The first v2 open imports legacy `authority.json` only if SQLite has never
committed a snapshot. The JSON file remains untouched. The authority signing
key, device public keys/membership, challenges, sequences, nonce ledger and exact epoch
credential survive import. Imported accounts are marked `imported`; their
creation timestamp is the migration time. Only the latest epoch credentials
actually present in v1 can be imported, with unknown issuance times left absent.
One `authority.imported` event records the transition; no earlier history is
invented. Subsequent epoch credentials are retained as complete public history.
Afterward SQLite is authoritative; the preserved JSON is not updated or used to
silently overwrite an existing database.

Public status/ledger responses include a signed head. It signs canonical domain
`swiftkey.ledger-head.v1` followed by `(sequence, hash)` using the existing
P-256 authority key. A signed head authenticates a checkpoint, but it is not an
external witness: detecting a complete database rollback/rewrite requires
retaining/anchoring checkpoints outside the authority. Partial corruption checks
must not be described as complete rollback protection.

Security policy remains bound to stored state. Changing package, signer,
minimum version, audience or domain requires explicit migration. See
[WIRE.md](WIRE.md) for admin DTOs and the unchanged device-authorization routes.

## Attestation policy

The executable always constructs the real Android verifier. It fetches current
[Google roots and revocation material](https://developer.android.com/privacy-and-security/security-key-attestation)
over HTTPS at startup, caching for at most one hour. Existing-device authorization
and every workload recheck the original certificate chain against current cached
trust and policy; a failed refresh after cache expiry fails closed. The original
attestation challenge is retained. Expiry checks apply to all certificates; the
optional legacy factory-certificate expiry exception is not implemented.
The [official verifier](https://github.com/android/keyattestation/blob/main/src/main/kotlin/Verifier.kt)
passes its current instant to PKIX path validation. The older phone’s chain checked
on 2026-09-19 contains an RKP intermediate expiring
on 2026-09-27. Its existing root will fail authorization after that expiry under
this policy. The new Pixel chain’s expiry has not been inspected; this date
refers only to the historical chain. Authenticated root/evidence renewal before expiry is a remaining
lifecycle requirement; the server does not silently extend expired attestation.

Policy requires a valid Google-rooted chain, no revoked/suspended certificate,
the attestation extension nearest the trusted root, the exact enrollment challenge,
StrongBox attestation and key security levels, generated P-256 key origin, signing
purpose, SHA256, exact app package/signing digest, minimum app version, and locked
verified boot. The boot/app properties describe the attested key's generation;
rechecking its certificate does not create a fresh measurement of current boot.
Apple App Attest remains unsupported and is rejected.

The connected device emits KeyUsage's critical TRUE as 0x01. A narrow local patch in
[vendored Swift Certificates 1.20.0](Vendor/SwiftKeyCertificates/SWIFTKEY_PATCH.md)
accepts that encoding and preserves original signed TBS bytes. Other malformed
Boolean encodings remain rejected. Cryptography and X.509 path validation remain
in the maintained upstream implementation.

## Verification

```sh
swift test -j 6
.build/debug/swiftkey-server --config config/device.json --verify-attestation-file /path/to/public-evidence.json
```

From the workspace root, the production executable can also be checked with
disposable state and credentials:

```sh
python3 SwiftKeyServer/scripts/verify-vapor-server.py
```

This check requires the built debug executable and network access to Google's
official attestation trust endpoints. It exercises real HTTP, private logging,
v2 preparation and graceful restart without modifying `.state` or enrolling a
phone. HTTP tests use VaporTesting, including in-memory and actual socket requests.

The evidence JSON contains `{challenge:base64,certificates:[base64DER]}`. This mode
performs real attestation validation without opening authority state or creating
membership. It accepts no mock roots and does not weaken any policy.

Tests exercise atomic replay under concurrency, bootstrap and lost epoch-response
retries, exact-key pairing and membership confirmation, revocation/recovery,
persisted replay and receipts, policy-change rejection, trust refresh gating,
private state locking, negative Android ASN.1 policy cases, and preservation of a
real leaf's original signature through the KeyUsage parser compatibility change.
Fixture attestation implementations exist only in the test target. The production
executable exposes no fixture switch.

The pre-migration suite passed 44 tests, including invitation reissue and local font serving. Live
v1 migration preserved the existing Android identity, epoch credential and six
replay records; the browser rendered real registry data and created a pending
account, then reissued its invitation. Restart preserved the existing identities,
credential and replay state. Independent Python canonical hashing and OpenSSL
signature verification passed for ledger head 4. No new phone roundtrip is
claimed in this console phase. See [BUILD_STATUS.md](../BUILD_STATUS.md) for evidence.
The final private admin credential was verified after restart; the temporary
browser-test credential is revoked and the browser session was cleared.

The current shared-Swift integration passes **Core 16, Client 33, Application 9,
UI 9 and Server 50 tests**; desktop/Android targets build. The live SwiftUI
account action, enrollment-bundle export, Swift operator and Pixel StrongBox
handoff completed enrollment and epoch 124299 issuance. Current API/shared-UI
verification passed, tampered signatures returned 403, and verification left
ledger head 10 unchanged. App restart reused the credential.

Browser controls passed on an isolated SQLite copy: create/export, invalid-name
and expired-credential rejection, current Pixel verification and exact key copy.
The 1280px desktop and 320/390px phone layouts were inspected without mobile
overflow or console errors. The Android screenshot confirms the shared identity
screen; native dark colors still differ from the browser. A final installed
`forceDarkAllowed=false` build did not resolve that palette discrepancy. See current
[evidence](../artifacts/swiftkey-shared-swift/) and
[BUILD_STATUS.md](../BUILD_STATUS.md). Native administrative sessions, physical
pairing/recovery and iOS remain separate unfinished work.
