# SwiftKey pairing-first account protocol

**Status:** revision 0.2, 2026-09-20. Opt-in Android v2 implementation; physical two-phone acceptance pending.
**Protocol family:** `swiftkey-pairing-v2`.
**Decision:** two devices must pair before account creation; both become equal initial owners.
**Add phone:** a current owner and an attested candidate mutually pair, then both
approve one membership proposal before the candidate gains any account access.

This specification defines the opt-in pairing-first account model. The retained
legacy protocol is described in [PROTOCOL.md](../PROTOCOL.md). The implementation
and verification boundary is tracked in [PHONE-V2-BUILD.md](PHONE-V2-BUILD.md).
No live installation was enabled or migrated during this build.

The words MUST, MUST NOT and SHOULD describe requirements for implementing this
profile. Canonical vectors, typed wire envelopes and explicit rollout controls
are versioned with the implementation; physical acceptance is still required.

## 1. Product contract

1. Opening the app or website does not create an account.
2. Two devices establish a short-lived, authenticated pairing. Pending identities
   and pairing records are not accounts or memberships.
3. Both devices review and sign the same account-creation proposal.
4. The authority atomically creates one account and two equal owner memberships.
5. Each owner subsequently authenticates and obtains its own epoch credentials
   independently. Root keys, leaf keys and sessions are never shared.

There is no single-device signup, email bypass, admin-created consumer account,
or automatic account creation when a QR code is scanned. An administrative bearer
does not count as either owner's consent.

Normative defaults for this revision (any change requires a newly versioned policy):

- Both owners require accepted native hardware-attestation profiles. An ordinary
  browser software key cannot satisfy the initial-owner requirement.
- Ownership is independent authority, with survivor-authorized replacement:
  either owner can pair a replacement if the other is lost. This preserves the
  recovery direction in the current plan; it is not two-person joint control.
- Additional owners may be added later. There must be at least two non-revoked
  owner memberships after any successful membership mutation.

“Two devices” is the intended user ceremony. The server enforces two different
device IDs, different attested root keys and independent possession proofs.
Those checks alone do **not** prove different physical hardware: one StrongBox
can generate multiple keys. The native client SHOULD maintain one active owner
identity per installation and require the peer ceremony on another device.
Cryptographic enforcement of physical-device uniqueness is an unresolved
requirement if stronger assurance than this ceremony is needed; do not invent
that assurance from key attestation or collect hardware identifiers implicitly.

## 2. What is taken from Marks

Reference: clean local `maceip/marks` checkout at
`5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0`, inspected on 2026-09-20.
This is source review, not a claim about Marks' deployed behavior or browser gates.

| Marks mechanism | SwiftKey adaptation |
| --- | --- |
| Pre-account scratch and pending-device records | Accountless, attested device identities and a pairing session; no scratch documents required |
| Random pairing ID, 256-bit secret, two-minute QR lifetime | Keep a high-entropy, short-lived, one-use rendezvous capability |
| QR secret in a URL fragment | Keep fragment transport and immediate removal; never log or persist the link |
| Signed grant binds exact pending device and key | Both roots sign the exact peer transcript, then the exact account genesis |
| One SQLite transaction claims scratch, consumes pairing and creates principal | One transaction consumes genesis approvals and creates the account plus both owners |
| Returning device signs a fresh origin-bound challenge | Use fresh hardware-root proof and current membership for owner authentication |

Important differences, supported by the implementation rather than inferred
from the UI:

- Marks explicitly permits [single-device self-bootstrap][marks-single]. SwiftKey
  omits that rail.
- Marks creates a phone `CONTROLLER` and browser `MEMBER`, not equal enrollment
  authorities. SwiftKey creates two `owner` memberships. See the
  [first-phone transaction][marks-bootstrap] and [capabilities][marks-capabilities].
- Marks uses browser P-256 software credentials and 64-byte P1363 signatures.
  SwiftKey retains its hardware-root policy and DER ECDSA representation; the
  two wire protocols are not interchangeable.
- Marks' [browser finalization][marks-finalize] occurs after account creation and
  can issue another session during its finalize window. SwiftKey requires both
  proofs before creation and makes creation-result retrieval idempotent. Retrieving
  a receipt does not issue a session.
- Marks' four-word accessibility capability is not adopted in this revision.
  The camera-free fallback carries the full high-entropy link. The comparison
  code below is not a login credential or a replacement for that secret.

