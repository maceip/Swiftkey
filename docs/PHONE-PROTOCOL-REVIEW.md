# Add-phone protocol review — 2026-09-20

The previous protocol was not adequate as an implementation contract for adding
or replacing a phone. Its existing-account flow lacked complete signed messages,
consent states and atomic commit rules. The legacy implementation also contained
two concrete security flaws. The review corrected the specification, hardened
the legacy code, and added shared UI surfaces. This is not a production v2 rollout.

## Findings and disposition

| Finding | Correction / current boundary |
| --- | --- |
| A pending candidate could be rebound to another hardware key by reusing its challenge, including across an asynchronous attestation race. | The authority now fixes the first accepted candidate; matching retries return that candidate. Changed identity is rejected. |
| Candidate attestation was not revalidated when approval/recovery activated membership. A new asynchronous check also needs a fresh authorization check afterward. | Revalidate candidate trust, then recheck authorizer membership/sequence, candidate eligibility/deadline and recovery target immediately before commit. |
| Add/replace existed as prose without complete canonical messages, routes or approval lifecycle. | Specification revision 0.2 defines signed roster/inspection/context, exact lost root, proposal, resulting roster, both final approvals, membership receipt and transaction rules. |
| State/control bindings, sequence contention and response-loss behavior had gaps. | Added origin/audience/scope bindings, competing-sequence behavior, invalidation, historical receipt lookup and committed-but-unacknowledged handling. |
| The v1 authority activates membership at owner approval, before candidate confirmation. | Explicitly prohibited in v2. V1 remains legacy; this patch does not silently migrate it or claim it satisfies the new ceremony. |
| No shared phone-flow surfaces covered the protocol. | Added `PhoneProtocolSnapshot`, typed bound actions, serialized store and `PhoneProtocolView`, with 27 phases and 43 catalog fixtures. |
| Stale UI, malformed receipts and uncertain responses could otherwise produce unsafe controls. | Shared guards reject changed bindings/root descriptors, wrong signers, expired/busy/browser signing, rollback and self-replacement. Unknown mutation outcomes retain the request ID for recovery. |

The survivor policy remains an explicit tradeoff: one accepted owner plus a new
phone can replace another owner. This is independent ownership with survivor
recovery, not two-person control. Distinct attested roots also do not establish
distinct physical devices by themselves.

## Implementation and verification boundaries

- The [v2 specification](PAIRING-ACCOUNT-PROTOCOL.md) and
  [UI contract](PHONE-UI-SURFACES.md) describe required behavior.
- The legacy authority hardening is executable and covered by substitution,
  revoked-trust and concurrent authorization/recovery regression tests.
- `NativePhoneProtocolService` now connects the durable verified v2 client to
  the shared UI. A generic browser cannot supply hardware consent.
- The [component catalog](../artifacts/phone-ui/index.html) uses development-only
  synthetic public records. Its buttons expose callbacks without making requests.
  QR/camera/import use native secure sheets; physical-device acceptance remains
  required.
- Standalone v2 revocation, policy changes, browser-login approval and fresh attestation
  display their requirements and unavailable state; their unimplemented
  wire profiles cannot fall back to v1 mutations.

The subsequent [v2 build](PHONE-V2-BUILD.md) implements strict canonical codecs,
independent vectors, durable authority/client state machines, explicit pairing-first
cutover, native hardware/transport/QR adapters and admission limits. Local tests
use isolated state and test-only attestation roots. Production acceptance still
requires two physical Android devices, including restart, response loss,
replacement, receipt verification and independent sign-in. No live account was
created, migrated or revoked.

The Android documentation requires trusted-server chain and revocation checks;
the new activation-time revalidation preserves that trust boundary. See
[Android key-attestation validation](https://developer.android.com/privacy-and-security/security-key-attestation).

Build and browser evidence for these changes is recorded in
[the catalog evidence index](../artifacts/phone-ui/README.md).
