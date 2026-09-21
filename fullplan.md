Exactly. For the requirement as you've described it, a YubiKey does not need to be the default. A phone can be the hardware security device the user already carries.

The architecture is legitimate on both platforms:

ANDROID                              iPHONE

StrongBox / TEE                     Secure Enclave
      │                                  │
generate non-exportable key         App Attest generateKey()
      │                                  │
Google-rooted                       Apple-signed
Key Attestation                     App Attestation
      │                                  │
      └──────────────┬───────────────────┘
                     ▼
              your verifier
                     │
              register Kpub
                     │
          issue your credential
                     │
                     ▼
       later: challenge + payload
                     │
                     ▼
             hardware signs
                     │
                     ▼
              verify Kpub

Google explicitly describes Android hardware attestation as proving that the credential key is locked in a TEE/StrongBox and cannot be exported or cloned. Apple says App Attest creates a hardware key whose private key resides in the Secure Enclave and cannot be directly read, and Apple certifies its origin; assertions then sign hashes of your payload.

There are meaningful tradeoffs versus a YubiKey, though. The biggest ones are:

The credential becomes device-bound. This is probably the largest product issue. Apple's App Attest key doesn't survive uninstall/reinstall, device migration, or restoring from backup, and it doesn't sync to another iPhone. Apple explicitly tells servers to expect key rotation for these cases. Android hardware keys similarly shouldn't be treated as portable credentials. So you need a first-class re-enrollment/key-rotation/revocation story.
Platform dependency replaces hardware-token dependency. With a YubiKey, you're depending primarily on the token and its standards. Here your trust chain contains Google/Android OEM infrastructure or Apple. Android verification requires maintaining Google's accepted attestation roots and checking its revocation information. App Attest's initial attestation goes through Apple's service, although subsequent assertions are generated locally and don't require an Apple round trip.
Android is heterogeneous. “Android phone” doesn't imply StrongBox. StrongBox is optional, and requesting it can produce StrongBoxUnavailableException. Google distinguishes ordinary TEE-backed keys from StrongBox, with StrongBox offering stronger isolation/tamper resistance. So your policy probably wants something like StrongBox ≥ SecureEnclave > TEE, rather than treating every Android Keystore result identically.
Apple App Attest isn't a generic HSM interface. You're signing an App-Attest assertion incorporating your clientDataHash, rather than receiving a generic PKCS#11-style sign(bytes) API. For your protocol that sounds fine—you control the verifier and can define the signed object accordingly—but it means the same key can't necessarily be dropped into arbitrary existing protocols expecting a raw private-key operation.
A phone has a much larger attack surface. Secure hardware protects extraction of the private key, but a compromised application/OS is a different question from extracting the key. Key-use authorization, app integrity and freshness therefore matter. Android lets hardware enforce things such as user authentication requirements; App Attest additionally binds assertions to your legitimate application. A YubiKey's tiny dedicated environment gives you a simpler boundary.
A removable token has operational properties phones don't. You can move a YubiKey between machines, keep one offline in a safe, provision two independent tokens, use it when the phone is dead/lost, and potentially use the same credential from unrelated applications. Those are features rather than necessarily stronger cryptography.

There's also a nice upside: phones can give you better UX around authorization. On Android you can make key use contingent on hardware-enforced user authentication. So a signing event can effectively become “hardware-bound key + biometric/PIN authorization” without carrying another object.

For your project, I'd therefore change the requirement from:

Private key must reside on a YubiKey.

to something closer to:

The signing key MUST be non-exportable and hardware-bound. Enrollment MUST provide remotely verifiable evidence binding the public key to an accepted hardware trust root.

Then define accepted implementations as Apple Secure Enclave + App Attest, Android StrongBox/approved TEE + Key Attestation, YubiKey, TPM/HSM, with the attestation evidence recorded alongside the public key.

That makes the YubiKey a useful fallback / high-assurance / recovery option, rather than something every user has to carry. The thing I'd spend design effort on isn't the signing operation—it's what happens when someone drops their phone in the ocean. Key rotation and recovery become part of your security protocol rather than an edge case.

Oh I see what You're saying if we needed those keys to live for a long time, then we're fucked. But, like, isn't that less of a problem now with other types of schemes we could use? Like, I don't know what, but there's got to be a way to re-key every, like, interval. And then for recovery, or for re-keying, you need some other credential, like maybe a... But yeah, I'm not worried about that. I'm just glad to hear that there is an option. So, like, what could we do knowing that they're not resident permanently, which is good? Let's say we did need to re-key every day. What would we do?

