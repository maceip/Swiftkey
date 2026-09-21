# SwiftKey design verification — 2026-09-19

The finished frontend is live at `http://127.0.0.1:18088`. Its HTML, CSS, JavaScript
and both self-hosted fonts match the final source byte for byte. The authority
snapshot, ledger head 4, and existing admin credential are unchanged.

Browser verification used an isolated, private SQLite backup on port 18089. Its
preview account and invitation mutations never entered the live authority. The
preview process, temporary credential and private database copy were removed
after testing.

## Browser checks

- Inspected the TypeSafe reference and both the desktop and phone implementations.
- Rendered at 320, 390, 768 and 1280px widths; no horizontal page overflow.
- Checked mobile and desktop navigation/active destination, including the fixed
  header's anchor offset.
- Switched accounts using the mobile native picker and desktop account buttons.
- Copied all 65 bytes of the actual enrolled root public key and compared the
  resulting bytes. Restored the initially empty browser clipboard.
- Inspected complete key wrapping, an expired credential, expandable ledger
  fields and signed checkpoint; long hashes/signatures do not overflow.
- Rejected a 122-byte Unicode account name at the field, then successfully created
  a preview account and replaced its enrollment invitation.
- Confirmed the one-time token receives focus and is visible on mobile; dismissed
  it before screenshots. Tokens were redacted from observation output.
- Stopped the preview authority and confirmed “Connection interrupted,”
  “Unavailable” and “Showing the last loaded snapshot.” Disconnect cleared data.
- No unexpected browser JavaScript warnings/errors before the intentional
  offline test. Reduced-motion styles, visible keyboard focus, input contrast,
  label references and 44px control geometry were reviewed.

## Automated/build checks

- Swift server: **44 tests passed**, including font whitelist, MIME type and CSP.
- Native Swift core: **124 tests passed**.
- Native renderer/JNI: **10 tests passed**, including actual shared-view layout at
  360px and 320px with 140% text scaling; all synthetic fixture bytes remain
  available without ellipsis.
- Android ARM64 library and debug APK build passed; package/version/signing
  certificate remain compatible with the existing authority.
- `node --check` passed for the final JavaScript.

`verification.json` records the final live checks. `live-state-baseline.json`
contains public comparison hashes, not private state. Relevant logs are beside
this file. Native synthetic previews and limitations are in
[SwiftKeyDesign/mobile.md](../../SwiftKeyDesign/mobile.md).

No Android device was attached, so the new APK was not installed and its physical
system bars/hardware screen were not reverified. iOS execution remains postponed.
The UI changes do not complete attestation renewal or external ledger anchoring.