The main reference is [Marks' authentication protocol][marks-protocol], with
[canonical pairing validators][marks-validator], [transaction handling][marks-tx]
and [device-session validation][marks-session]. We carry over the useful flow,
not its single-device escape hatch, capability asymmetry, or software-root trust.

## 3. Participants and trust boundaries

| Participant | Authority |
| --- | --- |
| Device A / device B | Each owns a non-exportable root and signs locally approved operations |
| SwiftKey authority | Validates hardware evidence, coordinates proposals, applies membership policy and commits the ledger |
| Website | Presents shared Swift views and relays requests; its process/session is not an owner root |
| Administrator | Operates the service and reads permitted diagnostics; an admin token cannot mint owner consent |

Account IDs are random server-generated UUIDs, independent of device IDs and key
hashes. Each root is associated with at most one account in this revision, matching
the current implementation's uniqueness rule. Two already-owned roots cannot
silently create another account or merge their accounts.

Production connections require authenticated HTTPS to the configured authority.
Native clients additionally validate a previously trusted authority signing key.
The authority's origin and signing-key hash are included in signed messages.
A QR link or HTTP response cannot install an arbitrary new trust anchor. Local
loopback plus an explicitly provisioned pin and USB forwarding remains a
development transport profile, not a production trust-bootstrap mechanism.

Android owner admission preserves StrongBox, key properties, application identity,
verified-boot policy, certificate-chain validation and revocation checks. Verification
is performed by the authority, consistent with [Android's attestation guidance][android-attestation].
Revalidating retained evidence is not a new measurement of current boot state.

Apple App Attest remains a separate proof kind requiring its own attestation,
assertion and counter verifier; it is not a generic Secure Enclave ECDSA callback.
The [Apple validation contract][apple-attest] remains the platform reference.
Until that adapter is implemented, the Apple profile MUST fail closed. A simulator,
browser Web Crypto key or server-generated key cannot stand in for the second owner.

The authority remains trusted to enforce state and availability. Signed owner
consents and ledger receipts make the declared authorization inspectable; they
do not prevent a malicious operator from replacing its entire service/database.
Independent checkpoint retention is still required for rollback detection.

## 4. Durable records and invariants

| Record | Required state |
| --- | --- |
| `DeviceIdentity` | Device ID; root kind/key/key epoch; original attestation evidence and challenge; trust receipt; proof sequence; lease expiry; account binding if any |
| `PairingSession` | Random pairing ID; immutable purpose/context; A identity; hashed rendezvous secret; expiry; revision; optional fixed B identity; immutable transcript hash; two consent records; status |
| `GenesisProposal` | Proposal ID; paired-session reference; reserved account ID; NFC label; authority context; exact owners; policy; nonce; expiry; hash; approval records |
| `MembershipProposal` | Proposal ID; pairing/receipt references; exact account context and before/after owner sets; add/replace operation; candidate and authorizer; expiry/hash; both approval records; status |
| `Account` | Account ID; creation time; genesis hash; owner policy; membership revision; lifecycle status |
| `OwnerMembership` | Account ID; device ID/root epoch; role=`owner`; enrollment/revocation times |
| `OperationReceipt` | Request ID and canonical request hash; outcome; committed result; ledger checkpoint |

The authority MUST preserve these invariants:

- Admission/pairing creates no account row or new membership, and grants the
  candidate no account list item, account data, epoch credential or owner session.
  An existing authorizer retains only the access it already held; the bounded,
  capability-authenticated account context in §10.1 is the candidate's sole
  pre-commit disclosure.
- A committed new account has exactly two initial owners with equal capabilities.
- Signer device IDs and root public keys are distinct. Two signatures from one
  key never satisfy two approvals, regardless of different aliases or labels.
- Both approvals bind the same immutable proposal hash, authority, policy,
  account ID and ordered owner set. The server cannot substitute any of them.
- Pairing secrets prove access to a rendezvous, not owner authority. Scanning,
  polling, displaying a comparison code or possessing an admin bearer cannot
  create an account without both accepted root proofs.
- Every new root operation checks its scope eligibility and uses a fresh
  challenge; §9 limits the historical receipt-only exception.
  Every state transition and replay decision is durable and atomic.
- A consumed pairing commits at most one genesis or membership mutation, never
  both. An unowned root is reserved against every competing live pairing, genesis
  or membership operation and cannot enter two accounts in a race. Owned roots
  can authorize only their own account and cannot act as unowned candidates.
- A proposal cannot add an owner as active before that candidate explicitly
  accepts the exact account, role and peer set.

## 5. Message format and signed bindings

Reuse [SwiftKey's canonical encoder](../SwiftKeyCore/Sources/SwiftKeyCore/Canonical.swift):
ASCII `SwiftKey`, binary-format version `u16(1)`, length-prefixed domain, then
schema-ordered fields. Binary-format version 1 is retained; the new domains
below identify protocol revision 2. Do not change existing v1 signed bytes.

Unsigned integers are u64 big-endian; text is NFC UTF-8; text/data lengths are
u32 big-endian. Nested records are length-prefixed canonical bytes. Owner arrays
have a u64 count and descriptors sorted by device ID's ASCII bytes. Identifiers
are canonical lowercase UUID text. Hashes/nonces are 32 bytes; Android public
keys are 65-byte uncompressed X9.63 P-256 points. Android signatures are DER
ECDSA over the raw canonical message using SHA-256 exactly once. Timestamps are
unsigned Unix seconds in UTC. Root key epochs begin at 1; revisions/sequences
never wrap. `audience` is the configured service identifier
`swiftkey-authority-v2`, checked against local configuration in every message.

New v2 JSON transports u64 values as decimal strings and `Data` as padded base64;
the generic browser must not round counters through JavaScript numbers. QR
secrets use unpadded base64url. These are transport rules, not JSON signing.
Unknown fields, enum values, duplicate object keys and noncanonical numeric
strings MUST be rejected by v2 decoders. Fixed-vector tests freeze this contract
before implementation is considered interoperable.

`authorityID = SHA256(authoritySigningPublicKey)` for this revision. Origin is
the configured canonical origin, with no path/query/fragment; clients compare
against configuration, not an origin copied from untrusted input. Labels are
metadata, normalized and validated before proposal creation, 1–120 UTF-8 bytes
without control characters. Editing a proposed label creates a new proposal and
invalidates previous approvals.

The following field orders are normative for the draft. `owners` contains the
canonical descriptors, not mutable display-name lookups.

| Canonical record / domain | Fields in order |
| --- | --- |
| `OwnerDescriptor` / `owner-descriptor-v2` | deviceID, rootKind, rootKeyEpoch, rootPublicKey, attestationReceiptHash, role (`owner`) |
| `PreEnrollmentChallenge` / `preaccount-enrollment-v2` | authorityID, origin, audience, challengeID, requestID, deviceID, rootKind, trustPolicyID, nonce, issuedAt, expiresAt |
| `AttestationEvidence` / `attestation-evidence-v2` | rootKind, certificateCount, ordered certificate DER bytes (Android: leaf to root) |
| `DeviceTrustReceipt` / `device-trust-receipt-v2` | authorityID, origin, audience, deviceID, rootKind, rootKeyEpoch, rootPublicKey, originalChallengeHash, evidenceHash, trustPolicyID, verifiedAt, leaseExpiresAt |
| `AccountRoster` / `account-roster-v2` | authorityID, origin, audience, accountID, accountLabel, ownershipPolicyID, membershipRevision, owners, issuedAt, expiresAt |
| `ExistingAccountContext` / `existing-account-context-v2` | accountID, accountLabel, ownershipPolicyID, membershipRevision, existingOwners, optional lostOwner descriptor |
| `PairingContext` / `pairing-context-v2` | purpose (`createAccount`, `addOwner`, `replaceOwner`), optional ExistingAccountContext canonical bytes |
| `CreatePairingIntent` / `create-pairing-v2` | authorityID, origin, audience, requestID, A descriptor, PairingContext canonical bytes |
| `PairingInspection` / `pairing-inspection-v2` | authorityID, origin, audience, pairingID, revision, A descriptor, PairingContext canonical bytes, issuedAt, expiresAt |
| `JoinPairingIntent` / `join-pairing-v2` | authorityID, origin, audience, pairingID, expectedRevision, inspectionHash, A descriptor hash, B descriptor |
| `PairTranscript` / `pair-transcript-v2` | authorityID, origin, audience, pairingID, revision, PairingContext canonical bytes, owners, nonce, issuedAt, expiresAt |
| `ProposeAccountIntent` / `propose-account-v2` | authorityID, origin, audience, pairingID, expectedRevision, pairReceiptHash, label, ownershipPolicyID |
| `ReplaceGenesisIntent` / `replace-genesis-v2` | authorityID, origin, audience, pairingID, expectedRevision, oldProposalHash, newLabel, newOwnershipPolicyID |
| `RenewLeaseIntent` / `renew-identity-lease-v2` | authorityID, origin, audience, deviceID, rootKeyEpoch, existingTrustReceiptHash |
| `AccountGenesis` / `account-genesis-v2` | authorityID, origin, audience, proposalID, pairingID, pairTranscriptHash, accountID, label, owners, ownershipPolicyID, initialMembershipRevision (`1`), nonce, issuedAt, expiresAt |
| `ProposeMembershipIntent` / `propose-membership-v2` | authorityID, origin, audience, pairingID, expectedPairingRevision, pairReceiptHash, PairingContext canonical bytes |
| `MembershipProposal` / `membership-proposal-v2` | authorityID, origin, audience, proposalID, pairingID, pairTranscriptHash, pairReceiptHash, PairingContext canonical bytes, authorizingOwner, candidate, resultingOwners, nextMembershipRevision, nonce, issuedAt, expiresAt |
| `MembershipReceipt` / `membership-receipt-v2` | MembershipProposal canonical bytes, authorizer approval digest, candidate approval digest, committedAt, membershipRevision, ledgerFirstSequence, ledgerLastSequence, ledgerHeadHash |
| `RootChallenge` / `root-challenge-v2` | authorityID, origin, audience, challengeID, requestID, deviceID, rootKeyEpoch, purpose, scopeID, payloadHash, sequence, issuedAt, expiresAt, nonce |
| `RootProof` / `root-proof-v2` | rootKind, RootChallenge canonical bytes, proof bytes |
| `OwnerSessionIntent` / `owner-session-v2` | authorityID, origin, audience, accountID, deviceID, rootKeyEpoch, clientRequestID, requestedScopes, requestedExpiresAt |
| `ResultLookupIntent` / `result-lookup-v2` | authorityID, origin, audience, operationID, originalActorDeviceID, originalPurpose |
| `OperationState` / `operation-state-v2` | scopeKind, scopeID, revision, status, objectHash, approvedSignerIDs, phaseExpiresAt, optional receiptHash |
| `SignedState` / `authority-state-v2` | authorityID, origin, audience, scopeKind, scopeID, revision, payloadHash, issuedAt, expiresAt |
| `ControlIntent` / `control-v2` | authorityID, origin, audience, scopeKind, scopeID, expectedRevision, operation (`cancel`, `reject`, `rotateUnjoinedSecret`), actorDeviceID |
| `PairReceipt` / `pair-receipt-v2` | pairTranscript canonical bytes, A consent digest, B consent digest, confirmedAt, expiresAt |
| `AccountReceipt` / `account-receipt-v2` | accountGenesis canonical bytes, pairReceiptHash, A genesis approval digest, B genesis approval digest, createdAt, membershipRevision, ledgerFirstSequence, ledgerLastSequence, ledgerHeadHash |

`RootProof` contains its typed root kind, the complete `RootChallenge` and proof
bytes. Android verifies a DER signature over that challenge. Apple would validate
the platform assertion envelope and stored counter, not reinterpret those bytes
as Android's signature. Accepted authorization records retain the complete
proof; receipt responses include both complete approvals so clients can verify
their digests. Authority state/receipt signatures are detached from their
canonical payloads. Hashes never replace possession proofs.

`attestationReceiptHash` is SHA-256 of `DeviceTrustReceipt` canonical bytes;
`evidenceHash` is SHA-256 of `AttestationEvidence`; an approval/consent digest is
SHA-256 of the complete accepted `RootProof` canonical bytes. Pair-receipt hashes
likewise exclude the detached authority signature. A/B in receipt tables means
the first/second descriptor in the sorted owner array, not which phone scanned.
Save the first accepted proof as the receipt's immutable evidence even if a
retry supplies a different valid ECDSA signature for the same authorized operation.

ID/scope arrays use a u64 count followed by sorted, unique canonical text fields;
optional fields use the existing one-byte 0/1 marker followed by length-prefixed
data when present. `SignedState.payloadHash` commits to `OperationState` canonical
bytes; `objectHash` commits to the current intent/transcript/genesis/membership
proposal, and the
corresponding object accompanies the state. `scopeKind` is `identity`, `pairing`,
`genesisProposal`, `membershipProposal` or `operation`. Status is a closed enum
from §9 for pairings/proposals; admission/lease/login operations use `PENDING`,
`COMMITTED`, `REJECTED` or `EXPIRED`. Polling signatures expire after at most
60 seconds, independently of the phase deadline in `OperationState`; terminal
state remains reportable after that phase expires. `AccountRoster` and
`PairingInspection` have detached authority signatures over their own complete
canonical bytes, and MUST be validated before signing an intent that uses them.
Receipt lease renewal does not rewrite an older receipt hash or extend a pairing
that already captured that receipt. Root kind/profile and trust-policy identifiers
must be recognized; unknown profiles cannot select a permissive verifier.

`PairingContext.existingAccountContext` MUST be absent for `createAccount` and
present for `addOwner`/`replaceOwner`. `lostOwner` MUST be absent for `addOwner`
and present only for `replaceOwner`, as an exact descriptor in `existingOwners`.
The latter is the complete sorted non-revoked roster at the signed membership
revision, not just the two ceremony participants. `PairTranscript.owners` always
contains exactly the two ceremony participants. `resultingOwners` is the full
sorted roster computed by adding the candidate and, only for replacement,
removing that exact lost root. The candidate must be absent from the old roster;
the authorizer must remain in the new roster. Both clients recompute this delta.
All descriptors include the root epoch, so a device ID alone cannot retarget it.
Account labels are display metadata bound into this ceremony, not account identity;
a later rename cannot change the signed historical snapshot. Renewing a trust
lease does not increment membership revision or rewrite a captured descriptor;
validate captured receipts as authentic historical receipts and enforce the
signing participants' captured lease deadlines. Current roster equality compares
immutable device ID/root kind/epoch/key/role, not a newly renewed receipt hash.
The context retains its original receipt hashes. Membership, ownership policy
and owner-root epoch changes MUST increment `membershipRevision`.

The server-issued `RootChallenge.payloadHash` is SHA-256 of the exact canonical
operation payload. For pair/genesis/membership consent that payload is the exact
transcript/genesis/membership proposal above. Control operations use `ControlIntent`
and cannot change membership. Do not accept a free-form string action signed
without its object bindings. `rotateUnjoinedSecret` is available only to A in
`OPEN`; `reject` means terminal refusal of the presented peer/proposal, while
`cancel` means abandoning the current ceremony. Both require a bound participant
and have the same no-membership-change effect before commit. Secret rotation
increments pairing revision and invalidates the prior secret and inspection,
without extending the original QR deadline. It returns the new secret once.

Challenge scope is explicit: identity ID for pairing creation/lease renewal,
pairing ID for join/confirm/propose/genesis-replacement or pairing control,
proposal ID for genesis/membership approval or proposal control, account ID for
owner-session creation, and original operation/request
ID for result lookup. The authority verifies that the actor is eligible in that
scope; a caller cannot change scope merely by supplying another `payloadHash`.
Join challenge issuance additionally requires the live rendezvous capability and
the exact inspected context, even though B is not bound yet. A successful join
consumes the right to select B atomically with B's identity reservation.
Result retrieval accepts only participants already bound to that stored operation.
The closed `RootChallenge.purpose` values for this revision are `createPairing`,
`joinPairing`, `confirmPair`, `proposeAccount`, `replaceGenesis`, `approveGenesis`,
`proposeMembership`, `approveMembership`, `control`, `renewIdentityLease`,
`authenticateOwner` and `getResult`; each maps to exactly one payload schema.
In particular, the common `control` purpose still binds its explicit operation
and object in `ControlIntent`. V1 epoch/workload purposes do not become v2
membership authorization just because the same root signs them.

## 6. Accountless device admission

Before showing a peer's fingerprint, the native app MUST possess its **final
attested root**. Today's legacy display key is not eligible if enrollment later
replaces it with another key.

1. The app requests a pre-enrollment challenge with a fresh, locally persisted
   admission request ID. The authority allocates a random
   device ID and a 15-minute challenge; it creates no account. It returns a
   random 256-bit preparation capability, storing only its domain-separated
   digest. The app persists the challenge and preparation state before key generation.
2. Android generates/reuses the root associated with that persisted preparation.
   New hardware generation binds the attestation to
   `SHA256(PreEnrollmentChallenge.canonicalBytes())`. It submits the certificate
   chain and a possession signature over the raw challenge.
3. The authority validates the exact issued challenge, current trust policy,
   chain and possession proof. After asynchronous trust checks it rechecks
   expiry/consumption and global key uniqueness inside the commit boundary.
4. It consumes the challenge and creates an unowned `DeviceIdentity` with a
   signed trust receipt. Exact retries return the same receipt. This is device
   admission, not account enrollment. A 15-minute candidate lease permits pairing.

A newly admitted identity starts at root key epoch 1 and root authorization
sequence 0; its first generic `RootChallenge` uses sequence 1. Issuing a challenge
does not advance that sequence. Accepting its proof does. Promotion into account
ownership carries the current sequence/platform counter forward without reset.

Admission is the exception to the generic root-challenge retry rule: no admitted
identity exists yet. `PreEnrollmentChallenge.requestID` binds the admission, and
the preparation capability authenticates its result retrieval. The app must
receive and durably save one complete preparation response before generating
the root. If that response is lost before any root exists, it may abandon the
allocation and request a new one; the orphan challenge expires and creates no
identity/account. Reusing an admission request ID for a different allocation is
rejected. After root generation, never abandon it merely to obtain a fresh challenge.

After admission has committed, a retry verifies the preparation capability and
possession signature against the original stored challenge/key, then returns
only the original public trust receipt. A consumed or now-expired challenge does
not block that receipt-only response. It does not extend the candidate lease or
admit new evidence. Changed attestation evidence is a new validation operation,
not an idempotent substitute. If the capability is lost, a fresh root-authenticated
result lookup is required; possession of the device ID or request ID is insufficient.

The preparation capability cannot approve pairing or genesis. Both peers need
fresh root proofs for those steps. Existing admitted, unowned roots may renew
their candidate lease using a fresh `renewIdentityLease` root challenge and
current validation of their retained evidence. That does not create a new
attestation or rewrite its original challenge.

An expired pairing does not delete a hardware key. Persist the original evidence,
identity receipt and current operation state so a new pairing can use the same
root. Missing local state, expired/revoked hardware evidence or an unknown
identity requires an explicit recovery/re-admission path; fail closed until it
is available. Never silently regenerate the root to make retry succeed. The
authority must retain enough identity metadata for lease renewal; garbage
collection cannot discard a bound identity or make its key reusable elsewhere.

## 7. Pairing ceremony — no new membership yet

This section describes `createAccount`; §10.1 supplies the additional bindings
and eligibility rules for `addOwner`/`replaceOwner`. The same rendezvous and
mutual-confirmation mechanics apply to all three purposes.

Default lifetimes: the OPEN/PEER_BOUND phase expires **120 seconds** after QR
creation. Its `PairTranscript.expiresAt` is that original deadline; joining does
not restart the clock. Root-operation challenges last at most **120 seconds**
and no later than the enclosing phase/proposal deadline. Both pair consents must
be accepted before the original pairing deadline.

Successful mutual confirmation creates a new, authority-signed `PairReceipt`
whose expiry is `min(confirmedAt + 300, leaseA.expiresAt, leaseB.expiresAt)`.
Here the leases are the trust receipts captured by the signed peer descriptors,
not newer leases obtained in the meantime. An existing owner obtains a current
trust receipt before starting or confirming the ceremony under the same retained
evidence validation; its ownership does not waive this trust lease.
This is a separate established-pair lease, not an extension or rewriting of the
signed transcript. In PAIRED state it becomes the session's phase deadline.
`AccountGenesis.expiresAt` is at most `min(issuedAt + 300, PairReceipt.expiresAt)`;
replacing a proposal cannot extend the pair receipt. Both accepted genesis
consents and the account commit must occur before that fixed genesis deadline.
The server clock controls acceptance; the comparison is `now < expiresAt`.

1. A signs a `createPairing` request. Its payload contains the authority context,
   request ID, A's descriptor and `PairingContext` with purpose `createAccount`. The authority checks
   A's live unowned identity and reserves it for one pairing.
2. The authority returns a random pairing ID and 256-bit rendezvous secret once,
   retaining only `SHA256(canonical("pair-secret-v2", pairingID, secret))`.
   A displays an app-approved-origin link:

   ```text
   https://<configured-origin>/pair#v2.<pairingID>.<base64url-secret>
   ```

   URI fragments are separated before dereferencing, as specified in
   [RFC 3986 §3.5][uri-fragment]. The landing adapter removes the fragment
   immediately and sends its contents only to the configured authority over
   HTTPS. Fragments can still be exposed to the page, history, screenshots or
   extensions; do not call them intrinsically confidential. Disable link
   analytics/third-party scripts; use a no-referrer policy. Never put the secret
   in a query string, server access log, public ledger or telemetry.
3. B scans or imports the full link, validates the origin, and obtains its own
   final admitted root. `inspect` requires the secret and returns a signed,
   bounded `PairingInspection` of A and the exact operation. B verifies the signed
   inspection, authority, expiry and allowed context before proceeding. Inspection
   is not acceptance. A copied link cannot change its purpose or destination account.
4. B explicitly chooses **Pair these devices** and submits the secret plus a
   fresh `joinPairing` root proof binding the pairing ID, inspection hash, A
   descriptor hash and B descriptor. The authority atomically fixes B; a different peer cannot
   overwrite it. Replacing a peer requires cancelling and creating a new session.
5. The authority issues the immutable `PairTranscript`. Both apps verify its
   signature, their own root binding, the peer descriptor, origin and expiry.
   They display the same peer details and comparison code:
   first 10 bytes of `SHA256(transcript)` as five groups of four hex digits.
   This 80-bit display is a human comparison aid, not a bearer credential or
   independent proof of proximity. Users compare it through a trusted channel.
6. Each app explicitly confirms the peer and signs a fresh `confirmPair`
   `RootChallenge` bound to the same transcript hash. A secret holder without
   either root cannot supply those consents. One-sided approval leaves a pending
   session and grants no rights.
7. After both valid consents, one transaction records `PAIRED` and a signed
   `PairReceipt`. It retires the rendezvous secret; subsequent access is
   root-authenticated. The account table is still unchanged.

Device labels are hints, not authenticated human identities. Confirmation must
name the signed purpose: **Create account**, **Add phone**, or **Replace lost
phone**, with the exact destination account for the latter two; do not silently
switch between these operations. QR phishing and deliberate approval of a remote
attacker remain social risks. The app must show both the operation and peer
fingerprint before signing, not approve merely on camera recognition.

## 8. Joint account creation

Either paired device may propose the label. The authority verifies `PAIRED`,
reserves a random account ID and returns a signed `AccountGenesis`. Reserving an
ID is not insertion into the account table, and cannot authorize other APIs.

There is at most one live genesis proposal per pairing. An exact retry returns
it. A conflicting label/policy proposal returns 409 until a participant explicitly
replaces it with a fresh root-authorized operation binding the old proposal hash
and current pairing revision. Replacement cancels every old approval, increments
the revision and issues a new proposal ID; it cannot extend the pair's deadline.

Both devices display the label, the two owners, authority and recovery policy.
They verify the pair receipt and every genesis binding locally, then explicitly
choose **Create account with these two owners**. Each signs a fresh
`approveGenesis` root challenge for the exact genesis hash. The first approval
is durably recorded but creates no account.

Upon receiving the second approval, the authority revalidates both identities
and executes one state/SQLite transaction:

1. Require the pair/proposal to be live, exact, unconsumed and not cancelled.
2. Require both distinct root approvals and current root epochs/trust policy.
3. Require neither root to have an account binding; validate reservations again.
4. Require the explicit `two-owner-survivor-v1` policy and exactly two owners.
5. Insert the account with membership revision 1 and both equal owner memberships.
6. Bind both identities to that account and mark the proposal/pair `COMMITTED`.
7. Store the immutable result, consent digests and replay/idempotency records.
8. Append `account.created`, two `owner.enrolled` events and `pairing.committed`
   within the same existing snapshot/event/commit transaction. Persist the
   resulting receipt payload before exposing success.

No observer may see the account with one initial owner. A failure commits none
of these changes. Each client verifies and persists the signed `AccountReceipt`
before treating itself as an owner; it checks its own approval and the exact
other owner, policy and account ID. Receipt-signature generation may be retried
over the same persisted payload if the response is lost; a newly generated ECDSA
signature is not a new account or a new receipt payload.

```mermaid
sequenceDiagram
    participant A as Device A
    participant S as Swift authority
    participant B as Device B
    A->>S: Accountless attestation + possession
    B->>S: Accountless attestation + possession
    A->>S: Signed createPairing
    S-->>A: Short-lived QR/link
    A-->>B: Out-of-band QR/link
    B->>S: Secret + signed joinPairing
    S-->>A: Signed transcript with both roots
    S-->>B: Same transcript
    A->>S: Explicit pair consent
    B->>S: Explicit pair consent
    S-->>A: Pair receipt; no account exists
    S-->>B: Pair receipt; no account exists
    A->>S: Propose account label
    S-->>A: Account genesis
    S-->>B: Same account genesis
    A->>S: Signed genesis approval
    B->>S: Signed genesis approval
    Note over S: Atomic account + two owners + ledger commit
    S-->>A: Committed account receipt
    S-->>B: Same committed account receipt
```

## 9. Replay, concurrency and failure behavior

Pair states are `OPEN → PEER_BOUND → PAIRED → COMMITTED`; any pre-commit state
may become `CANCELLED`, `REJECTED`, `EXPIRED` or `INVALIDATED`. Genesis and
membership-proposal states are `PROPOSED → PARTIALLY_APPROVED → COMMITTED`,
with those same pre-commit terminal states. `INVALIDATED` identifies a root,
membership or policy change; it is not a recoverable transport error.
Peer/genesis replacement never reuses old approvals. No terminal operation is reopened.

Each root-authorized mutation carries a random `requestID`, included in its root
challenge; admission uses the separate preparation rules in §6. The authority
records `(actor, purpose, requestID, payloadHash)` and the accepted challenge/proof.
“Exact retry” means the same canonical authorized operation, not identical JSON
or ECDSA signature bytes. A different valid DER signature over the same challenge
is permitted; a changed payload or identity is not. Evidence substitutions still
require their own complete attestation validation.

Every newly accepted root operation requires
`challenge.sequence == storedSequence + 1`.
An unaccepted challenge becomes stale after any different operation for that root
advances the sequence; reissue a challenge for the unchanged payload and request
ID. Multiple issued challenges never reserve or advance the sequence. An exact
already-accepted retry is recognized before this freshness check. The client
serializes signing per root and persists the request ID, canonical payload and
proof before sending. Platform assertion counters and authorization sequences
are separate monotonic values; both are checked and advanced atomically. No
sequence rule may invalidate a consent that has already been durably accepted.

For receipt-only replay, verify the presented original operation/proof against
the stored original signer key and accepted challenge, then return only its
persisted public result. Consumed/expired challenge status is allowed for this
branch; never apply the normal fresh-operation expiry check first. It cannot
replay the mutation, renew a lease, mint a session, return a session bearer, or
reconstruct an erased QR secret. A fresh authenticated `getResult` challenge is
the alternative when the original proof is unavailable. Session-creation replay
returns public outcome only; a lost session credential requires a new login
challenge, not reissuing it through the public receipt branch.

A fresh result lookup may also resolve an original request that was never
accepted. In one transaction the authority verifies the querying root, confirms
there is no accepted original operation, consumes the lookup sequence (making
all older challenges stale), and retains an actor/request/purpose rejection
tombstone. It returns a signed `OperationState` with scope `operation`, the
original request ID, `REJECTED`, the lookup-intent hash and no receipt or proofs.
The client clears only the exactly matching pending request after verifying
that signed negative result. It never infers non-commit from an unsigned error,
HTTP timeout or missing response, and never resubmits the approval automatically.

Pre-account and governance approvals need explicit sequencing, not two calls to
the current v1 `approvePairing`. On accepting an approval, atomically consume
its challenge, advance that root's authorization sequence and store the accepted
consent against the immutable proposal, including its acceptance time. Challenge
expiry is checked at acceptance, not again as the lifetime of an accepted consent.
Accepted genesis/membership consent remains eligible until its fixed proposal
deadline;
accepted pair consent can complete pairing only before the original transcript
deadline. A committed pair receipt remains usable until its own separate expiry.
Ordinary epoch issuance does not erase accepted consent. A relevant root-key
epoch change, cancellation, enclosing phase/proposal expiry or membership revision
change invalidates it. A trust-policy migration invalidates pending affected
ceremonies unless it explicitly preserves the signed profile and eligibility.
Hardware trust is still revalidated at commit. A response
lost before acceptance may require a fresh challenge; a response lost after
acceptance is recovered by request ID.

Use a separate account `membershipRevision` to bind governance proposals; do
not infer consent freshness from the current device sequence alone. Never lower
a threshold because an owner is offline or a key's attestation expired.

| Failure | Required result |
| --- | --- |
| Expiry/cancel before account commit | No account or membership; reservations released; roots retained locally |
| Cancel races with final approval | One serialized transition wins; cancellation after commit returns the committed receipt, not a rollback |
| Simultaneous final approvals/retries | One account, one logical receipt, one set of ledger events |
| A root participates in competing genesis proposals | Reservation/unique binding allows at most one commit |
| Attestation validation awaits I/O | Recheck identity, epoch, expiry, cancellation and reservation after the await |
| Disk failure | No success; follow the existing authority's fail-closed persistence behavior |
| Crash after commit, before HTTP response | Either root retrieves the same committed result using fresh authenticated proof |
| Peer disappears | Pending state expires; no one-owner account is created and no candidate is activated |
| Add/replace races with another membership change | First valid commit advances revision; all old-revision ceremonies become `INVALIDATED`; no automatic rebasing or approval reuse |
| Trust checking is unavailable | Preserve pending state until its deadline; show retryable unavailability; never treat outage as approval or extend signed expiry |
| Approval response is lost | Show result unknown, retrieve original operation result; never claim failed or start a replacement mutation automatically |

Preparation/pairing capabilities may be hashed at rest. Returning the initial
QR after a lost creation response requires either a short-lived encrypted result
cache or explicit authenticated rotation of an **unjoined** QR; do not claim that
hash-only storage can reproduce a random secret. If rotated, invalidate the old
secret atomically. Rotation is forbidden after B is bound. Public committed
receipts remain retrievable by a bound participant after ephemeral secrets are
purged. Receipt-only retrieval may prove possession of the stored historical
root even after its lease/membership expires or is revoked; it returns only that
operation's public result, never current private account data or credentials.
Retain historical verification keys, per-root-epoch sequence state and replay
tombstones so revocation does not make crash recovery impossible or reopen an
operation. `getResult` for that historical root is eligible only for a previously
bound operation and uses a fresh nonce/sequence; neither current membership nor
a renewed trust lease is required for this public-receipt-only scope. Signed state is refreshed
for polling; clients reject lower revisions and persist their highest observed
revision/checkpoint. A stale response cannot reset their progress.

## 10. Equal-owner authorization and recovery

The proposed policy ID is `two-owner-survivor-v1`; both founders sign it at
genesis. It applies identically to A and B—there is no primary controller.

| Operation | Required authorization |
| --- | --- |
| Read account | Current owner authentication or appropriately scoped session |
| Authenticate / issue own epoch | Fresh proof from that active hardware root; an epoch request additionally binds the exact leaf delegation |
| Execute own workload | Valid epoch credential plus that leaf's signature over the exact message; neither cookie nor credential possession alone suffices |
| Add an owner | One current owner + the candidate's explicit root acceptance of the exact account, role, policy and current membership revision |
| Replace a lost owner | One different surviving owner + replacement root acceptance; revoke lost root and add replacement atomically |
| Revoke another owner | One different active owner; reject if fewer than two non-revoked owners would remain |
| Change account ownership/recovery policy | Explicit proposal accepted by all current non-revoked owners under the old policy; no admin substitution for consent |
| Delete/merge account | Out of scope; no implicit route or ownership transfer |

### 10.1 Add phone and replace lost phone

Both are complete two-party ceremonies on an **existing** account. They MUST
NOT call the v1 approve-then-confirm flow: that flow makes the candidate active
before its final acceptance. Existing legacy accounts cannot use these routes
until the explicit §15 upgrade exists; the UI displays that limitation. Adding preserves every current owner. Replacing
removes one named owner and adds one candidate in the same transaction; it is
not an add followed by a separate revoke.

1. A authenticates as a current owner and loads the current signed account
   roster/revision from `AccountRoster` (fresh for at most 60 seconds). The server
   rechecks the current revision when accepting the signed intent; a fresh
   response is never itself permission to act on later-changed state.
   A explicitly chooses `addOwner` or `replaceOwner`; replacement
   requires selecting an exact different, non-revoked owner/root epoch. A cannot
   replace itself. A signs `CreatePairingIntent` with that full account context.
   The server verifies current account policy/revision and A's root trust before
   creating the pairing. Neither an admin bearer nor an owner session alone can
   open this owner-authorized ceremony.
2. A transfers the §7 QR/link. It contains only pairing ID and secret. Possession
   permits bounded inspection of the context, including account label/ID, policy,
   owner roster, authorizer and any replacement target. It permits no general
   account read. The owner UI discloses this sharing scope before exporting the
   link. B admits or renews its unowned hardware root and verifies the exact
   `PairingInspection`; already-owned or reserved candidate roots are rejected.
3. B chooses **Pair with this owner** after seeing the operation and account.
   A and B join/compare/confirm as in §7. Both signatures bind the full context,
   not only the peer's key. The server rechecks account revision, A's membership,
   candidate reservation and exact lost-root membership at each transition.
   The returned `PairReceipt` grants B no membership, session or epoch credential.
4. Either bound participant signs `ProposeMembershipIntent`. The server creates
   exactly one immutable `MembershipProposal` from the stored pair context;
   callers cannot supply a different authorizer, target, account, policy or
   before/after roster. Its expiry is at most
   `min(issuedAt + 300, PairReceipt.expiresAt)`. Exact retries return the same
   proposal. Changing the operation, peer or lost root requires cancelling and
   starting a new pairing, not editing an approved proposal.
5. Each app independently verifies the pair receipt, recomputes the full roster
   delta and displays the exact account, survivor policy and resulting owners.
   Replacement names the root whose access will end. A explicitly chooses
   **Add this phone as an owner** or **Replace this lost phone**; B chooses
   **Join this account as an owner**. Each signs a fresh `approveMembership`
   challenge over the same complete `MembershipProposal`. A pair consent or
   original admission signature cannot substitute for either approval. Both
   apps show whose approval is recorded; the first approval leaves B inactive.
6. The second approval triggers validation of the stored authorizer/candidate
   proofs and current hardware trust, then a single commit rechecks everything
   below. An asynchronous trust check does not reserve a right to commit stale
   membership afterward.

The commit MUST atomically:

- Require a live paired session and exact proposal, both distinct accepted root
  approvals, unchanged policy and `membershipRevision`, and current authorizer
  membership/root epoch. Only the authorizer and candidate require current
  hardware trust for this operation; an offline/lost owner's failing trust is
  not a veto over survivor recovery.
- Require the candidate to remain unowned, globally unique and reserved by this
  ceremony. Carry its existing root sequence/platform counter forward.
- Require the replacement target, if any, still to be the exact distinct
  non-revoked owner in the signed roster. Compute and verify `resultingOwners`,
  with at least two distinct non-revoked roots. Addition has no revoke effect.
- Bind the candidate to this account and create its equal `owner` membership;
  for replacement, revoke the target in the same state update. Preserve the
  revoked root's account binding/history; its identity cannot be recycled into
  a different account. Increment `membershipRevision` exactly once.
- Invalidate other old-revision governance pairings/proposals/challenges. Close
  revoked-device sessions and root challenges. Online epoch/workload validation
  rejects the revoked membership even if its credential has not expired; any
  cached authorization must include and recheck the membership revision.
- Consume this pairing/proposal, store immutable `MembershipReceipt` plus both
  complete approvals and idempotency records, and commit one ledger group with
  `owner.enrolled`, optional `owner.revoked`, `account.membership_changed` and
  `pairing.committed`. Record before/after revisions, proposal hash and signer
  digests; expose success only after durable persistence.

A or B may reject/cancel before commit with a signed `ControlIntent`; the result
releases the candidate reservation and preserves its root. Cancel versus final
approval is serialized: cancellation that loses returns the committed receipt,
never claims that access was undone. A membership revision change ends this
ceremony as `INVALIDATED`; refresh the roster and obtain new user approvals in a
new pairing. A lost response is `result unknown`, followed by authenticated result
lookup using the original operation/proposal ID. It is not a failed addition.

Both participants verify and persist the same `MembershipReceipt`, their exact
approval and the expected owner delta before presenting success. B then signs
its own fresh authentication and epoch-delegation requests. Activation is the
membership commit, not successful delivery of a session/epoch; a failure in that
later step is shown as **Phone added; sign-in needs retry**, preserving the
committed receipt. A refreshes the roster from current signed state. Receipt
retrieval or a stale screen must never re-add a previously revoked candidate.
Other active owners see the ledger-backed owner change on their next authenticated
refresh; no out-of-band message or extra approval is implied by this policy.

### 10.2 Revocation and policy limits

With exactly two owners, bare revocation is rejected; the UI offers replacement
without first revoking anything. With three or more, a revoke operation must bind
the exact target root, full current roster/revision and resulting roster, then
apply the same atomic revision/session invalidation rules. The wire proposal for
standalone revocation and unanimous policy changes is outside this revision;
those routes remain unavailable until separately specified and tested. The
authorization table is not permission to reuse weaker v1 endpoints. Only
`two-owner-survivor-v1` is an accepted v2 account policy in this revision.

Replacement supplies the second owner in the same transaction. Keeping two memberships does not prove
that two devices are online, uncompromised, or currently pass attestation.

**Recovery tradeoff:** the service cannot prove that the other device was lost.
A compromised owner can enroll an attacker-controlled replacement and remove its
peer under this policy. Two-owner creation prevents unilateral signup, not later
unilateral recovery. Strict joint control would require a different signed policy
(for example both existing owners for changes) and a separately specified recovery
factor; it cannot silently coexist with one-survivor replacement. If every accepted
owner is lost or fails trust validation, this draft provides no administrative,
email or short-code recovery bypass.

Account governance is distinct from the authority's hardware trust floor. Owners
cannot approve a policy that accepts software roots, unsupported evidence or
revoked certificates against that floor. Updated official revocation evidence or
an explicit authority-wide security-policy migration may distrust a key without
owner consent; it does not authorize an administrator to replace that owner.
Record authority policy versions and migrations, and report resulting trust
failures honestly. Unanimous account consent is not an override for attestation.

## 11. Authentication after creation and web access

Account ownership, a login session and an epoch signing credential are different
objects. Neither the pair secret nor the genesis receipt is a bearer login.

An owner requests a fresh `authenticateOwner` root challenge bound to account,
device/root epoch, exact origin, requested session scopes and client request ID.
The authority checks current membership and hardware trust, verifies possession,
and atomically consumes the challenge and inserts the session. Native clients
store session material in platform-private storage. Browser sessions use Secure,
HttpOnly, SameSite cookies, exact Origin validation and CSRF protection for
cookie-authenticated mutations. Session rotation/revocation is durable; closed
ownership must also close or invalidate related live UI sessions.

For the website, a browser may request a device-approved login. It receives a
private, one-use redemption capability distinct from the QR capability shown to
the owner. The owner signs a grant binding the pending browser request, account,
origin, scopes and expiry. Only that original browser can redeem the grant.
This authenticates an owner-scoped browser session; it does not register the
browser as a second hardware owner. Ownership-changing operations still require
the applicable root consents, not merely its session cookie. The full browser
login wire contract is a follow-on deliverable before replacing admin login;
there is no claim that the current admin UI supplies this flow.

Existing four-hour epoch semantics remain unchanged: each root independently
delegates to its own software leaf, rotates lazily at the boundary and obtains
an authority-signed credential. Pairing does not share or jointly generate leaf
keys. Online verification still checks current membership and retained hardware
trust; revoked owners cannot use an otherwise unexpired credential. Governance
consent always uses roots, not epoch leaves. Original attestation evidence may
expire; a root/evidence-renewal protocol is required before claiming durable
account availability. Re-pairing cannot refresh a certificate's validity.

## 12. HTTP surface

The implementation uses a typed operation envelope rather than one route per
purpose. Canonical signed records and their domains remain distinct. These v2
routes never alias legacy membership mutations. Every successful operation
returns signed public state or a durable receipt; pending state is explicit.

| Method / route | Authorization and result |
| --- | --- |
| `POST /v2/identities/prepare` | Admission/rate limits; accountless challenge and preparation capability |
| `POST /v2/identities/attest` | Preparation capability, exact attestation and possession proof; identity receipt |
| `POST /v2/challenges` | Identity/purpose/scope/payload binding; nonce issuance grants no rights |
| `POST /v2/pairings/inspect` | Pairing ID and QR capability; signed bounded pre-join details |
| `POST /v2/operations` | Typed `OperationPayload`, matching `RootProof`, join capability when required |
| `POST /v2/accounts/roster` | Account ID and current owner bearer session; signed complete roster |

`OperationPayload` discriminates `createPairing`, `joinPairing`, `confirmPair`,
`proposeAccount`, `replaceGenesis`, `approveGenesis`, `proposeMembership`,
`approveMembership`, `control`, `renewIdentityLease`, `authenticateOwner` and
`getResult`. The proof must match the payload's purpose, scope and canonical hash.
`control` signs cancel/reject/rotate and the exact expected revision. `getResult`
accepts the original request ID or an operation scope belonging to that root;
lookup does not replay the mutation or return its transient invitation/session
secret. Retained `/v1/challenges` and `/v1/epochs` support only current-owner epoch
issuance for v2 accounts; their v1 governance operations are rejected.

`/v2/challenges` resolves operation scope and expected signer eligibility
before issuing a challenge. Unknown or expired secret-based inspections return
the same generic error; do not disclose identities for a guessed pairing ID.
Authenticated callers may receive `pairingExpired`, `peerAlreadyBound`,
`proposalMismatch`, `approvalRequired`, `identityAlreadyOwned`,
`membershipRevisionChanged`, `ownerMinimum`, `unsupportedRootKind`,
`operationCommitted`, `candidateReserved`, `trustUnavailable`,
`rootSequenceChanged`, `operationRejected` or `unsupportedPolicy`. Malformed
input is 400; invalid authentication 401/403;
state conflicts 409; authenticated expired operations 410; rate limits 429;
unavailable required trust material 503. Never interpret a network timeout as
either rejection or permission to create a new account automatically.

The implementation must enforce request/chain size bounds, concurrent pending
limits per identity/session and global admission bounds, and rate limits by
both source and scoped identity/pairing. Apply them to inspect, join, approvals,
root-challenge issuance and result polling, not just the initial QR endpoint.
Concrete operational limits must be configured and tested before exposure.

## 13. Ledger and storage

Use the existing Swift authority actor and
[SQLite commit boundary](../SwiftKeyServer/Sources/SwiftKeyAuthority/LedgerStore.swift).
For genesis, account rows and both memberships commit together. For addition or
replacement, the exact membership delta, account revision and session
invalidations commit together. In both cases sequence/counter changes, replay
records, public event additions and private snapshot checkpoint share that same
transaction; a failed ledger write cannot leave a candidate active.

Pre-account security events may use pairing/identity correlation IDs, but no
fictional account ID. They are not exposed in unauthenticated account history.
Public genesis events include the genesis hash, both owner IDs/key hashes,
policy ID, membership revision and consent digests. Secrets, attestation chains,
session cookies and private leaf/root material never enter public ledger details.
Store necessary original evidence/proofs in private authority state; public
receipts contain only the deliberately shareable proofs and identifiers.

Preserve transaction grouping so a consumer can establish that `account.created`
and both `owner.enrolled` events belong to one committed genesis. A signed head
authenticates the checkpoint; an exported checkpoint on the same machine is not
equivalent to an independently operated witness.

## 14. Shared Swift implementation boundary

The [phone UI surface contract](PHONE-UI-SURFACES.md) maps every ceremony stage,
review action, terminal state and unavailable feature to its required shared
component surface. Rendering these surfaces does not establish protocol
implementation or replace the acceptance gates below.

| Layer | Implementation responsibility |
| --- | --- |
| `SwiftKeyCore` | New accountless challenge/transcript/genesis/membership proposal/receipt types; typed proofs; policy and canonical validators; independent vectors |
| `SwiftKeyClient` | Persisted admission/pairing/genesis/addition/replacement state machine; root operations; receipt verification; exact retry/resume behavior |
| `SwiftKeyApplication` | Typed actions and states: no account, preparing identity, waiting for peer, reviewing pair, paired, reviewing genesis/membership delta, waiting for approval, result unknown, receipt verified, sign-in retry, owner, rejected/cancelled/invalidated/expired/error |
| `SwiftKeyUI` | Shared QR/link presentation, peer comparison, policy review, dual-approval progress and honest terminal/error states |
| Swift authority | Durable pre-account records, proposal/consent validation, transaction guards, owner sessions, role policy and ledger integration |
| Platform adapters | StrongBox/App Attest operations, local storage/network, camera/QR decoding, sharing/clipboard and rendering |

Protocol decisions, account eligibility, transcript comparison and recovery
policy stay in Swift. The browser remains a generic event/rendering adapter;
it cannot manufacture a hardware-root signature inside the server's ViewHost.
The UI must display **Pair another device** before offering account creation;
the server enforces the same gate independently of the button state.

Pairing necessarily expands the prior minimal identity-screen scope. Implement
it as a separate shared onboarding flow; after enrollment, the existing identity
screen may remain the name and public bytes. iOS implementation remains postponed;
two compatible native Android clients can exercise the first physical proof.

## 15. Compatibility and rollout

Legacy behaviors retained only outside v2:

- `Authority.createAccount` and v1 bootstrap allocate accounts too early.
- `ChallengeEnvelope` and `PairingCandidate` require an existing account ID.
- Current pairing approves membership before candidate confirmation.
- Current device records lack explicit owner policy/membership revision; one
  root may revoke its only peer.
- Existing browser `createAccount` actions and enrollment bundles support the
  old one-device provisioning flow and do not satisfy this ceremony.

Introduce v2 records and migrations explicitly. Do not overload `accountID`
with a pairing ID or invent a placeholder account. In pairing-first mode, block
new consumer account creation through `/v1/admin/accounts`, global bootstrap
and invitation-reissue bypasses. An admin may operate the service, not bypass
two-owner genesis. Keep any legacy protocol compatibility separately scoped
and visible; fail closed on version/profile mismatch.

Dispatch every membership mutation by the account's stored protocol/policy,
regardless of URL version. A v2 account MUST reject v1 pairing approval,
confirmation, bare revocation and recovery routes; they cannot bypass candidate
consent, genesis proof or the owner minimum. V1 governance challenge issuance
for v2 accounts is rejected as well. Retained epoch/workload codecs may be reused
only with the current account's membership and trust checks.

At a pairing-first cutover, one explicit migration retires the global creation
bootstrap and all unused v1 first-enrollment invitations/challenges, including
invitations already exported into app configuration. Reject their subsequent
challenge/enroll requests; blocking only invitation creation is insufficient.
Preserve pending legacy account records and their history as retired provisioning
records, not active paired accounts. Tell affected clients that a new two-device
ceremony is required; do not silently destroy any root they already generated.

Existing accounts remain honestly marked legacy; do not manufacture a second
founder, erase existing keys or rewrite history. Converting a legacy account
requires its current root authorization and a new candidate's explicit consent
to a versioned upgrade proposal, preserving account ID and recording
`account.ownership_upgraded`. Until that migration is specified and implemented,
leave those records under their declared legacy policy. This draft itself
does not upgrade or delete the current Pixel/Development/imported records.

## 16. Acceptance gates and remaining decisions

Acceptance requirements (local evidence and physical-device gaps are tracked in
[PHONE-V2-BUILD.md](PHONE-V2-BUILD.md)):

- Addition/replacement vectors include exact account ID/policy/revision, the
  complete old/new rosters, authorizer/candidate epochs and replacement target;
  neither a changed target nor a changed account can reuse any consent.
- Golden canonical vectors match independent verification, including DER/raw
  message hashing, exact field order, owner sorting and u64 JSON boundaries.
- One key, one consent, copied QR, software root, unsupported Apple profile,
  wrong authority/origin, changed label/policy/peer, and expired consent all fail.
- No pre-pairing or partially approved request changes account/device-owner
  counts or permits candidate credential/session issuance.
- Both root consents are required for pairing and genesis; account plus two
  owners appears atomically. Candidate acceptance is also required for later
  additions/replacement.
- Real concurrent approval/cancel/expiry/competing-genesis races commit at most
  once; include actual concurrent requests, not only sequential replay tests.
- Crash/restart and response-loss tests cover every persistence boundary,
  including lost QR response, first consent and committed-but-unacknowledged genesis.
- Routine epoch issuance does not invalidate already accepted proposal consent;
  membership/key/policy changes do. Sequence and platform assertion counters
  never reset during promotion.
- Adding/replacing owners enforces the selected policy and minimum; pairing
  and the first membership approval grant the candidate no account access.
  Unsupported standalone revocation/policy-change routes fail closed;
  removed-owner sessions and still-current epoch credentials are rejected online.
  Concurrent add/replace versus revoke/key/policy changes cannot reuse stale
  consent. A replacement must reject a changed target epoch, authorizer-as-target,
  already-owned candidate and candidate reserved by another account.
- Response-loss/restart at either membership approval and after membership commit
  returns one receipt/delta. Failure to issue a later session or epoch does not
  roll back or misreport the completed addition. Old receipts cannot reactivate
  a revoked owner. Root-sequence contention can retry without erasing accepted
  proposal consent; revised signed states cannot roll the client backward.
- V1 mutation/challenge endpoints cannot bypass v2 policy; unused pre-cutover
  first-enrollment tokens cannot activate a new one-owner account after cutover.
  Account approvals cannot override the authority's hardware trust floor.
- Both physical devices show matching transcripts, verify the final receipt,
  independently authenticate and issue credentials, and retain their own roots
  across restarts. Test device loss/replacement and record the takeover tradeoff.
- Browser/native views share the Swift state machine and show real pending,
  rejected and committed outcomes; operator/browser sessions never count as owners.
- Verify secret-free logs, hashed capabilities, request bounds, CSRF/origin
  defenses and abuse limits for every unauthenticated pairing surface.

The defaults are explicit: hardware-only owners and `two-owner-survivor-v1`.
Joint control or browser ownership requires a separately reviewed protocol/profile;
clients cannot select one through an arbitrary string. The physical-device
uniqueness assurance is limited to distinct attested roots and the user ceremony.
Full browser-login wire details, standalone revocation/policy-change proposals,
authenticated attestation renewal, legacy upgrade, production trust bootstrap
and public-service operational limits remain separate implementation gates.
Their absent routes/surfaces must say unavailable; none may be silently filled
by a single-device/admin bypass.

[marks-protocol]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/docs/AUTHN-AUTHZ-PROTOCOL.md
[marks-single]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/docs/AUTHN-AUTHZ-PROTOCOL.md#L315-L351
[marks-bootstrap]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-server/src/routes/auth.rs#L734-L847
[marks-capabilities]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-auth/src/device.rs#L8-L39
[marks-finalize]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-server/src/routes/auth.rs#L1000-L1038
[marks-validator]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-auth/src/pairing.rs
[marks-tx]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-server/src/db.rs#L52-L68
[marks-session]: https://github.com/maceip/marks/blob/5cdd79dc8cd6764978cd2fa7799d2b42ee3f76a0/crates/marks-auth/src/device_session.rs#L83
[android-attestation]: https://developer.android.com/privacy-and-security/security-key-attestation
[apple-attest]: https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
[uri-fragment]: https://www.rfc-editor.org/rfc/rfc3986#section-3.5
