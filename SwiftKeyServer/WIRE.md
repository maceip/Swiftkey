# SwiftKey local authority HTTP contract

The backend uses Vapor/Swift. The framework migration preserves this wire
contract and the authority/SQLite storage schema. Duplicate Authorization headers
are rejected, and compressed request bodies are not automatically decoded.

Server: `127.0.0.1:18088`; Android uses `adb reverse tcp:18088 tcp:18088`.
Transport: JSON; Swift `Data` fields use padded standard base64, and `UInt64`
fields use unsigned JSON numbers. Error responses are non-2xx JSON
`{"code":"stableCode","error":"description"}`. Workload replay is
`replayedWorkload`/HTTP409; bad workload signature is `invalidSignature`/403,
revoked membership is `revokedDevice`/403, and failed attestation is
`attestationRejected`/403. HTTP/network failures are not protocol rejections.

Core models and canonical encoding live in `../SwiftKeyCore`. Root signatures
are P-256 ECDSA DER over raw `ChallengeEnvelope.canonicalBytes()` with SHA-256
exactly once. Public keys are 65-byte uncompressed X9.63 points. JSON bytes are
never the signed representation.

`GET /v1/time` returns `{unixTime,epoch,epochStart,epochEnd}` in Unix seconds.
Epochs last 14,400 seconds. `/health` reports readiness.

## Bootstrap

`POST /v1/bootstrap/challenge`, header `Authorization: Bearer <bootstrap token>`,
body `{}`, returns `{challenge:ChallengeEnvelope,attestationChallenge:Data}`.
The attestation challenge is SHA256 of canonical envelope bytes; pass it verbatim
to Android `setAttestationChallenge`. Persist the entire response before hardware
key generation. Repeated requests return the same pending response for 15 minutes.
An expired challenge fails explicitly; no route silently replaces a hardware key.

`POST /v1/bootstrap/enroll`, same bearer, body
`{challenge:ChallengeEnvelope,certificates:[Data],proof:Data}`. Certificates are
leaf-first. The hardware key signs canonical challenge bytes as possession proof.
Returns `{accountID,deviceID,publicKey,serverPublicKey}` (`EnrollResponse`).

The initial provisioning token creates exactly one initial account/device.
An admin-created account's one-use `enrollmentToken` uses these same routes,
scoped to that account and its reserved first device. Its expiry is 900 seconds
after account creation; obtaining a challenge does not extend that deadline.
The admin token is not an enrollment credential. A lost-response
retry may carry a fresh randomized ECDSA proof, but must retain the exact original
challenge and certificate key and must prove possession again. It cannot create
a second device or reset an account.

## Device authorization and epochs

`POST /v1/challenges`, body
`{accountID,deviceID,operation:Operation,payloadHash:Data}`, returns the
`ChallengeEnvelope` directly. Only an active member may obtain a challenge;
validity is 5 minutes. The payload hash is SHA256 of the exact operation payload's
canonical bytes. Successful authorization advances that device's sequence and
consumes all competing pending challenges for that sequence atomically.

`POST /v1/epochs`, body
`{delegation:EpochDelegation,authorization:RootAuthorization}`, returns
`EpochCredential`. Authorization operation is `issueEpoch`; it binds the exact
canonical delegation. The server accepts only its current epoch, configured
audience and correct previous accepted epoch-key hash. A different leaf in an
already-issued epoch is rejected. For a lost response, a fresh root authorization
for the same delegation returns the persisted exact credential and consumes the
new challenge. The client must retain its private leaf across this retry.

`POST /v1/workloads`, body
`{credential:EpochCredential,workload:SignedWorkload}`, returns
`{accepted:true,payloadHash:Data}`. The server checks current membership and
attestation trust, root and server credential signatures, current epoch, exact
account/device/audience/domain bindings, leaf signature, bounds and nonce replay.
Successful nonce consumption is persisted before acknowledging the request.

`POST /v1/credentials/verify`, body `{credential:EpochCredential}`, returns
`{accountID,deviceID,epoch,checkedAt,validUntil,credentialHash:Data}` after current
membership, retained attestation policy and credential checks. `credentialHash`
is SHA256 of the credential's canonical bytes. This is a point-in-time,
non-consuming receipt: it neither submits a workload nor consumes its nonce,
and cannot authorize a later workload by itself.

## Pairing, revocation and recovery

1. New device obtains `POST /v1/pairings/challenge` with `{accountID}`. Response
   is the bootstrap challenge shape. Persist it before creating a new attested key.
2. New device sends `POST /v1/pairings/enroll` with `EnrollRequest`. Response is
   `PairingCandidate {accountID,deviceID,publicKey,expiresAt}`. This is a pending
   verified candidate, not account membership. It expires after 15 minutes.
   The first accepted identity is immutable. Repeating the original key and
   certificate identity returns the existing candidate; substituting a different
   identity fails, including concurrent enrollment attempts. Candidate trust is
   revalidated at approval/recovery, followed by current authorization and
   candidate checks before commit.
