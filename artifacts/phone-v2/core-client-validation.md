# Core and client validation

Pinned Swift 6.3.2 host tests passed: Core 26, Client 47. Full output is saved in
`core-tests.log` and `client-tests.log` in this directory. These are local software
tests; they do not establish physical StrongBox attestation or deployment.

Core covers 46 independently generated Python vectors across all 27 canonical
records, strict JSON and decimal UInt64 decoding, detached signatures, context
and root proof bindings, complete pairing/genesis/membership consent, trust
renewal identity, and signed projection tampering. The signature regression
checks 2,048 roundtrips with the deterministic full-width fixture authority and
another 2,048 with a randomly generated authority.

Client covers pending request persistence and signed negative recovery, committed
lost replies and peer progress, fabricated partial consent, definitive rejection
versus transport uncertainty, restored evidence tampering, duplicate consent,
initial preparation failure before root generation, admission recovery after lease
expiry, explicit same-root renewal, lost owner-session response without bearer
reissue, and late renewal result recovery followed by explicit renewal. Final
receipt verification retains complete accepted root consent proofs.

## Observed host verification disagreement

During the final run, deliberately tiny scalar-9 test keys exposed an intermittent
verification disagreement: Python cryptography 48.0.0 (OpenSSL 4.0.0), Homebrew
OpenSSL 3.6.3, and an independent affine P-256 calculation accept the preserved
signature. This host's Apple CryptoKit, Security, and system LibreSSL 3.3.6
verification APIs reject it. Raw scalar
decoding, DER roundtripping, public key bytes, and message digest matched. The
issue reproduced under both the default and pinned toolchains. Its scope beyond
this test key is not established.

`apple-fixture-verification-reproducer.json` preserves a public reproducer; its
historical filename does not imply an Apple-only cause. Run
`python3 artifacts/phone-v2/verify-captured-signature.py` from the workspace to
repeat the independent arithmetic and installed OpenSSL comparisons. Results
are saved in `signature-provider-comparison.json`. The
independent vector generator now uses explicitly public full-width deterministic
test scalars. Production verification was not relaxed or replaced, and still
fails closed. Changing fixture keys is not a fix for the observed provider
behavior; further provider investigation remains separate work.
