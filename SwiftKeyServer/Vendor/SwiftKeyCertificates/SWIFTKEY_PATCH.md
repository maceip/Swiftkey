# Pinned upstream and local compatibility patch

This directory contains Apple Swift Certificates **1.20.0** sources, tests,
manifest and Apache 2 license/notice, copied from the SwiftPM resolved release.
Upstream revision: `c8aece90ea05f9866bd392a5bf13b5cae56c0e03`.
The only behavioral change is in `Sources/X509/Extension.swift`.

The local package has a distinct SwiftKeyCertificates identity, and the root
manifest aliases X509 to SwiftKeyX509. The internal helper target and its imports
are mechanically renamed to _SwiftKeyCertificateInternals to avoid collisions
with the unmodified upstream dependency used by NIOExtras. These namespace
changes do not modify validation behavior.

The connected Android StrongBox implementation emits the leaf X.509 KeyUsage
extension's `critical` Boolean TRUE as the single byte `0x01`. SwiftASN1's DER
Boolean parser permits only `0xff`, so unmodified Swift Certificates cannot
parse this otherwise signature-valid hardware chain. Android's maintained
[attestation parser](https://github.com/android/keyattestation/blob/main/src/main/kotlin/Extension.kt)
uses ASN.1 Boolean semantics.

The patch accepts `0x01` only for the KeyUsage critical flag (OID 2.5.29.15), with
the Boolean tag and exactly one content byte. Ordinary canonical `0xff` remains
accepted; other noncanonical values, malformed lengths/tags, and other extension
OIDs remain strict. An explicitly encoded default FALSE remains rejected.

**No certificate bytes are rewritten.** `Certificate` keeps the original
`tbsCertificateBytes`, and the unchanged upstream verifier verifies the original
signature against those bytes. Regression tests verify the real public leaf
signature, exact TBS-byte preservation, and failure if the critical byte is
rewritten to `0xff`. Chain validation, trust roots, revocation and all hardware
policy checks remain enabled.

The local path dependency makes the patch reproducible without editing SwiftPM's
cache. Review this patch when updating upstream; remove it if upstream provides
an equivalent narrowly scoped interoperability API.
