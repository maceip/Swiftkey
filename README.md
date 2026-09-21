# How this replaces a security key

**SwiftKey creates a non-exportable ECDSA P-256 signing key inside each compatible Android
phone's StrongBox secure hardware.** That key proves the phone's identity without
sending its private key to the server. It authorizes a separate P-256 software
signing key for a **four-hour epoch**, so routine requests can use a short-lived
credential while the long-lived identity remains in hardware.

Two phones become independent owners of one account. Each keeps its own hardware
key; they never copy or share a private key. You compare the phones, confirm the
pairing on both, and approve the same account and owner list on both. Only then
does the Swift/Vapor authority create the account. Each phone signs in separately
and receives its own epoch credential.

This provides hardware-backed proof of possession for applications that integrate
SwiftKey. **It is a custom authentication protocol, not a FIDO2/WebAuthn security
key or a drop-in passkey for existing websites.** The current implementation uses
Android StrongBox; an iPhone Secure Enclave implementation is not available yet.

## The protocol

1. **Prepare each phone.** The phone creates its hardware root and supplies
   attestation evidence plus proof that it holds the key. The authority checks
   the hardware/verified-boot policy, app identity, certificate chain and current
   revocation data before admitting it. The app pins the authority's public key
   through a trusted configuration channel, independently of any invitation.
2. **Pair the phones.** A short-lived QR code or link opens an invitation. Both
   phones show the authority, identities, full root fingerprints and the same
   transcript hash/comparison code. Each owner explicitly confirms those details.
   Importing a link alone never grants ownership.
3. **Create the account together.** Both phones review the same account name,
   owner set and ownership policy. One approval leaves the account uncreated.
   The second matching approval commits both owners atomically and produces a
   signed receipt bound to the authority's hash-linked ledger.
4. **Sign in and obtain a signing credential.** Each phone independently signs a
   fresh account- and origin-bound challenge with its hardware root. The authority
   checks current membership and trust, then verifies the root's authorization of
   that phone's epoch public key and signs the resulting credential.
5. **Verify requests online.** The authority checks the credential, signature,
   intended audience, current ownership/trust, expiry and replay state. A valid
   signature alone is insufficient if its owner has been removed or the request
   has expired or already been used.

### What rotates

The hardware root remains stable. The delegated **software** key changes on the
next use after a fixed four-hour UTC epoch boundary; there is no daily root-key
replacement or background rotation timer. A credential issued just before a
boundary has only the remainder of that epoch to live.

The root uses ECDSA P-256 with SHA-256. Delegated signing keys also use P-256 and
are stored in private app storage, outside StrongBox. This limits their credential
lifetime; it does not make a compromised running phone trustworthy. The current
signer does not require a fingerprint, PIN or physical touch for every signature.

### Losing or adding a phone

The implemented `two-owner-survivor-v1` policy keeps at least two owners. A current
owner and a new phone must both approve the exact membership change. Replacement
adds the new owner and revokes the lost owner's access in one atomic commit;
keys are never restored onto another phone.

Any current owner can start that replacement. This makes recovery possible with
one surviving phone, but a compromised owner can also take over the account. If
all owners are lost, there is no administrative recovery or password reset.

See the [full pairing and ownership protocol](docs/PAIRING-ACCOUNT-PROTOCOL.md)
and [cryptographic protocol](PROTOCOL.md) for the wire formats and trust model.

## What works today

The current Android build passed a real two-phone run against an isolated Vapor
authority: **StrongBox admission, mutual pairing, two-owner account creation, and
separate sign-ins producing two independently verified epoch credentials**. The
Pixel and Xiaomi retained their original hardware roots. The first account
approval created nothing; the second committed exactly one account with two owners.
See the [hardware evidence](artifacts/phone-v2-hardware/README.md).

That run used native Copy link and manual import. Optical QR scanning, interrupted
v2 ceremonies and owner replacement still need physical acceptance. The older
installed workload app separately passed Vapor signing, replay rejection and
restart checks; the current v2 phone UI does not expose workload submission.
Standalone owner revocation, arbitrary policy changes, browser-login grants,
legacy-account upgrade and iOS remain unavailable. This is a development project,
with no production authority cutover claimed.

## Get the code and build

```sh
git clone https://github.com/maceip/Swiftkey.git
cd Swiftkey
bash scripts/androidswiftui.sh doctor
bash scripts/swiftkey-protocol.sh test
bash scripts/androidswiftui.sh android-build
```

Everything needed from the Android renderer is included as ordinary source in
`AndroidSwiftUI/`. Use `main`; there are no submodules or extra branch checkouts.
The doctor command checks the installed Swift/Android toolchain. It does not
install prerequisites automatically.

Follow [phone setup](docs/PHONE-V2-BUILD.md) to enable v2 on a separate authority
and configure both phones. The [server guide](SwiftKeyServer/README.md) covers
Vapor configuration and local operation. Existing legacy accounts are preserved;
enabling v2 is an explicit state-format change, not an automatic account migration.

## Code map

| Directory | Responsibility |
| --- | --- |
| [SwiftKeyCore](SwiftKeyCore/README.md) | Canonical records, cryptography and epoch credentials |
| [SwiftKeyClient](SwiftKeyClient/Sources/SwiftKeyClient/ProtocolClient.swift) | Durable protocol client and hardware-root operations |
| [SwiftKeyApplication](SwiftKeyApplication/README.md) | Shared state, actions and service adapters |
| [SwiftKeyUI](SwiftKeyUI/README.md) | Shared account, identity and phone protocol views |
| [SwiftKeyServer](SwiftKeyServer/README.md) | Vapor authority, SQLite ledger and browser sessions |
| [AndroidSwiftUI](AndroidSwiftUI/README.md) | Swift-to-Compose renderer, Android host and component catalog |

The webpage and devices share Swift views and the same
[design tokens and fonts](SwiftKeyDesign/README.md). Android uses Compose; the
website renders server-evaluated Swift view trees through a small browser adapter.
The [Compose Cupertino integration](AndroidSwiftUI/docs/cupertino/README.md)
includes all six pinned upstream modules, 127 catalog surfaces and 879 icons.
Upstream licenses and [source provenance](AndroidSwiftUI/UPSTREAM.md) are retained.

[Build status](BUILD_STATUS.md) separates local tests from hardware proof and
remaining acceptance work. [Optional design research](tools/DesignResearch/README.md)
contains the TypeSafe/CatBoost evaluation tooling; it is separate from runtime
authentication and has not been trained on real UI ratings.
