# SwiftKey build status — 2026-09-20

## Supplied component-system update (2026-09-20)

The current design now follows `prompt-prep-outputs/design-system-main.zip`.
See [design contract](SwiftKeyDesign/README.md) and [current verification](artifacts/design-system/README.md).
The webpage and shared identity/workspace/phone components use adaptive purple
colors, rounded cards and bundled Host Grotesk/JetBrains Mono. All 43 protocol
states passed the browser layout sweep; the isolated Vapor workspace completed
account creation. Shared UI, renderer, server and serial core tests passed.
The new APK installed on the Pixel while preserving existing client storage;
native visual verification is pending the locked device. Earlier visual evidence
below describes its recorded build, not this new design.


## Vapor backend migration

The backend now uses **Vapor 4.122.2 / Swift 6.3.2**. All 37 HTTP routes, protocol
codecs, authority/storage behavior, shared browser sessions and launch commands
are preserved. The migration smoke tests used isolated authority state.

**77 Server tests passed**, including 20 HTTP tests with real socket boundary
checks. The production executable passed an isolated real-HTTP smoke run with
official Google trust refresh, bundled assets, bounded/chunked and partial-body
requests, v2 preparation, UI sessions, idle connection closure and private logging.
SIGTERM and SIGINT shutdown/restart retained the same authority pin and ledger.
The browser adapter regressions passed. See
[migration evidence](artifacts/vapor-migration/README.md).

**Installed Xiaomi app acceptance passed against Vapor** using the existing
authority pin and hardware root: fresh epoch 124301, signed workload acceptance,
replay rejection, online credential verification and tamper rejection. App restart
preserved the exact credential and accepted a new workload without issuing
another epoch. Ledger head advanced 10 → 13 → 14; account membership was unchanged.
See [hardware evidence](artifacts/vapor-hardware/README.md). This exercises the
older installed workload app, not the newly built v2 phone UI. Pixel wireless ADB
is connected; its retry needs the phone unlocked because Doze blocked app networking.

The phone-build counts and physical-device history below describe their earlier
checkpoints. Two-phone v2 hardware acceptance remains pending.

## Android phone pairing v2

The [v2 build](docs/PHONE-V2-BUILD.md) connects strict canonical records, the
transactional authority, durable client, shared UI and native Android
StrongBox/QR adapters. It supports accountless admission, mutual pairing, joint
account genesis, independent sign-in/epoch issuance, adding/replacing owners,
trust lease renewal and interrupted-request recovery. V2 is opt-in; enabling it
permanently retires unused legacy provisioning and persists schema 3 so older
binaries cannot bypass the cutover. No live state was changed.

Phone-build local checks: **Core 26, Client 47, Application 35, UI 26 and Server 73 tests
passed** (207 Swift tests), plus **7 native phone-host tests**. The Android ARM64
Swift/JNI library and debug APK built. The actual shared Swift components expose
27 phases and a [43-surface catalog](artifacts/phone-ui/README.md); all surfaces
passed Chrome checks at 320 px with enlarged layout without document overflow
or console warnings/errors.

[Current evidence](artifacts/phone-v2/README.md) includes test logs, browser
checks and the APK hash. The APK was not installed during that build. Phones are
now connected for Vapor checks, but the v2 APK remains uninstalled.
Physical two-phone StrongBox pairing, camera/secure sheets, process restart,
response loss and replacement remain acceptance gates. A fail-closed provider
verification disagreement on a deliberately tiny fixture key is preserved in the
[Core validation note](artifacts/phone-v2/core-client-validation.md); changing
fixture keys did not resolve that provider behavior.

Standalone revocation, arbitrary policy changes, browser grants, fresh
attestation/root rotation, legacy account upgrade and iOS remain unavailable.
Older evidence below describes earlier builds and does not establish v2 physical
acceptance or the current APK hash.

## Earlier shared workspace migration

