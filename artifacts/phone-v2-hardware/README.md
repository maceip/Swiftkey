# Two-phone v2 hardware acceptance

Physical devices: Pixel 11 Pro XL (font scale 1.3) and Xiaomi 15T Pro
(font scale 1.45). Both use Android StrongBox P-256 roots admitted by the
Vapor authority with the installed app's signing-certificate policy.

The authority at `http://127.0.0.1:18191` is isolated from the existing legacy
server at port 18088. USB/Wi-Fi ADB reverse routes each phone's loopback port
to this authority. Its public pin and zero-account baseline are in
`authority-baseline.json`. No accounts or identities were seeded by an operator.
Existing legacy identities and accounts remain separate.

## Final repaired APK: passed

APK SHA-256: `2a1a736512343cdf617bed94af2711d83f54f3035f5bcff3ce6559524a514667`.
Both installations retained all four existing private JSON files byte-for-byte
before launch; see the final install records in `../cupertino/android-hardware/`.
Both original hardware roots and identity IDs were retained through explicit trust
lease renewal. No operator seeded an identity, account, consent or credential.

The native Copy link / manual import flow completed mutual pairing in 102.4 seconds.
`final-comparison-verification.json` records both complete matching UI reviews:
authority, origin, audience, identities, full fingerprints, transcript hash and all
five comparison groups. The Pixel re-read the updated comparison after the
Xiaomi's first consent. `final-first-pair-consent.json` shows that one consent
alone left zero accounts, owners and credentials.

Both phones reviewed account **Pixel-Xiaomi**, reserved ID
`458ca6a0-a55d-4426-8f0c-04f44be3640a`, and policy
`two-owner-survivor-v1`. `genesis-review-verification.json` records the identical
owner set and policy on both screens. `after-first-genesis-approval.json` proves
the Pixel's approval alone left zero accounts and owners. The Xiaomi re-read the
updated proposal and approved it separately; `after-second-genesis-approval.json`
proves the atomic result: **one account, two active owners, zero credentials**.

`committed-receipt-verification.json` records the same verified native receipt on
both phones, including proposal digest and ledger sequence **1099**. Account
creation did not sign either phone in. `pixel-first-sign-in.json` then proves
one credential; `both-independent-sign-ins.json` proves **two separate epoch
credentials**, one for each owner, at ledger sequence **1111**. The checkpoint
independently verifies each root signature, authority signature and delegation
binding, and matches each owner key to its original hardware admission.
`signed-in-ui-verification.json` and the four reviewed `*-signed-in-*.png` images
show the native owner screens and verified epoch 124306 on both phones (Pixel
portrait/light/font 1.3; Xiaomi landscape/dark/font 1.45).

`final-expiry-verification.json` records automatic expiry and recovery of an
unjoined inspection on the final APK. Pixel polling samples retain identical
Join-button bounds without a background busy banner. Xiaomi samples establish
stable QR-button bounds before expiry and no background busy banner; expiry
legitimately replaces the invitation controls. See the Cupertino hardware index
for exact sample boundaries. The [deadline review](deadline-review.md) distinguishes
the successful timed run from broader human/accessibility timing validation.

## Evidence collected before the final interaction fixes

- `pixel/` and `xiaomi/` show independent hardware admission. Public fingerprints
  are `62138df796ff596897124c114787c81cc38e5ca0ce2e57589226518df64a7faf`
  and `6d215e88c19f9789a570d1b4ec921275e405df5f0c0550e73c54e9e2f3c15289`.
- The Xiaomi's first trust lease expired naturally. Explicit renewal preserved
  its identity and root epoch; the authority recorded renewal, not a new root.
- `comparison-verification.json` records a complete matching comparison on both
  screens under APK `43537a5`: authority, origin, audience, both full fingerprints,
  identities, transcript digest and all five comparison groups.
- `after-first-pair-consent.json` and `after-expired-first-pairing.json` prove
  exactly one consent for that transcript, zero accounts, zero active owners and
  zero credentials. That ceremony expired before the Pixel consent. A per-root
  `v2.pairing.confirmed` event alone does not mean mutual pairing is complete.

Those attempts exposed an expired-inspection screen without a recovery transition
and background refreshes that shifted controls or dropped actions. The shared
policy now refreshes unjoined inspection locally without signing or transport.
The Android host keeps background refresh layout stable and serializes one
original, explicitly requested action or QR presentation after the read. Changed
bindings reject; additional taps cannot enqueue duplicate approvals.

## Publication boundary

The public ledger checkpoints independently verify event hashes, links and
signed heads against the pinned authority key. Epoch-credential checkpoints also
verify root and authority signatures when credentials exist.

Private QR/link capabilities, configuration/journal contents, tokens and signing
keys are not published. The invitation travels through the native Copy link and
native manual-import UI, with the clipboard value held privately in the test
process. Optical camera scanning is not established by these records.

The final repaired-build expiry, mutual consent, genesis and independent sign-ins
passed on this isolated authority. Optical QR scanning, interrupted/restarted v2
ceremonies, response loss and replacement were not exercised in this run. No v2
workload submission is claimed: that path is not exposed by the current v2 native
host. Selected native controls were exercised; this does not establish physical
coverage of all 127 Compose Cupertino surfaces or a production authority cutover.
