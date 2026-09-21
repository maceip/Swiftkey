# Shared Swift application verification — 2026-09-20

[verification.json](verification.json) records test counts, the installed APK
hash, browser checks and the remaining implementation boundaries.

The generic browser adapter regression suite is reproducible from the workspace:
`node SwiftKeyServer/browser-tests/adapter.test.cjs`.

The live path exercised shared SwiftUI account creation, private enrollment-bundle
export, Swift operator USB handoff, Pixel StrongBox enrollment and issuance of
epoch **124299**. The account is `5ada6341-4338-433c-aae9-31a7e715ed1a`; its device
is `6788bc41-623f-4b5a-9184-fa5faf0ea337`.

- [live-account-device-credential.json](live-account-device-credential.json):
  live authority records, exact credential, API/shared-SwiftUI verification,
  tampered-signature HTTP 403, unchanged head 10 during verification and the
  cold-restart comparison. Verification is a point-in-time authorization result,
  not execution of a signed workload.
- [android-restart.log](android-restart.log): fresh `STRONGBOX`/`signVerify=true`
  output for the same root and `epochCredentialReused=true` after app restart.
- [android.png](android.png) and [android.xml](android.xml): the first inspected
  Pixel identity screen and accessible text, before the theme experiment.
- [android-final.png](android-final.png), [android-final.xml](android-final.xml)
  and [android-final.log](android-final.log): final installed APK after setting
  `forceDarkAllowed=false`. All 65 displayed public-key bytes match the enrolled
  root; the nonempty log records fresh StrongBox signature checks and credential
  reuse. Ledger head remains 10. The palette **still renders dark**; the theme
  experiment did not fix it and the cause remains unresolved.

Final installed APK SHA-256:
`f09e3591eb2cdedd4d6659950c1e8eed2a3e37e5a3d9663198fd63a6d17c8e69`.
Accepted initial enrollment is evidenced by the live device record and persisted
`device.enrolled` / `epoch.issued` events, not a reconstructed log capture.

Browser mutation/control tests used an isolated SQLite copy: account creation
and export, invalid-name and expired-credential rejection, exact public-key
copying, and inspection at 1280px desktop / 320px and 390px mobile. No mobile
overflow or console errors were observed. These checks are distinct from the
live authority/Pixel acceptance recorded in the JSON. Historical imported records
were real retained records; synthetic host fixtures are confined to tests.

Reported host results: Core 16, Client 33, Application 9, UI 9 and Server 50 tests
passed. Those tests/builds do not replace the live results above. Android renders
the shared identity/public-key views; its compiled administrative WorkspaceView
has no native admin session yet. Physical pairing/recovery, actual four-hour
rollover, attestation renewal and iOS remain unfinished.

This folder is for public identities, credentials and verification results.
Enrollment bundles, admin bearers and private client/server state must stay out
of evidence files. The September 27 RKP expiry documented elsewhere belongs to
the older phone’s September 19 chain, not an inspected expiry for this Pixel.
