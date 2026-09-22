# SwiftKey iOS mock passkey core

This package is an isolated **mock**, using CryptoKit software P-256 keys. It does not use the Secure Enclave, hardware attestation, biometrics, or production website credentials. The hardcoded RP allowlist is `swiftkey.mock` and `localhost`; `.production` mode fails before loading state.

The host must show an explicit mock approval screen before calling `approve`. Its opaque token binds the full typed request, expires after 60 seconds, and is consumed once. UP/UV flags represent **simulated** user presence and verification in this harness. Actual ES256 signatures, COSE keys, authenticator data, and `fmt: none` attestation interoperate with a WebAuthn relying party. BE/BS are false, signCount is honestly zero, and no unsupported extensions are claimed.

`MockPasskeyState` is a Codable **test-only private-key container** for isolated app-group persistence. Never log or publish its JSON. The app and extension must hold the same cross-process lock while loading, executing an operation, and atomically saving state. A fresh engine loses unconsumed approval tokens; accepted request IDs remain in the persisted journal. The journal has a 4096-entry bound and fails when full rather than discarding replay protection. Deleting a credential retains that journal.

The mock reuses its random credential and key for the same RP/user handle across launches, regardless of SwiftKey's separate four-hour identity epochs. Requests with multiple discoverable matches must select a credential. Exclusions, wrong RP/handle/allow-list bindings, changed approved requests, expired approvals, cancellation, and replay fail explicitly.

Apple's supplied client-data hash is signed exactly as `authenticatorData || clientDataHash`. Responses expose the binary fields needed by AuthenticationServices. `webAuthnJSON(clientDataJSON:)` can export a browser response for independent RP verification; nonempty client-data bytes must match the approved hash. An omitted value produces the empty hash-only placeholder, never invented browser data.

Run host tests with Xcode's Swift (Swift tools 6.0, macOS 13 / iOS 17 deployment minimums):

```sh
xcrun swift test --package-path SwiftKeyPasskeys
SWIFTKEY_IOS_MOCK_FIXTURE=/tmp/swiftkey-ios-mock-engine-fixture.json \
  xcrun swift test --package-path SwiftKeyPasskeys --filter MockPasskeyTests.testPublicInteropFixtureFromActualMockEngine
```

The exported fixture contains only public registration/assertion data and mock RP challenges. The test suite independently decodes CBOR and verifies signatures through the Security framework, and exercises persistent replay protection and stored-key tamper rejection. Building this package does not establish a signed iOS provider entitlement or a real system passkey ceremony; those are separate app/extension integration checks.
