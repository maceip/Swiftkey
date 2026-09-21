# SwiftKey protocol evidence — 2026-09-19

These artifacts contain public certificates, public keys, signatures, challenge/
nonce values, account/device identifiers and selected test/runtime results.
They contain **no hardware, epoch or authority private keys, bootstrap token,
or complete private client/authority state**. Public identifiers still identify
this development session and should not be mistaken for anonymous data.

## Exercised physical-device proof

Device `D6OZUCKVEIQ4LVLV`, model `2506BPN68G`, Android API 36, connected to the
local authority through `adb reverse` on port 18088:

| Files | What they establish |
| --- | --- |
| `android-first-enrollment.json` / `.log` | Real StrongBox attestation enrollment, verified epoch124295 credential, accepted workload and explicit workload replay rejection; authority had one device, one credential and one consumed nonce |
| `android-app-restart.json` / `.log` | Force-stop/relaunch reused the same root, epoch delegation and credential; a fresh workload advanced the nonce ledger to two |
| `server-before-restart.json` | Public membership/credential counts and nonce-ledger keys immediately before authority restart |
| `android-server-restart.json` / `.log` | Restarted authority retained prior replay entries and the same root/delegation/credential; new workload advanced nonce count to three and replay was rejected |
| `android-activity-recreation.json` / `.log` | Two activity recreations while the authority was paused preserved PID25901 and produced exactly one successful workload after resumption; nonce count3 → 4 |
| `android-offline.json` / `.log`, `android-offline-ui.xml` | Removing adb reverse left exactly the name and same attested root on screen; transport failure was reported and no server nonce was consumed |
| `android-final-online.json` / `.log` | Restored connectivity completed a fresh workload and rejected replay; nonce count5, same original epoch credential |
| `android-final-ui.xml`, `android-attested-key.png` | Final UI contains only `SwiftKey` and matching attested root hex; screenshot visually inspected, readable without clipping |

The JSON extracts intentionally omit private state. Log events and persisted
public-value comparisons are complementary evidence; successful APK assembly
or certificate capture alone would not establish these protocol results.

## Public chain and parser evidence

- `android-attestation-evidence.json` contains the issued attestation challenge
  and the five returned certificates; `android-attestation-0.der` through
  `android-attestation-4.der` preserve the original chain, leaf first.
- `leaf.pem`, `intermediates.pem`, `google-roots.pem`, and
  `openssl-chain-verification.txt` provide independent X.509 path-check evidence.
  OpenSSL path verification alone does not check Android's app/boot/StrongBox
  authorization extension policy.
- `device-verification-final.log` records the final Swift verifier accepting
  this real chain under the configured Android application/hardware policy.
- The leaf's X.509 KeyUsage critical TRUE is encoded as `0x01`. The
  [narrow Swift Certificates compatibility patch](../../SwiftKeyServer/Vendor/SwiftKeyCertificates/SWIFTKEY_PATCH.md)
  accepts that location while verifying original signed TBS bytes. The boot-lock
  Boolean remains canonical `0xff` and strictly checked.

## Host test evidence

- `core-tests.log`: **16 tests passed**, including independent canonical/OpenSSL
  fixtures, tampering, exact epoch boundaries, rotation and snapshot validation.
- `client-tests.log`: **30 tests passed**, including enrollment/retry/persistence,
  workload/replay behavior, pairing, revocation and recovery orchestration.
- `server-tests.log`: **17 tests passed**, including state/policy/refresh behavior,
  replay races, membership operations, negative attestation policy and X.509
  interoperability/signature preservation.

Host test attestation substitutes are explicitly software fixtures. They do
not prove hardware enrollment, physical pairing/recovery, or iOS support.
`android-final-build.log` and `android-final-apk.json` record the final protocol
APK build, SHA-256, size and 27 ARM64 native libraries; no XCTest/Testing runtime is packaged. Package
inspection does not prove visible UI or execution on its own.
The separate real desktop bridge pass is recorded in
[`../androidswiftui/desktop-final.log`](../androidswiftui/desktop-final.log) and
[`../androidswiftui/desktop-bridge-test.xml`](../androidswiftui/desktop-bridge-test.xml):
one executed Catalog → Text → counter0/1/2 test, zero skips/failures/errors.

## Remaining proof and lifecycle limits

Physical pairing/recovery and an actual four-hour device rollover have not
been exercised. iOS is postponed until a physical iPhone is connected.
The real RKP intermediate expires on **2026-09-27**; authenticated evidence/root
renewal is not implemented, and the retained chain will fail current-time
validation afterward. Revalidating old certificates does not produce a new
boot measurement. This is a loopback development authority with a debug APK
signing-certificate pin, not a public deployment.

See [BUILD_STATUS.md](../../BUILD_STATUS.md) for the current overall checkpoint
and [PROTOCOL.md](../../PROTOCOL.md) for contracts and reproduction commands.
