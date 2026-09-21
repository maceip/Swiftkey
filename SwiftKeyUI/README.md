# Shared Swift UI

`SwiftKeyUI` defines one set of Swift components for the Compose/Android host and
the website’s RenderNode adapter. It depends on portable `SwiftUICore`,
`SwiftKeyApplication`, and the public protocol DTOs in `SwiftKeyCore`. It imports
no JNI, Android, HTTP server, SQLite, browser DOM, or hardware API.

- `SwiftKeyIdentityView` and `SwiftKeyPublicKeyView` render the complete supplied
  public bytes. Key creation and validation remain in the hardware/client layer.
- `WorkspaceView` renders an immutable `WorkspaceSnapshot`, host-owned
  `Binding<WorkspaceDrafts>`, and an optional transient invitation result.
- `WorkspaceAction` dispatches actual service operations through the shared
  application store. Filtering, section selection, form values, conditional
  controls, record formatting, and callback definitions are Swift.
- Optional `WorkspaceUIEffect` handlers implement clipboard and file delivery.
  Copy/export buttons are absent when the host cannot perform those effects.
  Enrollment export and invitation dismissal use explicit application actions.

The Android entry currently uses the shared identity composition. The workspace
component is compiled for Android and available to authenticated hosts; adding
an administrative workspace session to the phone requires a real service and
authorization adapter. Device membership is not an administrative bearer token.
The website evaluates these Swift components on the server; this is not Swift
WebAssembly execution in the browser.

Hosts serialize evaluation/callback execution, retain drafts per session, and
authorize every action. Browser callback IDs must remain decimal strings and
must be checked against the current session, revision, type, and enabled tree.
Secrets in transient enrollment results must not enter persisted snapshots,
logs, URLs, or browser storage. Disclosure expansion is presentation-only.

Host tests exercise rendered records and callbacks, including complete public
keys, state bindings, typed create/select/verify/paging actions, invitation
lifetime, stale status, receipt matching, and the primitive renderer contract.
All synthetic records live in tests. They do not establish hardware attestation.

```sh
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" test --package-path SwiftKeyUI
```

## Pairing-first phone surfaces

`PhoneProtocolView` is a separate, reusable Swift composition for the proposed
v2 protocol. It preserves the existing workspace. Its public `PhoneIdentityCard`
shows complete root fingerprints and key epochs. Every `PhoneProtocolPhase`
has a surface: prerequisites, preparation, invitation/import/inspection,
full peer comparison and five-group code, dual consent, immutable account
proposal and replacement, final receipt, native sign-in, owner roster,
add/replace review and consent, gated revocation, policy/browser access review,
trust renewal/failure, revoked, rejected/invalidated/cancelled/expired and
unknown-result recovery. Existing-account inspection includes the full roster,
policy, membership revision, authorizer and exact replacement root before join.

Supply `PhoneProtocolSnapshot`, `Binding<PhoneProtocolDrafts>`, current Unix time,
and typed action/effect handlers. Refresh the time while mounted and feed actions
to `PhoneProtocolStore`, whose clock validates again when a callback runs.
Snapshots are public projections supplied by a cryptographically verifying
native adapter, not proof of attestation. `notImplemented` is the default;
`browserReadOnly` permits public refresh only. No renderer can sign approvals.
Approval callbacks bind the exact immutable object, digest, revision and expiry.
Standalone revocation, policy change and browser grant remain unavailable.
The Android adapter supports explicit renewal of the same retained root when
its lease expires; other ownership approvals remain blocked during renewal.
An identity that was never admitted has a separate failure surface with no
renewal control. Owner management offers an explicit sign-in and epoch retry
without reopening account creation. Declining an unjoined invitation is
described as a local action on this phone.
The workspace account form follows the authority's `legacyProvisioningAllowed`
capability. After pairing-first cutover, it directs account creation to the
native two-phone flow; existing account records remain visible.

`PhoneHostCapability` explicitly enables camera, manual import and secure
invitation presentation. `PhoneProtocolEffect.presentInvitation` passes only a
public binding. The native host obtains and renders the real QR/link in its
separate secure, short-lived presentation, validates the current binding again,
and clears it on dismissal, expiry, state change or session clear. The shared
`phone.invitation-surface` region explains this handoff when it is unavailable.
The camera and manual-entry sheets return a transient `PhoneInvitationInput`
to the adapter; never retain its value in `PhoneProtocolDrafts`, snapshots,
RenderNode/BrowserTree data, diagnostics, URLs, clipboard without explicit
user action, or browser storage. The Android demo now implements these native sheets and
connects the v2 client/service through `AndroidPhoneProtocolBridge`; the
component catalog itself remains a public projection preview. Other hosts must
supply their own trusted adapter and secure effects.

The phone tests render every phase against the portable primitive contract,
exercise form and approval callbacks, and verify exact bindings, full comparison,
candidate/owner wording, expiry/busy/browser gates, explicit host effects,
unsupported-operation gating and unverified-receipt handling. They use only
isolated public test projections; they do not prove a physical pairing ceremony.
