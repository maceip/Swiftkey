# Vapor verification with the installed Android app

The running local server is the verified Vapor build and uses the existing
`SwiftKeyServer/.state` authority and its unchanged public pin. The state was
backed up privately before startup. No app installation, provisioning reset or
hardware-key replacement is part of this check.

**Passed on the already installed Xiaomi app on 2026-09-20.**
[`verification.json`](verification.json) records the installed APK hash, observed
process IDs and acceptance results. The script is
[`verify-vapor-android.py`](../../scripts/verify-vapor-android.py).
It requires an already enrolled app whose old epoch credential has expired.
Only explicitly allowed public fields are exported from client configuration and
state; bootstrap bearers and epoch private keys stay out of artifacts.

The installed workload demonstration completed fresh StrongBox sign/verify,
root-authorized epoch 124301 issuance through Vapor, app and authority credential
verification, signed workload acceptance and replay rejection. Tampering with the
credential signature returned HTTP 403. Ledger head 10 advanced to 13 with
exactly the device's challenge, epoch and accepted-workload events.

The first completion log was captured before Android's log buffer rolled. The
harness resumed that still-running PID using the preserved log, checked its PID,
identity, credential and matching authority events, then restarted the app into
a new PID. The restart reused the exact credential and root, accepted one fresh
workload and rejected replay again. It issued no new epoch; head advanced to 14
only for the fresh workload. Account and device membership counts stayed fixed.
[`android.png`](android.png) was inspected and shows SwiftKey's existing public
root display, matching the enrolled root. This is the older installed identity UI.

The authority executable SHA-256 is
`740b8efb5666f004480446f9b2c24a2c68ae77b1f7907cf4af27de099b00079f`,
the same Vapor build used for the production-executable smoke test.
Fresh boot attestation and two-phone v2 pairing were not exercised.

The Pixel is connected over wireless ADB. Its first app attempt timed out while
Android Doze blocked networking for the sleeping app UID. The shell could reach
the authority while the app UID could not. Pixel acceptance remains pending an
unlocked, foreground retry; the failed attempt is retained under `pixel/`.

The requested commit/push now has the Xiaomi live proof and needs a supplied Git
repository/branch. The workspace/backend currently have no Git repository; the
nested AndroidSwiftUI checkout points to PureSwift/AndroidSwiftUI, where the
current GitHub account has read-only access. Compose Cupertino is being examined
in a temporary checkout; it has not yet been vendored into this workspace.
