# Android phone pairing v2 — implementation and verification

The opt-in v2 path connects canonical Swift records, the transactional authority,
a durable native client, the shared phone screens and Android StrongBox/QR effects.
The authority's HTTP transport now uses Vapor/Swift; see the
[migration verification](../artifacts/vapor-migration/README.md).
It covers accountless admission, invitation inspection, mutual pairing, joint
account genesis, independent owner sign-in and epoch issuance, adding an owner,
replacing a lost owner, cancellation/rejection, invitation rotation, proposal
replacement, retained-evidence trust lease renewal and interrupted-request recovery.

## Enable on a separate test authority

Use a separate state directory when first exercising this build. Existing live
configuration and records were not changed during implementation. The server
configuration adds this explicit block:

```json
"pairingV2": {
  "enabled": true,
  "origin": "https://your-authority.example"
}
```

The origin must exactly match the externally configured HTTPS authority, with
no trailing slash, path, query or fragment. The local server still binds loopback;
use the existing HTTPS front end. A debug USB test can explicitly use
`http://127.0.0.1:18088` with `adb reverse tcp:18088 tcp:18088` on each phone.
Do not use that debug origin for a remote deployment.

Enabling v2 permanently retires unused legacy first-enrollment provisioning in
that state directory and advances its persistent schema to version 3. Older
authority binaries reject that schema; disabling v2 neither downgrades it nor
reopens provisioning. Old exported invitations cannot enroll later. Existing enrolled legacy owners retain their
legacy records and supported operations. V2 accounts reject legacy governance
routes. A legacy-to-v2 account upgrade is not implemented. Inconsistent pre-release
schema 1/2 snapshots containing v2 records are rejected and require an explicit
operator migration; no such live state was created by this work.

## Provision each Android app

Build with `bash scripts/androidswiftui.sh android-build`. In the app, open
**Pair phones · v2**, then the trusted authority configuration sheet. Provide
public configuration obtained independently of any pairing QR:

```json
{
  "serverURL": "https://your-authority.example",
  "serverPublicKey": "BASE64_UNCOMPRESSED_P256_AUTHORITY_KEY",
  "audience": "swiftkey-authority-v2",
  "workloadAudience": "swiftkey.local"
}
```

Use the authority's `server-public-key.txt` from a trusted provisioning channel.
`workloadAudience` defaults to `swiftkey.local` and must match server configuration.
There is no administrative or bootstrap bearer in this file. Configuration locks
once a v2 key or journal exists; a pairing link cannot change the authority pin.
The v2 root uses a separate StrongBox alias, and its journal/configuration live in
Android `no_backup` storage. Existing v1 keys and files are preserved.

On A, prepare its hardware identity and create an invitation. On B, scan or
manually import it, inspect the signed context, prepare its identity, then join.
Compare both full fingerprints and the comparison code through a trusted channel.
Both phones explicitly approve pairing, then review and approve the same account
label and survivor policy. Only the second final approval activates both owners.
Each phone signs in independently and obtains its own epoch credential.

From the owner roster, choose Add phone or Replace lost phone. The candidate
reviews the account, all current owners and exact replacement target before
joining. Both participants approve the complete resulting roster. Replacing a
phone revokes the removed root's access; it never shares another phone's key.

## Recovery behavior

The client persists the exact public request payload and proof before submission;
the invitation capability stays transient. A timeout keeps
that request pending and disables further mutations. Refresh/recovery authenticates
the original request result. For a committed pairing, account or membership
ceremony, the client verifies both accepted hardware proofs and its own saved
approval. A signed negative result consumes a
new root sequence so the missing original cannot commit later. It does not
silently repeat the approval. Invitation and owner-session secrets are transient;
a lost invitation is explicitly rotated only while unjoined, and a lost session
requires a separate sign-in.

## Evidence and remaining gates

Local test/build evidence is recorded in [the evidence directory](../artifacts/phone-v2/README.md).
Cryptographic integration tests exercise real signing and the actual client,
application adapter and authority, with explicitly test-only software roots and
an injected attestation verifier. They do not establish physical StrongBox proof.

Final APK `2a1a736512343cdf617bed94af2711d83f54f3035f5bcff3ce6559524a514667`
was installed on Pixel and Xiaomi with all four existing legacy/v2 files preserved
before launch. Against an isolated Vapor authority on port 18191, both phones
completed StrongBox admission, mutual pairing, joint account genesis and independent
sign-in/epoch issuance. The first genesis approval left zero accounts; the second
committed one account with two owners. Independent checks verified ledger links,
signed heads, root/authority credential signatures and delegation bindings. See
[hardware acceptance and app screenshots](../artifacts/phone-v2-hardware/README.md).

This run used native Copy link and manual import. Optical camera scanning, v2
workload submission, process restart/response-loss recovery and replacement remain
outside that completed hardware scope. Selected control/layout checks do not
establish every product state on hardware. The existing legacy authority and
accounts remained separate; no existing account was migrated or revoked. The
older installed Xiaomi app's workload/replay proof remains a separate
[Vapor hardware check](../artifacts/vapor-hardware/README.md).

Standalone revocation, arbitrary policy changes, browser-login grants, fresh
attestation/root rotation, legacy account upgrade and iOS remain unavailable.
Their UI surfaces explain that boundary; no legacy fallback enables them.