3. Existing member approves the exact candidate using `POST /v1/pairings/approve`
   with `MembershipRequest {change,authorization}`. `change` is
   `DeviceMembershipChange(accountID,deviceID,publicKey,operation:addDevice)`;
   the existing root signs an `addDevice` challenge for its canonical bytes.
   Returns `{accepted:true}` after atomic enrollment.
4. New device obtains an active-member `enroll` challenge for
   `DeviceMembershipChange(accountID,deviceID,publicKey,operation:enroll)`, signs
   with its own hardware root, and posts the `MembershipRequest` to
   `/v1/pairings/confirm`. Returns `EnrollResponse`; persist enrollment only after
   this confirmation. A candidate cannot obtain this challenge before approval.

`POST /v1/devices/revoke` takes `MembershipRequest` with operation `revokeDevice`,
the target deviceID and `publicKey:null`. Another active member must authorize.
The target's outstanding epoch credentials stop working immediately.

`POST /v1/recovery` takes `RecoveryRequest {change,authorization}`. `change` is
`RecoveryChange {accountID,lostDeviceID,replacementDeviceID,publicKey}`. A surviving
member signs a `recoverDevice` challenge for these exact canonical bytes. The
server atomically enrolls a verified, unexpired replacement candidate and revokes
the lost member. Recovery requires a previously enrolled surviving device.

## Local admin API and console

The console is `GET /`; `/app.js` and `/style.css` are public static resources.
They contain no credentials or registry data. All `/v1/admin/*` endpoints require
`Authorization: Bearer <admin token>`. The admin token must differ from the
initial bootstrap token. Missing/wrong/bootstrap credentials return 403 before
account lookup or query/body interpretation. With valid admin authorization,
unknown accounts return 404 and malformed requests/pagination return 400.
Responses have `Cache-Control: no-store`; the console uses a restrictive
same-origin CSP and keeps the supplied bearer only in page memory.

The website is now a Swift `WorkspaceView` evaluated by an isolated server-side
`ViewHost`. JavaScript is a generic DOM/event adapter. The browser session routes
below retain Swift presentation state; they do not introduce another authority
database or change device membership authorization.

| Route | Response |
| --- | --- |
| `GET /v1/admin/status` | `AuthorityStatus` |
| `GET /v1/admin/accounts` | `{accounts:[AccountSummary]}` |
| `POST /v1/admin/accounts`, body `{label:String}` | HTTP 201 `{account:AccountSummary,enrollmentToken:String,expiresAt:UInt64}` |
| `POST /v1/admin/accounts/:id/enrollment-invitation`, no body | HTTP 200 same provisioning response, for an admin-created account with no device records |
| `GET /v1/admin/accounts/:id` | `AccountSummary` |
| `GET /v1/admin/accounts/:id/devices` | `{devices:[DeviceSummary]}` |
| `GET /v1/admin/accounts/:id/epochs` | `{epochs:[EpochSummary]}` |
| `GET /v1/admin/ledger?after=0&limit=100` | `LedgerPage`; optional `accountID` filter |
| `POST /v1/admin/workspace`, body `WorkspaceQuery` | `WorkspaceOverview`, a consistent public application snapshot |
| `POST /v1/admin/ui/sessions` | HTTP 201 `BrowserWorkspaceResponse`; creates a transient view session and loads state |
| `POST /v1/admin/ui/sessions/:id/events`, body `BrowserEventRequest` | Updated tree/revision and explicit effects |
| `DELETE /v1/admin/ui/sessions/:id` | HTTP 204; clears that transient session |

`BrowserWorkspaceResponse` is `{sessionID:String,revision:UInt64,tree,effects}`.
Nodes contain `{type,id,props,modifiers:[{kind,args}],children}`. Every
`PropValue.int`, including a callback ID or ARGB color, is a decimal **string**
in this renderer transport; this avoids JavaScript precision loss. This does
not alter the protocol's signed canonical encoding or ordinary DTO integers.

`BrowserEventRequest` is `{revision,events:[{id:String,kind:String,value?:String}]}`.
Kinds are `void`, `string`, `bool`, `double` and `int`; non-void values are strings.
The browser sends edited field bindings before the activating callback. The
server validates the complete batch against the current session/revision,
callback type and enabled tree before invoking Swift closures. Evaluation is
serialized, concurrent session actions are rejected, and a stale response/action
does not trigger an automatic mutation retry. Sessions expire after 30 minutes
idle; at most 16 coexist. Disconnect clears transient secrets/drafts, not records.