The application and view layer is now shared Swift. `SwiftKeyApplication` owns
workspace state/actions and service contracts; `SwiftKeyUI` owns the identity,
public-key and administrative workspace components. The website evaluates these
views on the Swift server and sends RenderNode trees to a generic browser
adapter. The former account-specific HTML/JavaScript application has been
replaced; the browser retains only transport, primitive rendering and platform
effects. This is server-driven Swift UI, not Swift WebAssembly.

Host checks reported for this migration: **Core 16, Client 33, Application 9,
UI 9 and Server 50 tests passed**, including secure-field serialization and
Swift browser-session integration checks.
The shared desktop library and Android ARM64 APK build. Android renders the
shared identity/public-key components; `WorkspaceView` compiles for Android,
but no native administrative session/service adapter is connected yet.

The new Swift operator consumes an account-bound enrollment bundle, checks its
expiry and a separately supplied authority pin, and transfers configuration
over USB into a fresh app installation. It refuses existing configuration or
protocol state. The live path now passed: **shared SwiftUI account action → enrollment bundle →
Swift operator → Pixel StrongBox enrollment → epoch credential 124299**. The
new account is `5ada6341-4338-433c-aae9-31a7e715ed1a`; device
`6788bc41-623f-4b5a-9184-fa5faf0ea337`. API and shared-UI verification both
accepted the exact credential; a tampered signature returned 403. Verification
did not advance ledger head 10. App restart reported `epochCredentialReused=true`.

Browser controls passed against an isolated SQLite copy: creation/export,
invalid-name rejection, expired-credential rejection, current Pixel verification
and exact public-key copying. Layout was inspected at 1280px and at 320/390px
without overflow; no console errors occurred. The modifier-order fix passed
visual inspection. The Pixel screenshot confirms the shared identity screen,
but native dark colors differ from the browser. Setting `forceDarkAllowed=false`
and reinstalling did not fix the palette; its cause remains unresolved.
The final APK SHA-256 is
`f09e3591eb2cdedd4d6659950c1e8eed2a3e37e5a3d9663198fd63a6d17c8e69`.
Its final UI XML matches all 65 enrolled root bytes; fresh signature checks and
credential reuse passed, with head 10 unchanged. Public evidence is in
[artifacts/swiftkey-shared-swift](artifacts/swiftkey-shared-swift/).

Historical checkpoints remain below. The September 19 HTML/JS design/browser
checks and older Android hardware results apply to those versions, not to the
current migration. The old authority contained two real accounts (one imported
active account, one pending Development account), one enrolled root, one now
expired epoch-124295 credential and ledger head 4. No account/device record is
seeded by the frontend. A pending account is not an enrolled phone.

The original real Android protocol run passed StrongBox enrollment, epoch
issuance, workload acceptance/replay rejection, app/server restart, activity
recreation and offline public-key display. The SQLite migration retained the
identity, exact credential and six replay records; independent Python/OpenSSL
checks verified the historical head 4. See the evidence index below for those
scoped results. Physical pairing/recovery, wall-clock epoch rollover, attestation
renewal, a native administrative workspace and iOS authorization remain open.

## Protocol implementation and proof

