# SwiftKey build plan

## Next account protocol — draft, not implemented

The [pairing-first account specification](docs/PAIRING-ACCOUNT-PROTOCOL.md)
replaces single-device account bootstrap as the target: two devices pair while
no account exists, both approve the same genesis, then one transaction creates
the account and both equal owner memberships. Marks supplies the rendezvous and
signed-grant pattern; its single-device fallback and unequal controller/member
roles are not the requested SwiftKey policy. Current v1 checkpoints below remain
historical/current implementation evidence, not proof of this new ceremony.

- [ ] Accountless attested identities and durable pairing/consent state.
- [ ] Two-root genesis and atomic account/owner/ledger commit with safe retries.
- [ ] Shared Swift onboarding and owner authentication; browser sessions cannot
      substitute for hardware-root consent.
- [ ] Explicit ownership/recovery policy, legacy migration and bypass removal.
- [ ] Adversarial concurrency/replay tests and physical two-device acceptance.

The draft preserves hardware-backed owners and proposes survivor-authorized
replacement from the existing plan. Those policy choices and remaining design
gates are called out in the specification; no live account is changed by it.

## Existing build sequence and checkpoints

Build in this order:

1. Get https://github.com/PureSwift/AndroidSwiftUI working on this machine.
2. Build the shared cryptographic protocol in Swift, including the server and
   end-to-end enrollment, four-hour delegation, signing, pairing and recovery.
3. Build the shared Swift application and UI layer for Android and the website.
   The focused Android identity screen remains the project name and public-key
   bytes. The administrative workspace uses the same Swift components and
   application state/actions through platform renderers. This does not reduce
   protocol scope. iOS work remains postponed until the physical iPhone is connected.

`fullplan.md` is the original design discussion. Its Kotlin Multiplatform
directory layout is superseded by the Swift direction above. Keep the proposed
hardware-root → four-hour delegated key → paired-device recovery model.

## 1. AndroidSwiftUI on this Mac — platform checkpoints passed

Use the existing `AndroidSwiftUI/` checkout. Match its Swift 6.3.2 toolchain pin,
select the matching swift.org Android SDK, and use the installed JDK 21 and
Android SDK. Do not use the legacy `Demo/setup.sh` unchanged: it targets Swift
6.0.3 and an older SDK layout.

Acceptance:

- [x] Host `SwiftUICore` tests pass (123 tests; initial run on Swift 6.4.0).
- [x] Swift 6.3.2 Android SDK installed, checksum verified, configured with NDK r27d.
- [x] Matching Swift 6.3.2 host toolchain installed and checksum verified;
      global Swiftly selection remains 6.4.0.
- [x] Android Gradle dependency compatibility check passes.
- [x] Desktop Swift dynamic library builds with Swift 6.3.2.
- [x] Desktop bridge test traverses the current Catalog → Text screen and
      verifies two native Swift state updates through JNI and Compose.
- [x] Android Swift dynamic library cross-compiles for ARM64, API 28.
- [x] Android debug APK assembles with Gradle.
- [x] APK payload inspected: app, bridge, Swift runtime and C++ runtime libraries
      present; no XCTest/Testing libraries.
- [x] Minimal APK installs and launches on physical device `D6OZUCKVEIQ4LVLV`
      (model `2506BPN68G`, API 36); the key reaches the Swift UI successfully.
- [x] Reproducible build/run commands and versions are recorded locally;
      remaining device evidence must be added as each check completes.

A host unit test pass, a desktop launch, and an Android launch are separate
checkpoints. Emulator success does not prove StrongBox or App Attest support.

## 2. Shared Swift cryptographic protocol — implemented, device validation in progress

`SwiftKeyCore`, `SwiftKeyClient`, and `SwiftKeyServer` now implement the shared
types, client orchestration, and online authority. Android has the StrongBox
attestation/signing and HTTP bridge. Host tests exercise canonical encoding,
epoch rotation, persistence, enrollment, pairing, revocation and recovery;
software fixtures are not hardware-attestation evidence.