Yes. And if you're comfortable treating the phone-held key as ephemeral, I think the design actually gets cleaner.

I would not generate and remotely attest a brand-new hardware key every day. In particular, Apple explicitly recommends keeping App Attest key generation low; repeated key creation contributes to its fraud metric, while there is no restriction on the number of assertions made with an already-attested key.

Instead, I'd use two layers of keys:

             DEVICE ROOT
       hardware-bound, attested
       relatively long-lived
              K_device
                  │
                  │ signs
                  ▼
        ┌───────────────────┐
Day 1   │ K_day_2026-09-17  │──► arbitrary signatures
        └───────────────────┘
                  ✕ expires

                  │
                  ▼
        ┌───────────────────┐
Day 2   │ K_day_2026-09-18  │──► arbitrary signatures
        └───────────────────┘
                  ✕ expires

The daily key can just be a normal fresh asymmetric key. At midnight—or better, at the first operation in a new epoch—the app generates K_day. Then the hardware key authorizes something like:

"adns-ephemeral-key-v1"
public_key = K_day.pub
valid_from = 2026-09-18T00:00Z
valid_until = 2026-09-19T00:00Z
identity = flowers.com
epoch = 20710

Hash that canonical object and have the attested hardware key sign/authorize the hash. On iOS that's an App Attest assertion over clientDataHash; Apple says those assertions happen locally, don't round-trip through Apple, and can be generated on demand. Android can do the corresponding signing operation with its hardware-backed key; Android documents ECDSA/RSA operations where the private key remains inside secure hardware.

Now your verifier sees:

Apple/Google attestation
        ↓
K_device
        ↓ signs
K_day.pub + epoch + expiry
        ↓ signs
arbitrary aDNS messages

That's essentially a tiny certificate hierarchy. The hardware key is your device root; the rotating key is a short-lived leaf.

And this gives you a surprisingly nice property: the daily key doesn't even have to live in secure hardware. If malware steals today's K_day, you've bounded the useful lifetime of the stolen material. Your policy can say that a leaf is accepted only if it has a valid authorization from an enrolled hardware root and its epoch hasn't expired.

I'd probably go one step further and make the epochs relatively short—say hours rather than days—if signing volume permits. There isn't much cost to minting software leaf keys.

The long-lived hardware key then becomes much less scary. It's basically a certification key, not the key you're throwing at every protocol operation.

And losing it is straightforward:

Old phone
 K_device_A
      │
      ├── day 100 ✓
      ├── day 101 ✓
      └── LOST

             recovery authority
                    │
                    ▼

New phone → attestation → K_device_B
                    │
                    ▼
              new enrollment
                    │
                    ▼
                day 102 ✓

K_device_A → revoked

Recovery could be another already-enrolled device, account authentication/passkey, administrator approval, recovery code, threshold recovery, another hardware key, etc. That's a policy decision rather than something that contaminates the basic attestation protocol.

There's another subtle benefit: you don't need to pretend that the Apple and Android primitives are identical. Your verifier only needs to understand them at enrollment:

Apple App Attest ───┐
                    │
Android Attestation ├──► DEVICE CREDENTIAL
                    │
TPM ────────────────┤
YubiKey ────────────┘
                          │
                          ▼
                   ephemeral key cert
                          │
                          ▼
                    normal protocol

After that boundary, aDNS doesn't care whether the root came from an iPhone, Pixel, YubiKey or TPM.

One caveat I'd emphasize: don't rotate the App Attest key itself daily. Apple's documented model is one key per user/device (or one per app/device), with that key surviving app updates but not reinstall/migration/restore. Apple specifically says to generate a new App Attest key primarily for those lifecycle events.

So I think the clean primitive for what you're building is:

attested hardware root → short-lived delegated signing keys → arbitrary data

rather than short-lived attested hardware keys.

That also makes the YubiKey story much nicer: it's just another possible root credential, perhaps useful for servers/recovery/high-assurance environments, rather than a physical object every aDNS user has to carry.

Yesterday 3:12 PM
Yeah, let's flesh this out, please. We already did a, I'd say, pretty okay job at the whole, like, recovery is solved by enrolling your other device at sign up. But we need your help mocking this whole end-to-end. Like, we want to do something more, like something, like every four hours it rotates the ephemeral key and support the paired device registration with recovery on Android using a key in the, like, most—I have, like, a Pixel 11 XL with, like, a lockbox, using that. But we also have an iPhone we need to use to do the Apple side of it. Can we do all this in Kotlin Multiplatform?