| Component / check | Current evidence |
| --- | --- |
| `SwiftKeyCore` | **16 host tests passed**: canonical vectors, independent OpenSSL signature, tampering, exact epoch bounds, lazy rotation and snapshots |
| `SwiftKeyClient` | **33 host tests passed**: enrollment, persistence failures, retry behavior, signing/replay handling and membership operations |
| `SwiftKeyApplication` / `SwiftKeyUI` | **9 + 9 host tests passed**; shared actions, presentation, callbacks and primitive contract |
| Server/storage/HTTP suite | **50 tests passed**, including Swift session dispatch and secure-field serialization |
| Shared browser / Swift operator / Pixel | **Live account action, exported bundle, StrongBox enrollment and epoch 124299 issuance passed**; verification accepts exact credential and rejects tampering |
| Shared renderer/browser behavior | **Passed**: real controls, validation, expiry rejection, complete key copying, desktop 1280 / mobile 320/390 and no console errors |
| New Pixel restart | **Passed**: existing epoch credential reused; no forced root/leaf replacement |
| SQLite snapshot/event/commit ledger | **Live migration and two restarts passed**: signing/root keys, membership, exact epoch credential and six replay records preserved; legacy JSON unchanged |
| Historical admin API / previous web console | **September 19 live connect/render/create/reissue passed**: real imported root/epoch, pending Development account, head 1 → 3 → 4, no JS errors/warnings |
| Pending-account invitation reissue | **Passed in the prior browser and host tests**; new one-use token revealed only for the action, then dismissed |
| Independent ledger verification | **Passed at head 4**: Python canonical event SHA-256 chain and OpenSSL ECDSA head signature against the preserved authority pin |
| Android bridge | Swift Crypto/Core/Client cross-build and Kotlin bridge compile; updated APK installed and client contacted the local server |
| Historical September 19 protocol APK payload | **Passed**: 496,227,763 bytes; 27 ARM64 native libraries, no test runtimes |
| Real hardware evidence | Five StrongBox attestation certificates captured; local possession/security-level checks passed |
| Strict remote enrollment | **Passed on physical Android** with the real five-certificate StrongBox chain |
| Real epoch delegation / workload / replay rejection | **Passed on physical Android**, epoch 124295; explicit acceptance and replay-rejection events |
| Protocol persistence across restart | **App and server restart passed**: same root/delegation/credential, retained replay ledger, fresh nonce count1 → 2 → 3 and replay rejection |
| Activity recreation during pending request | **Passed**: two recreations while the server was paused, same PID25901, exactly one completed workload and nonce count3 → 4 |
| Offline attested-key display | **Passed** with adb reverse removed: exactly the name and attested root bytes remained visible; transport failure reported, no server nonce consumed |
| Return online / final screen | **Passed** after restoring adb reverse: new nonce count5, same original credential, replay rejected; final screenshot inspected |
| Pairing, revocation and recovery | Shared APIs and software-fixture tests implemented; **physical-device proof pending** |
| Actual four-hour rollover on device | **Pending**; host boundary/rotation tests do not substitute for this |
| Attestation renewal | **Not implemented**; the historical September 19 phone chain has an RKP intermediate expiring on 2026-09-27; the new Pixel chain’s expiry has not been inspected |
| iOS authorization | **Not implemented; postponed**. Apple App Attest authorization fails closed |

The authority uses official Google roots/revocation data, StrongBox key and
verified-boot policy, exact app/signing-certificate identity, challenge-bound
possession and current membership. Review fixes bind persisted state to its
security policy and revalidate retained attestation chains before root
mutations/workloads, with state checks repeated after asynchronous validation.
Fixture verifiers are not selectable through production HTTP or configuration.
Host fixtures do not prove that a real device has satisfied those checks.

`swiftkey.device-root.v1`, the original display-demo alias, is preserved.
Protocol enrollment uses the separate `swiftkey.attested-root.v1` alias so its
immutable certificate binds the server-issued challenge. No hardware private
key is exported and there is no software fallback. The screen remains only
`SwiftKey` and public-key bytes. The attested-key accessor prefers and locally
validates an existing attested root even offline; the runner revalidates it
before publishing, and a process-wide coordinator prevents activity recreation
from racing client-state updates. The historical September 19 APK exercised those display and
lifecycle paths successfully; that evidence predates the SQLite/admin extension.

The new persistence layer imports v1 state without rewriting `authority.json`,
preserving the server/device identity, challenges, replay nonces and exact latest
credentials. An honest `authority.imported` event marks the boundary; older
events/epoch credentials that v1 never retained cannot be reconstructed.
New epoch credentials are retained across subsequent rotations. The signed
`swiftkey.ledger-head.v1` checkpoint authenticates sequence/hash, but complete
database rollback detection still requires an external retained checkpoint.
The console does not change mobile UI or replace root-authorized operations.

## Local commands

From `/Users/mac/SwiftKey`:

