# SwiftKey web authority verification — 2026-09-19

The Swift/Hummingbird server is running locally at `http://127.0.0.1:18088`.

- `server-tests.log`: all 43 server tests passed under Swift 6.3.2, including account isolation, invitation expiry/replacement races, epoch rotation, replay, revocation/recovery, and SQLite integrity/restart checks.
- `migration-baseline.json`: public pre-migration identities and hashes/counts used to compare retained state.
- `live-migration-proof.json`: live admin API responses and verified migration/restart checks. The server signing key, Android root, current credential, six replay records, and original legacy JSON survived migration and both restarts.
- `ledger-verification.json`: all four live event hashes independently recomputed in Python; the signed checkpoint independently verified with OpenSSL against the preserved authority public key.
- `server.log`: build and local service startup output.

Browser verification exercised authentication, the imported Android root and epoch credential, credential/checkpoint expansion, account creation, replacement invitation, token dismissal, account selection, and disconnect. The console had no JavaScript warnings/errors. The resulting `Development account` remains pending with no devices. The temporary admin credential used for browser testing was replaced; the final server rejects it.

These artifacts contain public protocol data and verification results, not private signing keys or enrollment/admin bearers. The final admin credential is stored privately in `SwiftKeyServer/.state/admin-token`.

The Android device was disconnected during this server extension, so this is not a new physical-device roundtrip or four-hour wall-clock rollover proof. iOS remains postponed. Attestation evidence renewal and external ledger checkpoint anchoring remain separate work; a complete database rollback cannot be ruled out by a checkpoint retained only beside that database.