The updated APK completed real-device attested enrollment → epoch delegation
→ workload acceptance → replay rejection against the local authority. The
five-certificate StrongBox chain is validated with a narrow compatibility fix
for this OEM's X.509 KeyUsage `critical` Boolean, preserving the original signed
certificate bytes. App and server restarts preserve the root, delegation and
credential, retain the replay ledger and accept fresh workloads. Activity
recreation during a pending request does not duplicate execution, and offline
display keeps the same attested public key without claiming network success.
The final online run and inspected minimal-screen screenshot passed. Actual
four-hour rollover, physical pairing/recovery and all iOS authorization remain
pending; the full protocol objective is not complete.

Before treating the root as a durable identity, add authenticated attestation
renewal: the older phone’s September 19 chain has an RKP intermediate expiring
on 2026-09-27; that date has not been established for the new Pixel chain.
Current validation correctly fails closed after certificate expiry. Rechecking the
original chain does not refresh the device's boot measurement.

The requirements below remain the acceptance contract. See [PROTOCOL.md](PROTOCOL.md)
for the implemented architecture and local commands, and
[BUILD_STATUS.md](BUILD_STATUS.md) for current evidence.

“Crypto primitives in Swift” means a Swift API using CryptoKit/Swift Crypto's
SHA-256 and P-256 implementations, plus our protocol and state machines. Do not
implement elliptic-curve arithmetic or hash algorithms from scratch.

The platform-neutral `SwiftKeyCore` Swift package must provide:

- A versioned canonical encoding with fixed field order, integer widths,
  lengths, public-key representation and signature representation.
- Four-hour epochs: `epoch = floor(unixSeconds / 14400)`, with acceptance only
  for `start <= verifierNow < end`; rotate lazily on the next signing operation.
- Delegation, device-operation authorization and workload-message types. Bind
  each to its operation/domain, account, device and intended audience.
- Explicit message-versus-digest signing APIs. Android `SHA256withECDSA` hashes
  input; an Apple App Attest assertion signs a platform-specific envelope.
  Passing an already hashed value to a message-signing API must not silently
  change the protocol hash contract.
- Separate Android P-256 authorization and Apple App Attest assertion types.
  Platform-specific verification is needed for later authorizations as well
  as initial enrollment.
- Fixed encoding/hash vectors, independently verifiable signature fixtures,
  tamper rejection and exact epoch-boundary tests on host and Android.

The authority and hardware adapters must provide:

- The server issues short-lived, single-use challenges. Every root-authorized
  operation binds challenge, sequence and payload. Atomically check current
  membership, consume challenge, advance sequence/App Attest counter and apply
  the operation. Workload nonces also require replay storage at execution.
- For the first implementation, use online verification against current device
  membership, so revocation takes effect immediately. Offline acceptance would
  require an explicit policy allowing residual validity until epoch expiry.
- Android: fail closed without StrongBox; validate the attestation chain,
  challenge, trusted roots and revocation, key properties, hardware security
  level, application identity and boot policy. Keep the private root in
  Android Keystore and expose its operations through a thin native adapter.
- Apple: use `DCAppAttestService`; verify attestation and assertions with their
  App ID, environment, nonce and monotonic counter requirements. Keep its
  opaque key identifier rather than treating it as a generic exportable key.
- New-account pairing must complete before account creation, and both attested
  roots must approve one exact account genesis. Later pairing binds the exact
  candidate to the intended existing account and requires both an active owner's
  authorization and the candidate's acceptance. Recovery atomically revokes the
  lost owner and adds a consenting replacement under the selected signed policy.
- Test replay, races, expired/future credentials, revoked roots, tampered
  pairing targets, rotation and recovery before exposing protocol operations
  through any later product UI.

