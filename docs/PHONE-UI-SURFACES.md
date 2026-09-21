# Phone protocol: UI surface contract

This contract follows [pairing protocol revision 0.2](PAIRING-ACCOUNT-PROTOCOL.md).
The named surfaces below are coverage requirements, not a statement that their
transport, native effects or security checks are implemented. A component catalog
may render every stage while the live service remains unavailable.

The shared phone flow is separate from the legacy administrative workspace.
The v2 authority/client transport is still an implementation gate. Rendering a
screen, pressing a preview button, or holding an administrator session is never
evidence that a phone has joined an account.

## Screen and component coverage

| Protocol step / surface name | Required surface | Explicit user action and completion evidence |
| --- | --- | --- |
| Entry / `introduction` | Pair another device; supported hardware and authority; distinction between creating an account and joining one | Prepare this phone. No account is created. Unsupported profiles show an explanation with no signing control. |
| Accountless admission / `preparingIdentity` | Preparing identity, attestation validation, retained-root state, safe error | Preserve the same root and preparation record across retry. A verified trust receipt advances the view. |
| Rendezvous creation / `invitation` | Purpose, authority, expiring invitation, QR host surface and camera-free full-link sharing | Show/share only a transient link. Explain that the recipient can inspect the bounded account context/roster for add/replace. Keep the original QR deadline. |
| Lost invitation / `invitationRotation` | Known operation and signed `OPEN` state, fixed expiry, explicit rotation control | Reconcile a lost creation response by original request ID first. Rotate only as the initiator before a peer binds; bind current revision, invalidate the old secret/inspection, and keep the original deadline. `PEER_BOUND` cannot rotate. |
| Receive invitation / `importingInvitation` | Camera entry, permission-denied/manual-import alternatives | Import full link through host private memory. Validate configured origin and protocol before inspection. Scanning cannot sign consent. |
| Inspect / `inspectInvitation` | Initiating phone fingerprint/root epoch, purpose, authority; for add/replace: account ID/label, policy, full current roster/revision and exact replacement target | Pair these devices only after the signed inspection is verified and reviewed. Reject a different purpose, account, authority, epoch or target. Candidate attestation and camera recognition grant no consent. |
| Compare peers / `comparePeers` | Both complete fingerprints, five comparison-code groups, transcript deadline | Compare through a trusted channel, then explicitly confirm or reject. Never treat a short code as a credential. |
| Pair consent / `waitingForPairConsent` | Separate local and peer approval states and expiry | Refresh authenticated state. One accepted consent grants no new rights. |
| Paired / `paired` | Verified pair receipt; no-account explanation for genesis; exact existing-account context for membership | Propose account label/policy or continue to the membership proposal. |
| Genesis proposal / `reviewGenesis` | Label, reserved account ID, both owner identities, authority, survivor policy and takeover tradeoff | Create account with these two owners. Only the fixed survivor policy is available. Editing the label requires explicit proposal replacement and new approvals, as below. |
| Genesis edit / `replaceGenesis` | Current proposal hash/revision, existing label, editable label and warning that both approvals will be cleared | Replace through a fresh signed intent binding the old proposal hash and new normalized label; keep the original pair-receipt deadline. No silent mutation of a review already shown to the peer. Arbitrary policy selection stays unavailable. |
| Genesis waiting / `waitingForGenesisConsent` | Which root approved, immutable proposal reference, fixed deadline | Await or reconcile. Never optimistically show an account. |
| Committed / `committed` | Locally verified receipt, operation/account, membership revision and complete resulting owner roster | Continue to independent sign-in. An unverified response cannot display success. |
| Owner authentication / `signIn` | Account, signing phone, origin and requested scopes | Sign in with this phone through a fresh hardware challenge. A receipt is not a session. |
| Post-commit sign-in retry / `signInRetry` | Phone added/account created, retained verified receipt, separate sign-in or credential failure | Retry independent sign-in/delegation. Never describe an already committed membership change as failed or repeat the pairing. |
| Receipt detail / `receiptDetail` | Proposal/receipt hashes, signer identities/epochs, exact delta, membership revision and ledger checkpoint | Inspect/export only public receipt data. Clearly distinguish its historical result from current owner access; a revoked root may retrieve its own past public result without regaining access. |
| Owner list / `owners` | Complete current roster, full root fingerprints/epochs, trust/revocation status, membership revision | Select Add phone or Replace lost phone using a freshly verified signed roster. Show its freshness and recheck the current revision before signing. Standalone removal is unavailable in this revision. Account ownership and admin access remain distinct. |
| Add / replace / `chooseOwnerChange` | Explicit operation choice; exact lost device/root when replacing | Review survivor authority and full before/after roster. A replacement must not remove the authorizing survivor. |
| Membership approval / `reviewMembership` | Account ID/label, existing policy/revision, authorizer, candidate, exact removal target, resulting roster | Owner approves and candidate accepts the same immutable proposal. Neither approval activates the candidate alone. |
| Membership waiting / `waitingForMembershipConsent` | Both approvals, original deadline and current revision | Refresh authenticated state. A changed membership/root epoch/policy invalidates the ceremony: start a new pairing and obtain all new pair and membership consents. Never automatically rebase a proposal. |
| Revoke / `reviewRevocation` | Exact root being removed, remaining owners and effect on its sessions/credentials | Unavailable: the standalone revocation wire proposal is not specified in revision 0.2. With exactly two owners explain the minimum and offer Replace lost phone; with more owners still do not expose a signing action. A stage in the catalog does not enable a route. |
| Policy change / `reviewPolicy` | Current and proposed policy, all required owner approvals | Unsupported policy changes remain unavailable; never offer an admin override. |
| Browser login / `reviewBrowserLogin` | Browser origin, requested scopes, lifetime and approving root | Separate device approval; unavailable until its wire protocol and native adapter are implemented. A browser cannot become a hardware owner. |
| Credential/trust lifecycle / `renewingTrust` | Independent sign-in/credential status, trust expiry, evidence-renewal availability | Explain retained evidence and recovery accurately. Do not silently regenerate a root or imply pairing renews attestation. |
| Expired / `expired`; cancelled / `cancelled` | Terminal outcome, retained-root explanation | Start a new ceremony only after the previous outcome is known. Do not reopen the old operation. |
| Rejected / `rejected` | Explicit local or peer refusal, terminal operation reference, retained-root explanation | A signed rejection ends that ceremony without changing membership; begin again only with a new operation. Do not relabel it as timeout or transport failure. |
| Invalidated / `invalidated` | Membership, root-epoch or policy change; old revision and current safe context | Refresh roster and start a new pairing with new user approvals. The old operation cannot resume or transfer its approvals. This is distinct from expiry, cancellation and rejection. |
| Response lost / restart / `outcomeUnknown` | Outcome unknown, original operation reference, resume action | Retrieve the existing result with authenticated proof. No automatic duplicate mutation, replacement or account creation. |
| Trust failure / `trustUnavailable`; revoked / `revoked` | Specific safe failure category, whether an approval was sent, original operation reference and available recovery route | Fail closed. Temporary verifier unavailability may retry only before the same deadline; a possibly sent approval requires outcome reconciliation. Preserve local keys; no email, short-code, software-root or admin bypass. |
| Identity conflict / `identityConflict` | Already-owned/reserved candidate, missing preparation state, unsupported root or expired/revoked evidence | Explain the exact safe category. Retain the root and original preparation; never regenerate it silently or move it to another account. Unknown/missing identity recovery remains unavailable until specified. |
| Legacy account / `legacyAccount` | Declared legacy policy, existing identity and upgrade availability | Show that v2 addition/replacement requires the separately specified upgrade. Do not route this ceremony through legacy approve/confirm endpoints. |
| No surviving owner / `recoveryUnavailable` | All accepted owners lost or unable to satisfy trust, retained account identity | Explain that this policy has no administrator/email recovery bypass. Do not show a recovery approval control. |