```bash
scripts/androidswiftui.sh doctor
scripts/swiftkey-protocol.sh test
scripts/androidswiftui.sh android-run
```

Start the authority with `scripts/swiftkey-protocol.sh server`. Open
`http://127.0.0.1:18088/` using the private
`SwiftKeyServer/.state/admin-token`. It is a global operator credential, not a
consumer account login or device-membership credential. Browser transport keeps
it only in memory. `status`/`ledger` script commands read it privately.

For a new account, create/reissue an invitation and choose **Export enrollment
bundle**. The downloaded JSON is secret and expires with the invitation. With
the debug APK installed on an authorized, fresh Android installation:

```bash
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" run --package-path SwiftKeyServer swiftkey-operator provision-android \
  --bundle-file /absolute/private/enrollment.json \
  --pin-file /Users/mac/SwiftKey/SwiftKeyServer/.state/server-public-key.txt \
  --serial DEVICE_SERIAL
```

The Swift operator validates expiry, exact expected account, independently
supplied pin and explicit loopback endpoint, creates `adb reverse`, writes
app-private configuration and launches the app. It never resets existing
hardware identities; an expired challenge or lost state requires an explicit
recovery decision. Refresh the website to verify the actual enrolled root and
credential; process launch alone is insufficient.

The `configure-android /absolute/private/enrollment.json` wrapper now requires
the bundle and calls the same Swift operator; set `ANDROID_SERIAL` to choose
the device. The old global-bootstrap shortcut is removed.
Operator build and seven isolated fake-adb checks pass; these are not hardware
enrollment proof. This remains local development over loopback/USB with the debug
APK signer pinned. No public deployment, TLS or production signing rollout is
claimed. Contracts are in [PROTOCOL.md](PROTOCOL.md) and
[the server wire reference](SwiftKeyServer/WIRE.md).

## Platform readiness

| Check | Result |
| --- | --- |
| Upstream SwiftUICore host suite | **123 tests in 16 suites passed**, initially with Swift 6.4.0 |
| Pinned compiler / Android SDK | Swift **6.3.2**, downloaded and checksum verified; global Swiftly remains 6.4.0 |
| Environment | `doctor` passed with JDK **21.0.11**, NDK **27.3.13750724 (r27d)**, ARM64/API 28 SDK |
| Gradle compatibility / APK | Dependency compatibility, Android Swift cross-build and debug assembly passed |
| Original minimal APK inspection | **27 ARM64 libraries**, including app, SwiftJava, Swift runtime and libc++; no XCTest/Testing |
| Physical Android | Device `D6OZUCKVEIQ4LVLV`, model `2506BPN68G`, API 36; install/launch passed |
| Original key display / local signature | **Passed**: `securityLevel=STRONGBOX`, `signVerify=true`, matching 65-byte UI hex and inspected screenshot |
| Original root persistence | **Passed** after force-stop/relaunch, identical 130-character public hex and fresh signature verification |
| Desktop library / JNI integration | **Passed with Swift 6.3.2**: one executed test, zero skips/failures/errors, Catalog → Text → counter 0 → 1 → 2 |
| Earlier iOS catalog | Built/launched in iPhone 17 Pro / iOS 26.4.1 Simulator; Catalog screenshot inspected |
| Minimal iOS hardware screen | **Not implemented; postponed until physical device** |

The scripts select the matching compiler through its absolute path and
`TOOLCHAINS`, with JDK/SDK/NDK checks. `SWIFTKEY_SWIFT` is the custom Gradle
compiler override; SwiftPM's reserved `SWIFT_EXEC` is not repurposed.
The existing `AndroidSwiftUI/` checkout started at
`e12fb09a906921506a84287f53117ccbf4357102`; local changes remain uncommitted.
The parent directory is not a Git repository. `fullplan.md` is preserved.

## Evidence and historical results

