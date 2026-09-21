# SwiftKey protocol and local development

**Next protocol revision:** [Pairing-first account specification](docs/PAIRING-ACCOUNT-PROTOCOL.md)
is a draft requiring two paired devices and both root approvals before account
creation, with equal initial owner rights. The account-first/bootstrap behavior
documented below is the current implementation, not that proposed revision.

The [phone UI contract](docs/PHONE-UI-SURFACES.md) covers the proposed flow's
component surfaces. These components do not expose v2 routes or upgrade legacy
accounts. The legacy pairing implementation now fixes the candidate to its
first accepted hardware identity and rechecks candidate trust plus current
authorization after asynchronous validation, before approval/recovery commits.

SwiftKey's target is an attested hardware root that authorizes four-hour
software signing keys, with pairing, revocation and recovery authorized by
another active device. The Android identity screen displays only the project
name and the root's public bytes. The administrative workspace now uses shared
Swift application logic and view components. [BUILD_STATUS.md](BUILD_STATUS.md) separates implemented
code, host-fixture tests and exercised physical-device proof.

## Components

| Component | Responsibility |
| --- | --- |
| [SwiftKeyCore](SwiftKeyCore/README.md) | Canonical signed values, shared JSON DTOs, SHA-256/P-256, credential validation and epoch-key state |
| [SwiftKeyClient](SwiftKeyClient/Sources/SwiftKeyClient/ProtocolClient.swift) | Enrollment, delegation, workload and membership orchestration; injected transport, hardware and persistence callbacks |
| [SwiftKeyApplication](SwiftKeyApplication/README.md) | Shared workspace state/actions, service contracts, account selection/creation, invitation lifecycle, paging and credential verification |
| [SwiftKeyUI](SwiftKeyUI/README.md) | Shared identity/public-key components and `WorkspaceView`; composition, field bindings, filtering and conditional actions in Swift |
| [SwiftKeyServer](SwiftKeyServer/Sources/SwiftKeyAuthority/Authority.swift) | Online membership, attestation policy, credentials and SQLite state/event/commit transactions |
| [Browser adapter](SwiftKeyServer/Sources/SwiftKeyServer/Resources/app.js) | Generic RenderNode-to-DOM rendering, typed event transport, local auth shell, focus/scroll and explicit clipboard/download effects |
| [Swift operator](SwiftKeyServer/Sources/SwiftKeyOperator/main.swift) | Validate an account-bound enrollment bundle against a separately trusted server pin and transfer it to a fresh Android installation over USB |
| [Android adapter](AndroidSwiftUI/Demo/app/src/main/java/com/pureswift/swiftandroid/HardwareKeyStore.kt) | Android Keystore StrongBox generation/attestation and raw-message hardware signing |
| [Android Swift bridge](AndroidSwiftUI/Demo/App.swiftpm/Sources/AndroidProtocolBridge.swift) | JNI adapters and background protocol exercise, while retaining the minimal Swift UI |

The maintained Swift Crypto dependency is pinned to 4.5.2. Software P-256 keys
are appropriate for epoch leaves and the authority's signing key. They never
satisfy the hardware-root enrollment policy. Apple App Attest is represented
as a distinct authorization kind and rejected until its platform verifier is
implemented; it is not treated as an interchangeable ECDSA signature.

The website evaluates `SwiftKeyUI.WorkspaceView` through `SwiftUICore.ViewHost`
on the server. Each browser session has its own Swift store, drafts, callback
registry and revision. Browser JavaScript contains no account/device/epoch
application model: it renders primitive nodes and sends typed callbacks. This
is server-driven Swift UI, not browser WebAssembly. Android renders the same
identity/public-key components through ComposeUI; its build includes
`WorkspaceView`, but a native administrative service/session is not implemented.

## Signed data and lifecycle