## Interaction and state rules

Approval, rejection, cancellation, secret rotation and genesis-replacement
actions carry the operation ID, revision, canonical object hash and
deadline shown on screen. A service adapter must compare them with its current
verified state before requesting a root signature and recheck at authority
commit. A stale rendered callback must not approve the newest object implicitly.
The view blocks mutation signing when busy, expired, unavailable or awaiting
outcome reconciliation. Receipt-only authentication remains a separate scope. Host capability flags describe available effects, not security
authorization. `nativeReady` alone does not enable a profile or route whose wire
contract is still gated (standalone revocation, policy change, browser login,
fresh attestation/root rotation and legacy upgrade).

Each participant sees their own acceptance separately from the peer's. The host
supplies a clock updated while the screen is visible and rechecks time on every
action. Countdown expiry stops approval immediately; it does not prove server
cancellation. Terminal success requires verification of the receipt and its exact
account, operation, signer, peer, policy, revision and local approval bindings.
For membership review the two consent indicators identify the **authorizing
owner** and **candidate**, while the owner-list/result surfaces show the entire
before/after roster. Root epochs and full fingerprints remain visible; matching
a device ID or label alone cannot establish the intended replacement target.
Before join/peer confirmation, the candidate sees the same exact existing-account
context that the authorizer signed. Changing its purpose or target requires a new
pairing, not an in-place edit of a consent screen.

