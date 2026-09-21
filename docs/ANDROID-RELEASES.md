# Automatic Android APK releases

Every branch push runs [Android APK Release](../.github/workflows/android-apk-release.yml).
There are no path filters: documentation-only pushes build too. Generated tags do
not start another build. A successful run publishes a regular GitHub Release
with the installable APK, `SHA256SUMS`, and `build.json` attached. Releases appear
in the repository's Releases list; the highest published version is marked Latest.

The workflow uses the Java/Android setup pattern from
[Triplex](https://github.com/maceip/triplex/blob/main/.github/workflows/ci.yml)
and the every-push APK publication pattern from
[Cursor](https://github.com/maceip/cursor/blob/main/.github/workflows/debug-apk-release.yml).
It also builds Swift and all required ARM64 native libraries: this is a complete
APK, not Triplex's native-skipped unit-test configuration.

## Versioning

For workflow run number `N`:

| Field | Value |
| --- | --- |
| Release tag and title version | `v1.0.N` |
| Android `versionName` | `1.0.N` |
| Android `versionCode` | `1000 + N` |
| APK filename | `SwiftKey-v1.0.N-arm64.apk` |

The counter increases for each new run without a version-bump commit or push
loop. Failed runs can leave gaps. Re-running an existing run retains its version;
a complete published release is verified and preserved, not replaced. Tags point
to the exact built commit and are never moved to a different commit.
Each build attempt uploads a separate Actions artifact. Publication consumes its
exact artifact ID, so both a full rerun and a publication-only retry work.

Builds run independently. Publication uses GitHub's queued concurrency mode so a
waiting release is not replaced by a later push. An older build that finishes
late still gets its release but cannot demote a newer version from Latest.

## Signing and payload checks

These are development/debug APKs, matching the currently tested Android build.
They are signed with the same development certificate as the existing installed
SwiftKey app, rather than a different generated key on every fresh runner.
The private signing keystore is stored only in the repository's encrypted Actions
secret and restored only for the build; it is never committed, cached, or uploaded
as an artifact. It is removed from the runner after the build.

Repository configuration:

- Actions secret: `ANDROID_DEBUG_KEYSTORE_BASE64`, containing the existing Android
  debug keystore encoded as base64. This keystore uses the standard
  `androiddebugkey` alias and Android development-keystore password.
- Actions variable: `ANDROID_SIGNING_CERT_SHA256`, the expected public signing
  certificate fingerprint. The restored keystore and final APK must both match.

The build checks Swift application/core tests, Android popup tests, full Cupertino
vendor hashes, and release-publisher regressions. Packaging independently reads
the APK manifest, verifies its Android signature and version, requires ARM64 Swift
runtime libraries, and rejects bundled test runtimes. `build.json` records the
commit, run, version, variant, ABI, APK SHA-256, and public certificate fingerprint.

The release job receives no private signing keystore. It verifies the packaged
checksums, creates a draft, attaches all three assets, then publishes it. A failed
upload can be retried from its draft without exposing a half-complete release.
Existing tags with a different source commit fail instead of being overwritten.

## Build environment and operations

See [pinned toolchain setup](ci-toolchain.md) for Swift 6.3.2, JDK 21, API 35 and
NDK 27.3.13750724 on the ARM64 macOS runner. The build calls the same
`scripts/androidswiftui.sh android-build` wrapper used locally.

The workflow can also be launched with **Run workflow** in GitHub Actions. Use
**Re-run failed jobs** to resume a failed publication with the existing version.
The workflow has a read-only build token and grants `contents: write` only to its
release publication job.

GitHub imposes an additional token restriction when publishing a branch commit
whose workflow files differ from the default branch. Its built-in Actions token
cannot publish that commit; the job fails explicitly. Merge workflow changes to
`main` before releasing them. See GitHub's
[release creation permissions](https://docs.github.com/en/rest/releases/releases#create-a-release).

GitHub's [queued concurrency documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
defines `queue: max`. Actionlint 1.7.12 does not yet recognize that property;
other workflow checks can be run with this one known syntax diagnostic excluded:

```sh
actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/android-apk-release.yml
python3 -m unittest discover -s scripts/ci -p 'test_*.py' -v
```