JSON is transport only. `Data` fields use padded base64, public keys use exactly
65 uncompressed X9.63 bytes (`04 || X || Y`), signatures use ECDSA DER, and
integer fields are exact unsigned 64-bit values. Signed bytes use the versioned,
domain-separated binary encoding specified in [Core's canonical table](SwiftKeyCore/README.md#canonical-v1-encoding),
including fixed field order, length-prefixed NFC UTF-8/data and big-endian
integers. Canonical vectors and an independent OpenSSL fixture are checked in.

1. **Bootstrap:** the locally provisioned bearer credential obtains a
   15-minute account/device challenge. The client persists it before generating
   a key. Android attests `SHA256(challenge.canonicalBytes())` and proves
   possession by signing the raw canonical challenge using `SHA256withECDSA`.
   The server validates the Google chain/revocation state, exact challenge,
   StrongBox security levels, generated P-256/SHA-256 key properties, locked
   verified boot, package/version and app signing-certificate digest.
2. **Delegation:** an epoch is `unixSeconds / 14400`, valid only for
   `epoch * 14400 <= now < (epoch + 1) * 14400`. The client lazily generates one
   software leaf per epoch. Its delegation binds account, device, audience,
   epoch, leaf public key and optional SHA-256 of the previous leaf public key.
   A fresh five-minute challenge binds the canonical delegation's hash and the
   root's next sequence. The hardware root signs that challenge; the authority
   signs the delegation and complete root authorization together.
3. **Workload:** the leaf signs domain, audience, account, device, epoch,
   32-byte nonce and payload. The authority checks current membership, retained
   hardware trust, root/server/leaf signatures, exact current epoch and context.
   It durably consumes the nonce before returning acceptance. Signature validity
   alone does not establish membership or freshness.
4. **Pairing:** an attested candidate is pending until an active enrolled root
   authorizes the exact account, candidate ID and public key. The candidate
   then confirms membership using its own hardware root. Capturing an
   attestation or creating a candidate does not itself add an account member.
5. **Recovery:** a surviving active root signs a payload binding both the lost
   device and the exact replacement candidate/public key. Adding the replacement
   and revoking the lost device happen in one durable state change. Revoked
   devices cannot issue new credentials or execute old workloads online.

Each root operation binds its operation, account, signing device, next sequence,
nonce, expiration and payload hash. Membership, challenge consumption, sequence
advance and mutation are checked atomically. Asynchronous attestation checks
are followed by fresh state checks before committing. The authority's clock is
authoritative. A consumed issuance challenge's expiry does not shorten an
already issued epoch credential.

Android signing receives raw canonical bytes and hashes them exactly once.
Core's explicit prehashed API exists for callers that truly have a digest;
passing a digest to `SHA256withECDSA` would hash it again and violate the contract.

## State and trust

The Android attested alias is `swiftkey.attested-root.v1`; the earlier
`swiftkey.device-root.v1` demonstration alias remains intact. Root private keys
stay in StrongBox. Existing attested keys and their original challenges are
never silently replaced on retries. An expired bootstrap or lost required
state needs an explicit provisioning decision, not automatic root regeneration.

The client persists pending enrollment, accepted identity and epoch snapshots
in app-private atomic storage. A snapshot contains the **software leaf private
key**, never a hardware private key. Restoring validates identity, audience,
root/server pins, key correspondence and credentials. An unexpired leaf is
reused; an expired leaf rotates while retaining the previous-public-key hash.
Do not copy client state or bootstrap credentials into public evidence logs.

The authority holds a process lock and uses an owned private SQLite database.
Its snapshot, public event additions and private commit checkpoint are committed
together in one FULL-sync WAL transaction. Event hashes link prior events;
commit hashes also bind the private snapshot digest to that event head. Startup
checks the full chains and current snapshot. A persistence error prevents further
mutation until restart. State binds the app identity/version and workload policy; incompatible
configuration changes require explicit migration. Stored chains are revalidated
before hardware-authorized mutations and workload acceptance. Google trust
material is refreshed with a one-hour cache and unavailable fresh material
fails closed. Certificate expiry policy is currently conservative for all
chains, including legacy factory chains.

The older phone’s chain captured on September 19 has an RKP intermediate
expiring on **2026-09-27**. That retained chain will stop authorizing work then
under current policy; authenticated evidence/
root renewal is still required. This date has not been established for the new
Pixel chain. Certificate revalidation checks trust and
expiry of the original evidence, not a fresh measurement of current device
boot or app state. See [the server policy](SwiftKeyServer/README.md#attestation-policy).

The server public-key pin is provisioned independently through adb. A public key
returned inside an HTTP response is not itself a trust anchor. Test verifier
injection is confined to library/test construction; the executable has no
software-attestation mode.

The captured OEM leaf uses `0x01` for the X.509 KeyUsage extension's critical
Boolean. A narrow compatibility patch in vendored Swift Certificates 1.20.0
accepts that value only in this location. Certificate signatures still verify
the original signed TBS bytes; no signed bytes are normalized or rewritten.
The attested boot-lock Boolean remains strict DER. See
[the patch record](SwiftKeyServer/Vendor/SwiftKeyCertificates/SWIFTKEY_PATCH.md).

## Accounts, history and the local console

The console at `http://127.0.0.1:18088/` uses a separate admin bearer from
`SwiftKeyServer/.state/admin-token`. It keeps that bearer only in page memory,
never in a URL or browser storage, and clears it on disconnect/page exit.
Its public views cover accounts, device roots, complete retained epoch history
and paginated events. The browser never generates root/leaf private keys, nor
does admin access replace a device's hardware authorization.

`POST /v1/admin/accounts` with `{label}` creates a named pending account and
returns `{account,enrollmentToken,expiresAt}`. This token is shown only in that
provisioning result, is valid for 900 seconds, and never appears in lists or ledger
events. The shared Swift store can explicitly export an `EnrollmentBundle`
containing the endpoint, audience, public-key pin and `ClientConfiguration`,
including `expectedAccountID`. A new native client uses its bearer as `ClientConfiguration.bootstrapToken`
with the existing bootstrap challenge/enroll routes. Account creation does not
enroll a device or issue a signing credential. The original initial bootstrap
credential still applies to its original account.

An admin-created account with no device records can explicitly request a replacement via
`POST /v1/admin/accounts/:id/enrollment-invitation`. It returns a fresh one-use
token/reserved device ID and invalidates prior unused invitations and challenges.
An active, revoked-only or special initial/global-bootstrap account cannot use it. This replaces an invitation,
not a hardware key: a root attested to an old challenge needs explicit client
provisioning recovery and cannot silently be rebound.
The authority supplies `AccountSummary.canReissueInvitation`; presentation no
longer guesses eligibility from a zero device count.

Credential verification uses `POST /v1/credentials/verify`. It checks the exact
credential, current epoch, membership and retained attestation policy without
submitting a workload or consuming a workload nonce. Its receipt is a result at
the authority's checked time, not continuous authorization. Actual workloads
still require their own signature and replay check.

The first SQLite startup imports v1 `authority.json` only into a database with
no committed snapshot, preserving the original JSON untouched. Authority signing/device public
keys, membership, challenges, nonces and exact latest credentials are retained.
Imported accounts are marked as imported; their creation time is the import
time. Only latest epoch credentials actually available in v1 are imported;
unknown issuance times remain absent. One `authority.imported` event states
that provenance. No pre-migration event or lost older epoch history is fabricated.
Subsequent epoch issuance retains every public credential across rotation.

The public signed head covers Core canonical domain `swiftkey.ledger-head.v1`
and `(sequence,hash)`. It authenticates that checkpoint with the authority key.
It cannot alone detect replacement with a complete older database: external
checkpoint retention/anchoring is still necessary for complete rollback
detection. See [server persistence details](SwiftKeyServer/README.md#sqlite-state-and-ledger)
and the [admin wire contract](SwiftKeyServer/WIRE.md#local-admin-api-and-console).

## Endpoints

All POST bodies/responses use the shared [Wire.swift](SwiftKeyCore/Sources/SwiftKeyCore/Wire.swift)
DTOs. Non-success responses contain `{ "code": "...", "error": "..." }`.

| Method / route | Purpose |
| --- | --- |
| `GET /health`, `GET /v1/time` | Local readiness and server epoch time |
| `POST /v1/bootstrap/challenge`, `/v1/bootstrap/enroll` | First device; requires bootstrap bearer |
| `POST /v1/challenges` | Challenge for an enrolled root operation |
| `POST /v1/epochs` | Issue the server-signed epoch credential |
| `POST /v1/workloads` | Verify and consume one workload nonce |
| `POST /v1/credentials/verify` | Check credential authorization at the authority's current time without executing a workload |
| `POST /v1/pairings/challenge`, `/v1/pairings/enroll` | Attest a pending candidate |
| `POST /v1/pairings/approve`, `/v1/pairings/confirm` | Existing-root approval and candidate confirmation |
| `POST /v1/devices/revoke` | Revoke another enrolled device |
| `POST /v1/recovery` | Atomically replace and revoke a lost device |
| `GET /v1/admin/status`, `/v1/admin/accounts`, account `/devices` and `/epochs` | Admin-authenticated public state and history |
| `POST /v1/admin/accounts` | Create a pending account and one-use enrollment bearer |
| `POST /v1/admin/accounts/:id/enrollment-invitation` | Replace an unused invitation for an admin-created account with no devices |
| `GET /v1/admin/ledger` | Admin-authenticated cursor page and signed global head |
| `POST /v1/admin/workspace` | Load a consistent public workspace snapshot for a shared Swift application service |
| `POST /v1/admin/ui/sessions` | Create an isolated Swift view session and load its workspace |
| `POST /v1/admin/ui/sessions/:id/events` | Validate the current revision and enabled typed callbacks, dispatch Swift actions, return a new tree and explicit effects |
| `DELETE /v1/admin/ui/sessions/:id` | Clear the transient workspace session; leaves authority/device records intact |

## Reproduce the local Android exercise

Use the checked-in scripts; they select Swift 6.3.2, JDK 21 and NDK r27d without
changing the global Swiftly selection. From the workspace root:

```bash
scripts/androidswiftui.sh doctor
scripts/swiftkey-protocol.sh test
scripts/androidswiftui.sh android-run
```

In a separate terminal, leave the authority running:

```bash
scripts/swiftkey-protocol.sh server
```

The server helper creates distinct private bootstrap/admin token files if
missing. Open the local console and supply the admin token, or inspect public
responses without printing the token:

```bash
scripts/swiftkey-protocol.sh status
scripts/swiftkey-protocol.sh ledger
```

For a newly created account, use **Export enrollment bundle** in the Swift
workspace before its 900-second invitation expires. The download is a secret,
not public evidence. With the debug app installed on an authorized USB device,
run from the workspace root:

```bash
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" run --package-path SwiftKeyServer swiftkey-operator provision-android \
  --bundle-file /absolute/private/enrollment.json \
  --pin-file /Users/mac/SwiftKey/SwiftKeyServer/.state/server-public-key.txt \
  --serial DEVICE_SERIAL
```

The operator checks bundle expiry, account binding, the separately supplied
authority pin, loopback endpoint and device authorization. It refuses to replace
existing client configuration or protocol state. It creates the port reverse,
writes configuration atomically with private permissions through `adb run-as`,
and launches the app. It does not reset hardware keys or repair an expired
challenge. Launch alone is not proof: refresh the workspace and check that the
new account has the actual attested device root and issued credential.

The wrapper now requires an explicit account bundle and calls that same Swift
operator; the old global-bootstrap shortcut has been removed:

```bash
ANDROID_SERIAL=DEVICE_SERIAL scripts/swiftkey-protocol.sh configure-android /absolute/private/enrollment.json
```

The server listens only on
`127.0.0.1:18088`. Configuration pins
`com.pureswift.swiftandroidui` and this workspace's **debug APK** signing
certificate. A different signer requires an explicit policy/provisioning change.
No TLS/public deployment or production release-signing workflow is implied.

The current app starts enrollment/delegation/workload/replay checks in its
background runner. A process-wide coordinator serializes client-state work
across activity recreation. The key accessor prefers and locally validates an
existing attested root even offline; the runner validates it again before
publishing its bytes. Protocol progress is logged; the screen stays limited to
`SwiftKey` and public bytes. Inspect the current device/server evidence before
calling the run successful. Host fixtures, captured certificates, APK assembly
and screenshots do not replace server acceptance, actual workload execution or
physical pairing/recovery. iOS work remains postponed until the user connects
and authorizes work on a physical iPhone.