Effects are `{kind:"copy",text}` or
`{kind:"download",filename,mediaType,text}`. They occur only for explicit actions.
An enrollment-bundle download contains a bearer and must remain private;
credential/ledger exports contain public protocol data. Admin credentials stay
in transport memory and are excluded from serialized SecureField values.

Account labels are trimmed/NFC-normalized and must contain 1–120 UTF-8 bytes
without control characters. Creating an account returns the enrollment bearer
only in this provisioning response; the server persists its hash, not the bearer. It expires
in 900 seconds, permits the first real hardware enrollment and is never included
in account lists, event details or later reads. The existing native client uses
it as `ClientConfiguration.bootstrapToken`. There is no admin endpoint that
substitutes for root-authorized rotation, pairing, revocation or recovery.

The invitation-reissue route reserves a fresh device ID for the same empty
admin-created account and atomically invalidates its unused prior invitations and challenges.
An account with any active or revoked device records rejects reissue with
`accountNotPending`/403. The special initial/global-bootstrap account is also
ineligible, preserving its original provisioning state. A key attested to an old challenge cannot be rebound by
issuing a new token; explicit client provisioning recovery is required, with no
silent hardware-key replacement. The returned bearer is again shown once and
never appears in subsequent reads.

Public DTOs are defined in [Core AdminModels.swift](../SwiftKeyCore/Sources/SwiftKeyCore/AdminModels.swift):

- `AccountSummary`: `accountID`, `label`, `createdAt`, `status` (`pending` when
  no device has enrolled, `active` with an active device, `inactive` when all
  enrolled devices are revoked), `deviceCount`, `activeDeviceCount`, `imported`,
  `canReissueInvitation` (computed by the authority; do not infer it from counts).
- `DeviceSummary`: `accountID`, `deviceID`, `publicKey`, `sequence`, `status`
  (`active` or `revoked`), optional `enrolledAt`, `revokedAt`, `lastEpoch`.
- `EpochSummary`: `accountID`, `deviceID`, `epoch`, `publicKey`, optional
  `previousPublicKeyHash`, `validFrom`, `validUntil`, optional `issuedAt`, `status`
  (`current`, `expired`, or `revoked`), complete public `credential`.
- `AuthorityStatus`: `serverPublicKey`, `unixTime`, `epoch`, `epochStart`,
  `epochEnd`, `accountCount`, `activeDeviceCount`, `revokedDeviceCount`,
  `credentialCount`, `ledgerHead`, `storage:"sqlite"`, `schemaVersion:2`.

`LedgerPage` is `{events:[LedgerEvent],nextAfter:UInt64,hasMore:Bool,head:SignedLedgerHead}`.
The `after` cursor is exclusive; pages sort by increasing global sequence.
`limit` is 1–200 (default 100). Use `nextAfter` for the next page. Filtered account
pages retain global sequence/hash links, so adjacent filtered rows need not be
adjacent global events. The head is always the global checkpoint.

A `LedgerEvent` contains `sequence`, `timestamp`, `kind`, optional `accountID`,
`deviceID`, `actorDeviceID`, public string-to-string `details`, `previousHash`
and `hash`. Its canonical domain is `authority-ledger-event-v1`: sequence,
timestamp, kind, optional IDs, detail count and NFC UTF-8-sorted key/value pairs,
then previousHash. `hash` is SHA256 of those canonical bytes and is excluded
from its own input. Details contain no private keys, enrollment bearers or raw
workload payloads. Migration records `authority.imported`, not invented past
operations. Legacy unknown timestamps remain absent.

`SignedLedgerHead` contains `{sequence,hash,signature}`. The authority signs
Core canonical domain `swiftkey.ledger-head.v1`, UInt64 sequence, then Data hash
with P-256/SHA-256; the signature is DER and Data fields use base64. Verify using
the independently trusted authority public key. The signature authenticates the
checkpoint, but detecting whole-database rollback requires an externally retained
checkpoint or witness. The browser displays these public values; it does not
claim independent external witnessing.

An explicit enrollment export uses shared `EnrollmentBundle` JSON:
`{version:1,accountID,label,expiresAt,configuration:{serverURL,bootstrapToken,serverPublicKey,audience,expectedAccountID}}`.
The expected account must equal the invitation account. The bundle carries a
secret bearer and is never part of a public workspace snapshot or ledger. The
Swift operator compares its public-key pin to a separately supplied trusted file
before transferring it to an unconfigured Android installation. Export checks
the current clock; a previously loaded snapshot does not extend invitation life.

## Configuration and trust

See [README.md](README.md) for launch and evidence verification. The server pin
comes from `.state/server-public-key.txt`, provisioned out-of-band. An HTTP-returned
key is not the trust source. The executable accepts real Android attestation only;
Apple App Attest and software attestations fail closed.
