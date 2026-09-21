# SwiftKeyCore

Shared Swift protocol values, canonical encodings, P-256/SHA-256 operations and
an epoch-key state machine. There are no Android, UIKit, transport or server
storage dependencies in the core. Public wire values are immutable `Codable`
and `Sendable`; `Wire.swift` is the HTTP DTO contract shared with the authority
and client.

Cryptography comes from Apple's maintained
[Swift Crypto 4.5.2](https://github.com/apple/swift-crypto/releases/tag/4.5.2),
pinned exactly. Its [manifest](https://github.com/apple/swift-crypto/blob/4.5.2/Package.swift)
requires Swift 6.1 and selects the BoringSSL backend on Android. The package
builds and its host tests run with the workspace's Swift 6.3.2 toolchain;
Android cross-compilation and device execution are separate integration checks.
On Apple hosts the Crypto product uses CryptoKit.

## Signing contract

- Public P-256 keys are exactly 65 uncompressed X9.63 bytes: `04 || X || Y`.
  Points are validated by Swift Crypto. Signatures use canonical ASN.1 DER
  ECDSA encoding, not a raw `r || s` pair.
- `SoftwareSigningKey.sign(message:)` and
  `ProtocolCrypto.verify(signature:message:publicKey:)` hash the raw message
  with SHA-256 exactly once. Android's hardware callback must use
  `SHA256withECDSA` over **`challenge.canonicalBytes()`**, without prehashing it.
- Already-hashed input requires the explicit `PrehashedSHA256` type and
  `sign(sha256Digest:)` / `verify(signature:sha256Digest:publicKey:)` overloads.
  Passing digest bytes to a message overload hashes them again. Tests cover
  this distinction against an independent OpenSSL fixture.
- `RootAuthorization.kind == .appleAppAttest` is representable in transport
  but rejected with `unsupportedAuthorization`. An App Attest assertion is
  not a generic P-256 signature. No iOS authorization or software fallback is
  claimed by this package.
- A software key represents an epoch leaf or the authority's signing key.
  It is never proof of a hardware root. Root-key enrollment and attestation
  verification belong to the platform adapter and authority.

## Canonical v1 encoding

JSON is transport only; signatures never cover JSON bytes. Data uses the
default Codable JSON base64 representation. Integer JSON values must be parsed
as exact unsigned 64-bit integers, not through floating-point values.

Every canonical object begins with eight ASCII bytes `SwiftKey`, unsigned
16-bit big-endian version `1`, then a length-prefixed object domain. Variable
fields have an unsigned 32-bit big-endian byte length followed by their bytes.
Strings use NFC-normalized UTF-8. Integers use unsigned 64-bit big-endian.
Optional Data begins with a one-byte presence tag (`0` absent, `1` present);
present Data then uses the regular length prefix. Absent and empty differ.

IDs, workload domains and audiences must be nonempty, at most 256 UTF-8 bytes,
and contain no control characters. Nonces and SHA-256 hashes are exactly 32
bytes. Individual variable fields are bounded to 1 MiB. Public-key and integer
bounds are checked when canonical bytes are produced, including after JSON
decoding; decoding alone is not validation.

The following order is normative. Nested objects are length-prefixed complete
canonical byte strings, including their own version/domain prefix.

| Object domain | Fields in order |
| --- | --- |
| `challenge` | accountID, signing deviceID, operation string, sequence, nonce, expiresAt, payloadHash |
| `epoch-delegation` | accountID, deviceID, audience, epoch, publicKey, optional previousPublicKeyHash |
| `root-authorization` | authorization kind string, canonical challenge, DER root signature |
| `epoch-credential` | canonical delegation, canonical root authorization |
| `signed-epoch-credential` | unsigned canonical credential, DER server signature |
| `device-membership` | accountID, target deviceID, operation string, optional publicKey |
| `device-recovery` | accountID, lostDeviceID, replacementDeviceID, replacement publicKey |
| `workload` | workload domain, audience, accountID, deviceID, epoch, nonce, payload |

Operation strings are `enroll`, `issueEpoch`, `addDevice`, `revokeDevice`, and
`recoverDevice`. Root authorization signs the canonical challenge, whose
`payloadHash` is SHA-256 of the canonical operation payload. For epoch issuance
that payload is `EpochDelegation`; membership and recovery have their own
types. A recovery authorization binds both the exact lost root and replacement
public key. Enrollment's attestation bootstrap is specified by the authority.

The server signs `EpochCredential.unsignedCanonicalBytes()`, which binds the
delegation and the complete root authorization. A consumed challenge's expiry
is checked at issuance; it does not prematurely expire an issued credential.
Credential verification therefore verifies that historical authorization's
signature and binding, while checking the current epoch's validity.

## Four-hour epochs and state

`epoch = unixSeconds / 14400`. Validity is derived rather than duplicated in
wire values: `start = epoch * 14400`, `end = start + 14400`, and acceptance
requires `start <= verifierNow < end`. Future, expired and overflowing epochs
fail closed. The authority's clock is authoritative.

`EpochManager` is an actor. Call `prepareDelegation(now:)` when signing work is
requested; repeated calls within an epoch reuse the same key. Obtain and
hardware-authorize the challenge, issue the credential through the server,
then call `acceptCredential(_:now:)`. `signWorkload(...)` refuses to operate
until a valid credential for that exact key has been accepted. Async client
calls occur outside the actor, so a response arriving after rotation fails
binding/time checks instead of overwriting the new state.

Rotation is lazy and includes SHA-256 of the previous epoch public key in
`previousPublicKeyHash`. Missing previous keys use `nil`, including the first
epoch. Local clock rollback cannot silently rotate an existing manager back.

`snapshot()` returns an `EpochManagerSnapshot` containing the **software leaf
private key**, credential, delegation and trust-pin hashes. Store it only in
app-private atomic storage; never log or transmit it. `restore(_:now:)` checks
identity, audience, root/server pins, private-to-public correspondence and the
credential signature. An unexpired snapshot reuses the same key. An expired
snapshot rotates immediately and retains the previous-public-key hash. Future
snapshots and altered trust pins fail closed. No hardware private key is ever
exported or stored by these APIs.

Cryptographic verification alone does not establish current membership,
challenge freshness, monotonic sequence, or nonce uniqueness. The authority
must atomically check membership, consume the challenge/workload nonce,
advance sequence, and commit the operation. Online verification is required
for immediate revocation; the core deliberately does not call an offline
signature pass an authorization decision.

## Verification

```sh
swift test
openssl dgst -sha256 -verify Tests/SwiftKeyCoreTests/Fixtures/openssl-public.pem \
  -signature Tests/SwiftKeyCoreTests/Fixtures/openssl-signature.der \
  Tests/SwiftKeyCoreTests/Fixtures/openssl-message.bin
```

Tests cover fixed independently encoded vectors/hashes, an OpenSSL signature,
message-versus-digest APIs, canonical framing, JSON transport, tampered fields,
credential/audience binding, exact epoch boundaries, overflow, unsupported
Apple authorization, recovery target binding, rotation and snapshot restoration.
The fixtures are public conformance material; their test key is not a real
hardware key and cannot satisfy enrollment policy.

## Pairing-first v2

`PairingV2Records`, `PairingV2Wire`, `PairingV2Codec` and
`PairingV2Verification` define the Android two-owner profile. Canonical records
are immutable reference values to avoid copying deeply nested receipts on the
small Swift concurrency worker stack. Their public constructors and exact
`Equatable` behavior remain value-like.

V2 JSON rejects unknown/duplicate keys, noncanonical base64, non-NFC text and
lossy numeric encodings. Unsigned 64-bit fields use decimal strings. Domain
separation and canonical field order are specified in the
[pairing protocol](../docs/PAIRING-ACCOUNT-PROTOCOL.md).
The receipt verifiers require both accepted root proofs, full object/context
bindings and the pinned authority signature. The native client additionally
checks its own saved consent and monotonic checkpoints. Current trust,
membership and replay authorization remain authority responsibilities.

Independent Python-generated fixtures cover all 27 canonical records with
46 byte/hash vectors, including real ECDSA proof/receipt verification. Software
roots in tests never enable software-root admission in production.
