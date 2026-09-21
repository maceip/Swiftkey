# SwiftKeyApplication

Shared Swift workspace behavior for the server-rendered web workspace and native
views. This package depends on SwiftKeyCore and SwiftKeyClient; authentication, storage,
HTTP and hardware keys belong to service and platform adapters.

Implement `WorkspaceService` with real authority operations, construct
`WorkspaceStore(service:)`, and send typed `WorkspaceAction` values. Render
`await store.snapshot()`. The store handles account selection, validated account
creation, server-authorized invitation replacement, ledger pagination, and
credential verification receipts. `verifyCredential` checks current authority
authorization without submitting or consuming a workload nonce.

`WorkspaceSnapshot` contains public records only. Enrollment invitations and
configuration bundles are held separately in memory, returned by provisioning
actions, and cleared on dismissal, account change, session clearing, or detected
expiry. Do not log or persist action results as workspace state. Explicit bundle
export checks the current clock, includes the pinned authority key, and binds
the client configuration to the invited account using `expectedAccountID`.

A successful mutation can be followed by a failed refresh. Its action result
still has `operationCommitted == true`, retains the issued handoff, and explains
that only the refresh failed. The store never retries a mutation automatically.
Service adapters should throw safe `WorkspaceFailure` codes/messages; unknown
errors receive a generic message. Unauthorized responses clear the session.

`clearSession()` affects presentation state only. It never resets a hardware
identity or deletes server records. In-flight responses from the cleared session
cannot restore its data. Parallel actions are rejected while an operation runs.
When an authority reports `legacyProvisioningAllowed == false`, the store rejects
legacy account creation before a service call, including actions from an old
form. Older authorities that omit the field retain their legacy behavior.

Tests use an explicitly isolated service fixture and injected clock. They cover
actual action dispatch, secret exclusion from snapshots, post-commit read
failures, invitation expiry, pagination failure, verification binding, and
session races. Production sources provide no fixture service or static-success
fallback.

Run with the workspace's Swift 6.3.2 toolchain:

```sh
swift test
```

## Native v2 phone protocol

`PhoneProtocolModels`, `PhoneProtocolStore`, and `PhoneProtocolService` define
an independent application boundary for pairing-first onboarding and owner
add/replace review. `NativePhoneProtocolService` connects those surfaces to `PairingClient`, which
verifies canonical records, pinned authority signatures and both hardware proofs.
A store without an adapter remains explicitly unavailable.

The native service must persist each `requestID` and its exact signed request
before network submission, validate pinned authority/origin/audience, canonical
transcript and receipt signatures, current hardware evidence and membership,
and map only verified results into public `PhoneProtocolSnapshot` projections.
The presentation store is intentionally in-memory; it does not replace the
required durable client recovery journal. Adapters must restore the outstanding
request on restart and never auto-retry a mutation with a new request identity.
The adapter must also treat `rotateUnjoinedSecret`, `replaceGenesis` and
`rejectProposal` as exact revision-bound protocol operations, not local edits.

The store serializes actions, rejects stale review bindings, prevents expired
approval and browser signing, and preserves original request identity after
an ambiguous response. Its read recovery action reuses that identity; an
unknown result never authorizes another mutation. Session clearing prevents
late responses from restoring old state. Public projection checks reject
receipt mismatch, account/binding rollback, changed unchanged-owner roots,
unrelated approval participants and invalid owner-count deltas. These checks
supplement authoritative validation; adapter assertions such as receipt
`verified` are not themselves cryptographic proof.

A verified terminal response clears the pending request identity. Local
pre-submit rejections remain known failures; they do not invent an ambiguous
network write. Restarting a cancelled addition retains the account's original
commit evidence. Sign-in and epoch issuance may be retried independently of
that already committed membership. Projection tests cover those transitions,
declining an unjoined invitation, retained-root renewal and failed admission.

`PhoneInvitationInput` is deliberately non-Codable and has redacted descriptions.
Do not log or persist the action containing it. QR/link presentation and camera
or manual input belong to explicit native host effects, outside public view
trees and snapshots. Sign-in requires a consistent verified commit receipt and
an active matching local root. A historical proposal deadline does not expire
a committed account. Browser projections can refresh public status but cannot
perform proof-authenticated result recovery. Standalone revoke, browser grant,
policy change and legacy-upgrade adapters remain gated. Retained-evidence trust
lease renewal is explicit; fresh attestation and root rotation remain unavailable.