Yes. Kotlin Multiplatform is a good fit, but I would deliberately not try to abstract the actual hardware APIs into pure common Kotlin. Put the protocol/state machine/rotation/recovery/networking in commonMain, with thin Android and iOS hardware-attestation adapters. KMP is explicitly designed for this pattern via common interfaces plus platform-specific implementations.

For your prototype, I'd make the system have three key levels, not two:

                    ACCOUNT
                       │
          ┌────────────┴────────────┐
          │                         │
     Pixel 11 XL                 iPhone
          │                         │
    DEVICE ROOT A              DEVICE ROOT B
     StrongBox                  App Attest
    attested by Google         attested by Apple
          │                         │
          └──────────┬──────────────┘
                     │
              registered devices
                     │
          ┌──────────┴──────────┐
          │                     │
       epoch N               epoch N+1
       4 hours                 4 hours
          │                     │
      EPHEMERAL A           EPHEMERAL B
          │
          ▼
     sign workload
1. Device roots

Pixel: create a P-256 signing key in Android Keystore with setIsStrongBoxBacked(true) and a server-issued setAttestationChallenge(). Android returns the X.509 attestation chain; your server verifies the Google root, challenge, certificate signatures/revocation and that the attestation security level is actually StrongBox. Google documents that this establishes a key locked in StrongBox/TEE that cannot be exported or cloned.

Something approximately:

interface DeviceRoot {
    suspend fun enroll(challenge: ByteArray): AttestedPublicKey

    suspend fun authorize(
        payloadHash: ByteArray
    ): HardwareAuthorization
}

Android:

class AndroidDeviceRoot : DeviceRoot {
    // AndroidKeyStore
    // EC secp256r1
    // PURPOSE_SIGN
    // SHA-256
    // StrongBox = true
}

And fail closed if StrongBox isn't available rather than silently accepting TEE, assuming StrongBox is your policy. Android explicitly exposes the StrongBox feature check and throws StrongBoxUnavailableException when the requested operation isn't supported.

iPhone: the implementation calls DCAppAttestService. Apple says generateKey() creates the key in the Secure Enclave, attestKey() asks Apple to certify it, and generateAssertion() produces subsequent assertions.

I'd probably implement that tiny adapter in Swift, rather than fighting Kotlin/Native bindings:

final class AppleDeviceRoot {
    func enroll(challenge: Data) async throws -> Attestation { ... }

    func authorize(hash: Data) async throws -> Data { ... }
}

and expose it to the shared layer. KMP supports this architecture; Apple SDK APIs are accessible from Kotlin/Native too, so we could subsequently decide whether eliminating the Swift shim is worthwhile.

2. Four-hour keys

This is where I'd change one thing from our earlier discussion.

Don't rotate hardware keys every four hours.

Make a cheap P-256 ephemeral key in software:

epoch = floor(unix_time / 14400)

For example:

epoch 123456

starts:   12:00 UTC
expires:  16:00 UTC

K_epoch_priv
K_epoch_pub

Then construct a canonical delegation:

version:        1
account:        <account-id>
device:         <device-id>
epoch:          123456
public_key:     <K_epoch_pub>
not_before:     12:00
not_after:      16:00
previous_key:   SHA256(K_epoch-1_pub)

And calculate:

H = SHA256(
    "stratura-device-delegation-v1" ||
    canonical_encode(delegation)
)

The device root authorizes H.

Android signs it with the StrongBox key.

iOS calls:

generateAssertion(
    appAttestKey,
    clientDataHash = H
)

The server validates that authorization and returns something like:

EpochCredential {
    delegation
    hardwareAuthorization
    serverSignature
}

From that point onward, virtually nothing is platform-specific.

3. Ordinary signing becomes fast

This is the nice part.

You don't need to hit StrongBox/App Attest for every operation:

              DEVICE ROOT
                   │
             once / 4 hours
                   │
                   ▼
            Epoch Credential
                   │
             K_epoch_priv
                   │
          ┌────────┼────────┐
          ▼        ▼        ▼
        msg 1    msg 2    msg 3

So an arbitrary operation becomes:

signature = Sign(
    K_epoch_priv,
    SHA256(
        domain ||
        epoch ||
        nonce ||
        payload
    )
)

Your verifier checks:

message signature
       ↓
epoch public key
       ↓
epoch credential
       ↓
device-root authorization
       ↓
