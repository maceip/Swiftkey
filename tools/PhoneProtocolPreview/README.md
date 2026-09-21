# Phone protocol component catalog

This development-only executable evaluates the actual shared `PhoneProtocolView`
for each phase and representative failure/approval variant. Synthetic public
records live here, outside the production packages. It has no authority, private
keys, credentials, QR capability, or native signing adapter.

From the workspace root:

```sh
bash scripts/phone-ui-preview.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory artifacts/phone-ui
```

Open `http://127.0.0.1:8765`. The catalog uses the existing website's primitive
renderer and styles. Its buttons display the typed callback produced by the
shared view; they do not simulate successful enrollment. Width and enlarged-layout
controls support manual accessibility inspection. Regenerate after Swift view or
browser renderer changes, then reload the browser.

The QR/camera/manual-entry controls exercise host-effect dispatch only. Their
secure native surfaces need a real platform adapter and transient capability;
the catalog deliberately contains no scannable invitation.