Current shared-Swift evidence is in
[artifacts/swiftkey-shared-swift](artifacts/swiftkey-shared-swift/):
`live-account-device-credential.json` records the new account/device/credential;
`android-restart.log` records fresh StrongBox verification and credential reuse;
`android.xml` and `android.png` record the first inspected identity screen.
`android-final.png`, `android-final.xml` and the nonempty `android-final.log`
record the final installed build, unchanged root/credential and unresolved dark
palette. Initial enrollment is evidenced by the live JSON and persisted events.
These are separate from the older OEM phone
and replaced HTML/JS console evidence below. Browser mutation checks used an
isolated authority copy; they do not fabricate devices in the live authority.


Console/SQLite evidence is in [artifacts/swiftkey-server](artifacts/swiftkey-server/):
`migration-baseline.json` and `live-migration-proof.json` compare the real v1
identity, credential and replay state with the migrated registry. The browser's
one-time enrollment bearer was dismissed before evidence capture. These are
separate from the earlier physical Android artifacts below. `ledger-verification.json`
records independent Python canonical-hash and OpenSSL head-signature validation;
this is not an externally operated rollback witness.

September 19 protocol evidence: [artifacts/swiftkey-protocol](artifacts/swiftkey-protocol/).
It contains the five public certificate DER files,
`android-attestation-evidence.json`, and `android-first-enrollment`,
`android-app-restart`, `android-server-restart` JSON/log pairs. These record
live enrollment/workload results, app/server persistence and replay rejection.
`server-before-restart.json` supplies the prior public replay-ledger comparison.
Host suite results are preserved as `core-tests.log`, `client-tests.log`, and
`server-tests.log`; see the [artifact guide](artifacts/swiftkey-protocol/README.md).
Captured certificates alone are not an accepted-enrollment result.
`device-verification-final.log` records the September 19 server binary validating the
older phone’s real chain. `android-final-apk.json` records the September 19 protocol APK, SHA-256
`6819a7f47d8d5e5a3c7f887c2484249f67fcdad0f75a64238347599e028dd9e1`.
`android-activity-recreation`, `android-offline`, and `android-final-online`
JSON/log pairs cover the historical September 19 lifecycle/network checks. The UI XML files
and inspected [attested-key screenshot](artifacts/swiftkey-protocol/android-attested-key.png)
show exactly the project name and matching attested root bytes.

Earlier platform evidence: [artifacts/androidswiftui](artifacts/androidswiftui/).

- `hardware-key-first-launch.log`, `hardware-key-relaunch.log`, both UI XML
  dumps and `hardware-key-verification.json` prove the original local root's
  display, signature check and process-restart persistence.
- [hardware-key.png](artifacts/androidswiftui/hardware-key.png) is the inspected
  original minimal-screen screenshot; it predates protocol enrollment.
- `android-install-success.log` / `android-launch-success.log` record the
  successful installation retry. The earlier `INSTALL_FAILED_USER_RESTRICTED`
  entry in `android-hardware-build-install.log` is historical and resolved.
- `android-hardware-apk.json` records the **earlier** approximately 479 MB APK,
  SHA-256 `ba3688d5451ea1aa1e93f9f27909d4ab636193089783805ac05b921d5e7930ea`;
  it is not the fingerprint of the new protocol APK.
- `core-tests-swift-6.4.0.log` and `android-dependency-check.log` record the
  upstream 123-test suite and Gradle compatibility pass.
- `desktop-final.log` records the successful desktop library build and Gradle
  integration run; `desktop-bridge-test.xml` confirms the bridge test executed
  and passed without skipping. `host-bridge-swift-6.3.2.log` is earlier build
  evidence. `desktop-*-attempt.log` files are historical unsuccessful attempts;
  compiler/download blockers were subsequently resolved.
- Emulator readiness files are not hardware-key evidence.

[The iOS catalog evidence](ios-simulator/evidence/) includes `build.log`,
`launch.log` and inspected `catalog.png` for `com.swiftkey.catalog.demo`.
The preserved Simulator wrapper is a catalog demo, not an App Attest client or
minimal hardware-key app. No further iOS implementation is authorized yet.