original platform attestation
       ↓
Apple / Google trust root

You only pay the hardware operation once every four hours per device, rather than making StrongBox/App Attest part of your hot path. StrongBox in particular is deliberately slower and more resource-constrained than the ordinary Android keystore, so keeping it off the workload path is attractive.

4. Paired-device enrollment

This is where your existing recovery design becomes especially useful.

Say the Pixel is enrolled first:

ACCOUNT
   │
   └── Pixel A
         └── StrongBox Root A

The user selects:

Add recovery device

Server creates:

pairing_id
random_nonce
expires_at = now + 5 min

Represent that as QR/deep link.

The iPhone scans it and performs App Attest enrollment:

iPhone
  ↓
generate App Attest key
  ↓
Apple attestation
  ↓
pairing_nonce
  ↓
server verifies

But I would add one important requirement:

the existing Pixel must authorize adding the iPhone.

So the server doesn't merely see:

"I have a valid iPhone"

It sees:

StrongBox Root A
       │
       │ authorizes
       ▼
"add App-Attest Root B
 to account X
 challenge Y"
       +
Apple attestation for Root B

Then:

ACCOUNT
   │
   ├── Pixel
   │    StrongBox Root A
   │
   └── iPhone
        App Attest Root B

Now neither Google nor Apple identity is your account identity. Your account is the set of currently authorized device roots.

That's a much nicer primitive.

5. Losing the Pixel

Suppose tomorrow you smash the Pixel.

Nothing particularly dramatic needs to happen:

       ACCOUNT
       /     \
      /       \
 Pixel A      iPhone B
   X             │
 LOST            │
                 │
                 ▼
          "revoke Root A"
                 │
                 ▼
              SERVER

Root B authorizes:

RevokeDevice {
    account: X
    device: RootA
    counter: 72
    challenge: serverNonce
}

Server verifies it against the enrolled App Attest root.

Root A is revoked.

All four-hour credentials descended from A are either immediately invalidated or simply expire within ≤4 hours.

Then your iPhone can enroll:

Pixel C
   ↓
StrongBox Root C
   ↓
authorized by iPhone Root B

and you're back to two devices.

6. I would add one small but important protocol feature

Make every device-root operation include a monotonic server-side sequence number:

account
device
operation
sequence
server_nonce
payload_hash

For example:

device A sequence 417:
    issue epoch 98371

device A sequence 418:
    issue epoch 98372

device A sequence 419:
    add device B

device B sequence 1:
    issue epoch 98372

The server rejects previously consumed sequence numbers/nonces.

That makes replay reasoning considerably easier and gives you a very useful audit trail.

KMP project shape

I'd make the repository boring:

shared/
  commonMain/
    crypto/
      EpochKey.kt
      Delegation.kt
      CanonicalEncoding.kt

    attestation/
      DeviceRoot.kt
      AttestationEvidence.kt

    protocol/
      Enroll.kt
      Pair.kt
      Rotate.kt
      Revoke.kt
      Sign.kt

    storage/
      DeviceState.kt

  androidMain/
    attestation/
      StrongBoxDeviceRoot.kt

  iosMain/
    attestation/
      AppleDeviceRoot.kt

androidApp/
iosApp/
server/

And the common API can genuinely be tiny:

interface HardwareRoot {
    suspend fun enroll(
        challenge: ByteArray
    ): EnrollmentEvidence

    suspend fun authorize(
        challenge: ByteArray,
        digest: ByteArray
    ): Authorization
}

interface EpochManager {
    suspend fun current(): EpochSigner
    suspend fun rotate(): EpochSigner
}

Everything interesting—canonical serialization, four-hour epochs, pairing, device-set membership, recovery, delegation validation, replay protection and tests—is identical Kotlin code.

Only these operations cross the platform boundary:

generate hardware root
obtain attestation
authorize digest
delete hardware root

That's exactly the sort of boundary KMP handles well.

One further design choice I'd make for the mock: don't actually schedule a background job at exactly four hours. Define four-hour cryptographic epochs and lazily rotate on the first signing request after the epoch changes. Pre-generate the next leaf opportunistically if you want. That avoids iOS/Android background-execution restrictions affecting correctness.

So your core invariant becomes wonderfully simple:

No workload key lives longer than four hours. No device root leaves secure hardware. No new device becomes a recovery authority without authorization from an existing device root.

That is a prototype I'd be quite interested in testing end-to-end on the Pixel + iPhone before adding any YubiKey path at all.
