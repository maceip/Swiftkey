# Vapor backend migration — 2026-09-20

The backend now uses Vapor 4.122.2 on the pinned Swift 6.3.2 toolchain. Hummingbird
was removed from the package dependency graph and server/test imports. Vapor
provides routing, middleware, HTTP transport and async startup/shutdown. The
existing Swift authority, SQLite transactions, attestation verifier, canonical
protocol records and shared Swift browser sessions remain in place.

## Compatibility

All 37 route registrations remain: public console/time/health, two optional
bundled fonts, twelve v1 protocol routes, six v2 routes and twelve admin routes.
Existing launch commands, configuration files and authority pins remain valid.
This framework migration requires no data migration and did not modify the
normal authority state, install an APK or deploy a public service.

`SwiftKeyHTTP.configure(...)` registers streaming routes so authentication and
request budgets run before application body collection. Exact caps remain:

| Request | Maximum bytes |
| --- | ---: |
| v1 protocol | 2,000,000 |
| v2 protocol | 750,000 |
| Admin account/workspace bodies | 16,384 |
| Browser event batches | 131,072 |

Explicit checks also cover already buffered bodies. Error JSON, strict v2
decoding, raw query validation, security headers and namespace-wide admin
authentication are retained. Duplicate Authorization headers are rejected on
protocol routes as well as admin routes. Default request/error logging middleware
is replaced, low-level loggers cannot emit debug/trace HTTP input, and automatic
request decompression is disabled. Idle sockets close after 30 seconds without
activity. SwiftKey's validated loopback address cannot be overridden by Vapor
command-line flags.

Vapor dispatches a streaming request after its first body chunk or request end.
The auth/budget smoke checks send one byte and withhold the remainder; they verify
rejection before full collection, not before any body byte arrives. The idle
timeout also covers sockets that have not yet produced a complete request header;
it is not a total deadline against a peer that keeps trickling data. HTTP parser
failures below application middleware may close the connection without the
application JSON error envelope.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Final server build and suite | 77 tests passed, including 20 HTTP tests; executable relinked after final changes | [Server log](server-tests.log) |
| Migrated HTTP suite | Existing 16 tests plus 4 transport regressions | [HTTP log](http-tests.log) |
| Browser adapter | Existing JavaScript adapter regression checks passed | [Log](browser-adapter-tests.log) |
| Production executable over real HTTP | Startup, actual bundled assets and HEAD, guarded partial uploads, raw/chunked body limits, v2 preparation, Swift UI session and private logging passed | [Smoke results](executable-smoke.json) |
| Inactive connections | Partial-header socket closed by the configured inactivity timeout | [Smoke results](executable-smoke.json) |
| Graceful lifecycle | SIGTERM and SIGINT exit cleanly; restart retains the exact public pin and ledger sequence/hash | [Smoke results](executable-smoke.json) |
| Dependencies | Vapor 4.122.2 resolved; Swift Crypto remains 4.5.2 | [Resolution log](resolve.log), [lockfile](../../SwiftKeyServer/Package.resolved) |

The production smoke uses freshly generated temporary credentials and an isolated
state directory. It invokes the real executable and fetches official Google
attestation roots/revocation material; it does not inject a verifier or enroll
a physical device. Its temporary private logs and state are removed afterward.
The previous two-phone StrongBox acceptance gap remains.

Reproduce from the workspace root:

```sh
source scripts/androidswiftui-env.sh
"$SWIFTKEY_SWIFT" test --package-path SwiftKeyServer -j 6
node SwiftKeyServer/browser-tests/adapter.test.cjs
python3 SwiftKeyServer/scripts/verify-vapor-server.py
```

Implementation references: [Vapor routing](https://docs.vapor.codes/basics/routing/),
[VaporTesting](https://docs.vapor.codes/advanced/testing/), and the resolved
Vapor source APIs in the package checkout.