A returned root-sequence conflict requires a fresh challenge for the same request
and payload; keep accepted consent progress. A membership revision conflict is
terminal `invalidated` and requires a new ceremony. Never report **No approval
was sent** after a transport timeout unless the adapter has evidence it never
submitted the request. Show the original request ID and `outcomeUnknown` until
its result is known. A signed terminal state, not a local countdown or modal
dismissal, establishes cancellation/expiry for restart purposes.

The shared action vocabulary must include explicit join, pair confirm/reject,
propose/replace genesis, approve genesis, propose/approve membership, unjoined
secret rotation, cancel/reject proposal, authenticated result lookup and restart.
A proposal rejection is distinct from rejecting the earlier peer transcript.
Read-only result reconciliation remains usable after a deadline and after
revocation within the protocol's historical-public-receipt scope. Persist the
highest verified operation revision/checkpoint; a late polling response cannot
move the view backward or overwrite a committed outcome.

The host owns camera/QR generation, clipboard/share, deep-link ingestion and
private storage. The shared Swift layer owns screen composition and typed
operation selection. Hide unavailable effect controls; permission denial must
leave the full-link import path reachable. QR graphics must encode the actual
transient invitation, with adequate quiet zone and contrast. Never draw a fake
QR as a placeholder that appears scannable.

Public snapshots contain no rendezvous secret, private key, preparation token,
session bearer or raw imported link. Links travel only through transient host
effects. Remove incoming URL fragments immediately, avoid analytics and browser
storage, and erase clipboard/export staging when dismissed or expired. A browser
adapter may render verified public state; only a native root adapter can sign.

## Accessibility and verification

All screens scroll at small widths and enlarged text sizes. Keep full
fingerprints selectable/readable and preserve their order. Use descriptive
headings, visible field labels, accessible button names, and stable semantic
identifiers. Approval progress must use text as well as color. Never announce a
countdown every second to assistive technology. Focus moves to the new heading
or safe error after a transition; errors must not expose attestation chains or
private transport details.

Verification has three distinct levels:

1. Shared-state and rendered-callback tests cover allowed actions, exact binding,
   root epochs, expiry, duplicate submission, approval counts, receipt gating,
   terminal-state distinctions and secret exclusion. Include stale callbacks
   after label replacement, forbidden post-join rotation, roster invalidation,
   unavailable standalone revocation, and committed membership with sign-in failure.
2. The component catalog renders these same Swift views using synthetic public
   records. Inspect narrow and large-text screens, long identifiers, terminal
   failures and uncertain outcomes, and each named surface above. Missing
   transport/effect adapters stay visibly unavailable. Its buttons do not perform
   real operations.
3. Production acceptance still requires the v2 service/native adapters, two real
   hardware roots, camera/manual handoff, restart/response-loss recovery and
   independently verified receipts. A component catalog cannot satisfy this gate.

## Connected Android host

`NativePhoneProtocolService` supplies verified snapshots from `PairingClient`.
Android presents secure QR/share and camera/manual-import sheets outside the
public view tree. The live adapter connects all revision 0.2 mutation actions,
retained-root lease renewal, result recovery and independent sign-in/epoch
issuance. A known local rejection does not manufacture an unknown request;
recovery controls appear only for a durable outstanding request.

The owner screen can explicitly refresh its own sign-in and epoch credential
without repeating pairing. A failed credential request preserves the committed
account receipt. Failed identity admission without a verified receipt has its
own retained-root explanation and cannot invoke trust renewal or silently
replace a root.

After pairing-first cutover, authority metadata disables the legacy admin
account-creation form and invitation reissue. The shared workspace explains
that two native phones create the account; stale form callbacks are rejected
before invoking the service. The authority independently enforces the same gate.

The current catalog contains 43 synthetic surfaces. Live hardware acceptance is
tracked in [the build guide](PHONE-V2-BUILD.md).