Real-device gate: demonstrate enrollment, delegation, signing, pairing and
recovery using the user's Android phone and iPhone. Software mocks must remain
explicit test fixtures and must never satisfy hardware-attestation policy.

## 3. Android identity display

Show only the project name (currently `SwiftKey`) and the real public key bytes
in hex. Use uncompressed X9.63 P-256 encoding:
`04 || X || Y`, 65 bytes. Do not add catalog controls, enrollment/recovery
screens, or signing playgrounds to this scope.

- Android: generate or reuse a persistent StrongBox P-256 key in Android
  Keystore. Verify its actual hardware security level and a random challenge
  signature before displaying its public bytes. No software fallback or
  fabricated key. **Passed on the connected phone:** `securityLevel=STRONGBOX`,
  `signVerify=true`; UI dump and inspected screenshot show only `SwiftKey` and
  the matching 65-byte public hex.
- **Passed:** force-stop/relaunch displays the identical 130-character public
  hex and performs a fresh successful signature check. Both UI dumps contain
  exactly the name and public bytes. The Android device checkpoint is complete;
  private-key material stays in Android Keystore/StrongBox.
- iOS: **postponed at the user's request until a physical iPhone is connected**.
  The earlier Simulator catalog launch is only a platform-readiness result.
  The new screen and App Attest adapter/verifier have not been implemented.
  When resumed, display the public key from the validated App Attest identity,
  retain its opaque key identifier, and use App Attest assertions with their
  platform-specific verification. A generic Secure Enclave ECDSA callback does
  not implement this authorization protocol. Simulator must never supply a
  mock or software substitute.

The Android hardware-key screen is a completed intermediate demonstration.
The project objective remains the end-to-end protocol above; the screenshot
and local key checks do not establish enrollment, delegation or recovery.

## 4. Shared Swift workspace and account handoff — live Pixel path passed

`SwiftKeyApplication` owns platform-neutral state, actions and real service
contracts. `SwiftKeyUI` owns identity/public-key components and `WorkspaceView`.
The website evaluates those Swift views with an isolated `SwiftUICore.ViewHost`
per session; a generic browser adapter renders primitive nodes and transports
typed callbacks. Android uses ComposeUI for the same shared identity components.
Do not duplicate account/device behavior in browser JavaScript or treat matching
colors as shared application code.

- [x] Shared Swift Core, Client, Application and UI packages have host tests.
- [x] Application state excludes invitation secrets; explicit export checks the
      current expiry and binds the expected account and authority pin.
- [x] Server UI sessions validate revision, active callback type and enabled
      state before dispatching actions; SecureField text is excluded from trees.
- [x] Android identity uses shared Swift components; shared workspace compiles
      for Android. Desktop/Android builds pass.
- [x] Swift operator validates an exported account bundle and separately trusted
      pin before private USB handoff; existing config/state cannot be overwritten.
- [x] Live shared-browser account/export actions, Swift operator handoff and
      Pixel StrongBox enrollment/epoch 124299 issuance; current verification,
      tampered-signature rejection and restart credential reuse passed.
- [ ] Native administrative workspace session and authorization/service adapter.

The workspace is an operator interface, not consumer device-key login. Browser
account creation prepares a pending account; only strict hardware enrollment
adds a device. The original full-plan gaps remain: physical multi-device
pairing/revocation/recovery, an actual four-hour rollover, authenticated attestation
renewal, Apple App Attest, and any independently operated ledger checkpoint
anchoring or production deployment. Do not mark the protocol complete from the
UI migration or host tests. Results belong in `BUILD_STATUS.md`.

## Review references

- [AndroidSwiftUI upstream](https://github.com/PureSwift/AndroidSwiftUI)
- [Android Signature API](https://developer.android.com/reference/java/security/Signature)
- [Apple App Attest server validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server)
- [Android key attestation verification](https://developer.android.com/privacy-and-security/security-key-attestation)

Build/run results and remaining blockers belong in `BUILD_STATUS.md`.
