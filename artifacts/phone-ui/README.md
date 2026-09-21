# Phone protocol component evidence — 2026-09-20

The catalog renders the actual shared Swift components across 27 protocol phases
and 43 fixture surfaces. The native service, StrongBox bridge, QR sheets, scanner
and transport are now implemented and built. This catalog uses synthetic public
records; its buttons display typed callbacks without sending protocol requests.

## Results

| Check | Result |
| --- | --- |
| Shared application / UI tests | 35 / 26 passed |
| Swift suites in total | 207 passed; see [current build evidence](../phone-v2/README.md) |
| Native phone host | 7 tests passed |
| Android ARM64 library and debug APK | Built, not installed |
| Actual shared view export | 27 phases; 43 fixture surfaces |
| Chrome, 320 px / 140% layout scale | All 43 surfaces rendered without document overflow |
| Browser console | No warnings or errors |
| New callback checks | Explicit retained-root renewal and owner sign-in/epoch retry |

The final browser pass visually inspected pre-admission invitation inspection and
failed admission, and checked all surfaces for overflow. Prior review checks also
covered bound comparison consent, unknown-result recovery, expired/busy/browser
signing gates and exact request bindings. Text fields retain normal internal
horizontal scrolling. The viewport override was reset after verification.

No Android phones were attached. Physical camera permissions, QR transfer,
secure sheets, layout and two-phone StrongBox pairing remain unexercised. The
catalog contains no real QR capability, private key or account.

## Review the screens

```sh
bash scripts/phone-ui-preview.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory artifacts/phone-ui
```

Open `http://127.0.0.1:8765`. The catalog uses the production primitive renderer
against development-only Swift fixtures.

See [build/setup notes](../../docs/PHONE-V2-BUILD.md),
[review findings](../../docs/PHONE-PROTOCOL-REVIEW.md),
[protocol](../../docs/PAIRING-ACCOUNT-PROTOCOL.md) and
[complete UI contract](../../docs/PHONE-UI-SURFACES.md).

Current evidence is indexed in [../phone-v2/README.md](../phone-v2/README.md).
`verification.json` in this directory reflects the final build; older test/build
logs here preserve the earlier review-only checkpoint and are not final counts.
