# SwiftKey

Clone the workspace with its pinned Android renderer:

```sh
git clone --recurse-submodules https://github.com/maceip/Swiftkey.git
```

`main` contains the workspace. The `AndroidSwiftUI` submodule preserves the
upstream history on this repository’s separate `androidswiftui` branch.

The current [design system](SwiftKeyDesign/README.md) uses the supplied
`design-system-main.zip`: adaptive purple themes, rounded cards, Host Grotesk
and JetBrains Mono across the webpage and shared device views.
[Optional autoresearch tooling](tools/DesignResearch/README.md) implements the
TypeSafe/CatBoost feature-discovery method for labelled text evaluations.
It is separate from the runtime UI and has not been trained on real UI ratings.

The [pairing-first protocol](docs/PAIRING-ACCOUNT-PROTOCOL.md) now has an opt-in
v2 implementation: two Android hardware identities pair, approve account genesis
and become equal owners. Adding or replacing an owner requires both the surviving
owner and candidate to approve the exact membership proposal.

The authority, durable client, shared UI and Android native host are connected.
See [setup and verification](docs/PHONE-V2-BUILD.md) and the
[UI surface contract](docs/PHONE-UI-SURFACES.md). Existing installations retain
their legacy records; no live deployment or account migration was performed.
Build the synthetic component catalog with `bash scripts/phone-ui-preview.sh`.

An attested-device identity protocol and shared Swift application. A hardware
root authorizes four-hour software signing keys; the online authority checks
membership, attestation policy, signatures and replay state.

The application is split into portable Swift layers:

| Package | Role |
| --- | --- |
| [SwiftKeyCore](SwiftKeyCore/README.md) | Canonical protocol values, cryptography and public DTOs |
| [SwiftKeyClient](SwiftKeyClient/Sources/SwiftKeyClient/ProtocolClient.swift) | Hardware-backed enrollment, epoch credentials and device operations |
| [SwiftKeyApplication](SwiftKeyApplication/README.md) | Shared workspace state, typed actions and service contracts |
| [SwiftKeyUI](SwiftKeyUI/README.md) | Shared identity/public-key components and workspace views |
| [SwiftKeyServer](SwiftKeyServer/README.md) | Vapor/Swift HTTP authority, SQLite ledger, isolated Swift browser-view sessions and USB operator |

Android renders the shared identity components through ComposeUI. The website
evaluates shared Swift views on the server and uses generic JavaScript only for
DOM rendering, event transport and browser effects. It does not run Swift
WebAssembly. `WorkspaceView` compiles for Android, but the phone does not yet
have a native administrative service/session. iOS remains postponed.

```sh
scripts/androidswiftui.sh doctor
scripts/swiftkey-protocol.sh test
scripts/swiftkey-protocol.sh server
```

The backend uses Vapor 4. Existing launch commands, JSON routes, authority pins
and SQLite state remain compatible. See the
[migration verification](artifacts/vapor-migration/README.md) and the
[installed Android app acceptance](artifacts/vapor-hardware/README.md).

Open `http://127.0.0.1:18088/` using the private
`SwiftKeyServer/.state/admin-token`. This is a local operator credential. Create
an account and export its private enrollment bundle, then provision a fresh
debug app installation on an authorized USB Android device:

```sh
ANDROID_SERIAL=DEVICE_SERIAL scripts/swiftkey-protocol.sh configure-android /absolute/private/enrollment.json
```

The wrapper calls the Swift operator, validates the account/expiry and separate
authority pin, and refuses existing configuration or protocol state. It never
silently resets a hardware identity. Refresh the workspace to confirm real
enrollment and credential issuance; a successful build or process launch is
insufficient. The bundle is a secret, not an evidence artifact.

[BUILD_STATUS.md](BUILD_STATUS.md) distinguishes current work, host checks and
historical physical-device proof. [PROTOCOL.md](PROTOCOL.md) describes trust and
local operation; [buildplan.md](buildplan.md) retains the acceptance contract.
The shared-UI account action, exported bundle, Swift operator handoff and real
Pixel StrongBox enrollment/epoch issuance now pass end to end. Current-policy
verification and app-restart credential reuse also passed. Native admin sessions,
physical pairing/recovery, wall-clock rollover, attestation renewal and iOS remain
unfinished; no public deployment or pixel-identical native/web styling is claimed.
