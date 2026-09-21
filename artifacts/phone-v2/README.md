# Phone v2 implementation evidence — 2026-09-20

The opt-in Android path is implemented from canonical records through the
transactional authority, durable client, shared screens and native hardware/QR
adapters. See [setup and physical acceptance](../../docs/PHONE-V2-BUILD.md).
These are local implementation, test and build results. No live configuration,
account or device record was changed, and the APK was not installed.

## Final checks

| Check | Result | Evidence |
| --- | --- | --- |
| Core | 26 tests passed; 46 independent vectors across 27 canonical records | [Log](core-tests.log), [details](core-client-validation.md) |
| Client | 47 tests passed | [Log](client-tests.log) |
| Application | 35 tests passed | [Log](application-tests.log) |
| Shared UI | 26 tests passed | [Log](ui-tests.log) |
| Authority, storage and HTTP | 73 tests passed | [Log](server-tests.txt), [integration cases](server-integration-cases.txt) |
| Native phone host | 7 tests passed | [JUnit results](native-phone-tests.xml), [Gradle log](native-tests.log) |
| Android ARM64 Swift/JNI and debug APK | Build passed; artifact postdates all production source changes | [Build log](android-build.log), [source/build audit](native-verification.json) |
| Actual shared view catalog | 43 synthetic surfaces checked in Chrome at 320 px and 140% layout scale; no document overflow or console warnings/errors | [Browser record](browser-verification.json), [catalog](../phone-ui/index.html) |

The 207 Swift tests include real client/application/authority integration with
cryptographic software roots and an explicitly injected test attestation verifier.
They cover mutual pairing, joint account genesis, both approval orders for add
and replace, removed-root rejection, historical receipt recovery, response loss,
restart, signed negative recovery, trust/revision races and irreversible schema-3
cutover. They do not establish physical hardware attestation.

The [debug APK](../../AndroidSwiftUI/Demo/app/build/outputs/apk/debug/demo-app-debug.apk)
is 505,049,043 bytes. Its SHA-256 is:

```text
175572bee26d57c767aa0c94846cb55e007afd56948145314344a94293092ac7
```

## Remaining verification

No Android devices were connected. Two-phone StrongBox admission, camera
permission/QR transfer, physical layout, process restart, response loss,
replacement and independent sign-in must still be exercised on devices.

A deliberately tiny test key exposed a fail-closed crypto-provider verification
disagreement. The [Core validation note](core-client-validation.md) and public
reproducer preserve the observations. Production verification was not relaxed;
replacement full-width fixture and generated-key roundtrips passed. The fixture
change does not resolve that provider behavior.

Standalone revocation, arbitrary policy changes, browser-login grants, fresh
attestation/root rotation, legacy account upgrade and iOS remain unavailable, as
documented in the build guide and their UI surfaces.
