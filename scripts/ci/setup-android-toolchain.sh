#!/usr/bin/env bash
# Fresh macOS ARM64 CI setup. --check is read-only and never installs or relinks.
set -euo pipefail

die() { printf 'SwiftKey CI: %s\n' "$*" >&2; exit 1; }
ci_mode="${1:---install}"
[[ $# -le 1 && ( "$ci_mode" == --install || "$ci_mode" == --check ) ]] ||
    die 'Usage: bash scripts/ci/setup-android-toolchain.sh [--install|--check]'
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] ||
    die 'Use an ARM64 macOS runner (macos-26), not an Intel runner.'

ci_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ci_swift_version=6.3.2
ci_ndk_version=27.3.13750724
ci_build_tools_version=35.0.0
[[ "$(cat "$ci_root/AndroidSwiftUI/.swift-version")" == "$ci_swift_version" ]] ||
    die 'Swift pin changed: review the CI download URLs/checksums with the new SDK.'
ci_toolchain="$HOME/Library/Developer/Toolchains/swift-$ci_swift_version-RELEASE.xctoolchain"
ci_swift="$ci_toolchain/usr/bin/swift"
ci_sdk_bundle="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-$ci_swift_version-RELEASE_android.artifactbundle"
ci_swift_sdk="$ci_sdk_bundle/swift-android"
ci_download_base="https://download.swift.org/swift-$ci_swift_version-release"
ci_pkg_url="$ci_download_base/xcode/swift-$ci_swift_version-RELEASE/swift-$ci_swift_version-RELEASE-osx.pkg"
ci_sdk_url="$ci_download_base/android-sdk/swift-$ci_swift_version-RELEASE/swift-$ci_swift_version-RELEASE_android.artifactbundle.tar.gz"
# PKG digest is pinned from the Apple-trusted Swift Open Source signed release.
# Android SDK digest is published by swift.org/api/v1/install/releases.json.
ci_pkg_sha256=3dd8da736318b6f0a5d7c01b039dd8511f7994cababf9b10534dce1b19ccdca7
ci_sdk_sha256=939e933549d12d28f2e0bf71019d734d309859e9773c572657ce565a81f85d68

[[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/javac" && -f "$JAVA_HOME/release" ]] ||
    die 'Run actions/setup-java with Temurin 21 first (JAVA_HOME is required).'
ci_java_version="$(sed -n 's/^JAVA_VERSION="\([^"]*\)".*/\1/p' "$JAVA_HOME/release")"
[[ "$ci_java_version" == 21 || "$ci_java_version" == 21.* ]] || die 'JDK 21 is required.'
ci_android_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ci_android_root" ]]; then
    if [[ -d /opt/homebrew/share/android-commandlinetools ]]; then
        ci_android_root=/opt/homebrew/share/android-commandlinetools
    else
        ci_android_root="$HOME/Library/Android/sdk"
    fi
fi
[[ -z "${ANDROID_SDK_ROOT:-}" || "$ANDROID_SDK_ROOT" == "$ci_android_root" ]] ||
    die 'ANDROID_HOME and ANDROID_SDK_ROOT disagree.'
export ANDROID_HOME="$ci_android_root" ANDROID_SDK_ROOT="$ci_android_root"
export ANDROID_NDK_HOME="$ci_android_root/ndk/$ci_ndk_version"
export SWIFT_VERSION="$ci_swift_version"

ci_temp=
cleanup() { [[ -z "$ci_temp" ]] || rm -rf -- "$ci_temp"; }
trap cleanup EXIT

if [[ "$ci_mode" == --install ]]; then
    ci_sdkmanager="$(command -v sdkmanager || true)"
    [[ -n "$ci_sdkmanager" ]] || die 'Run android-actions/setup-android first (sdkmanager is required).'
    # License acceptance is intentional for these CI build dependencies. Ignore
    # only yes(1)'s expected SIGPIPE, while retaining sdkmanager's exit status.
    (set +o pipefail; yes | "$ci_sdkmanager" --sdk_root="$ci_android_root" --licenses >/dev/null)
    "$ci_sdkmanager" --sdk_root="$ci_android_root" --install \
        'platform-tools' 'platforms;android-35' \
        "build-tools;$ci_build_tools_version" "ndk;$ci_ndk_version"

    if [[ ! -e "$ci_toolchain" ]]; then
        ci_temp="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/swiftkey-ci-toolchain.XXXXXX")"
        ci_pkg="$ci_temp/swift.pkg"
        curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
            --retry 3 --connect-timeout 30 --max-time 1200 "$ci_pkg_url" -o "$ci_pkg"
        printf '%s  %s\n' "$ci_pkg_sha256" "$ci_pkg" | shasum -a 256 -c -
        pkgutil --check-signature "$ci_pkg" > "$ci_temp/signature.txt"
        grep -Fq 'Developer ID Installer: Swift Open Source (V9AUD2URP3)' "$ci_temp/signature.txt" ||
            die 'The toolchain package has an unexpected signer.'
        installer -pkg "$ci_pkg" -target CurrentUserHomeDirectory
        # Keep the large archive out of both caches and subsequent build peaks.
        rm -f -- "$ci_pkg"
    fi
fi

[[ -x "$ci_swift" && -f "$ci_toolchain/Info.plist" ]] ||
    die 'The pinned toolchain is missing/incomplete; do not reuse this cache.'
ci_swift_identity="$("$ci_swift" --version)"
[[ "$ci_swift_identity" == *"Swift version $ci_swift_version "* &&
   "$ci_swift_identity" == *"swift-$ci_swift_version-RELEASE"* ]] ||
    die 'The installed compiler does not match the exact release pin.'
export TOOLCHAINS="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$ci_toolchain/Info.plist")"
export PATH="$ci_toolchain/usr/bin:$JAVA_HOME/bin:$ci_android_root/platform-tools:$PATH"

if [[ "$ci_mode" == --install && ! -e "$ci_sdk_bundle" ]]; then
    "$ci_swift" sdk install "$ci_sdk_url" --checksum "$ci_sdk_sha256"
fi
[[ -f "$ci_sdk_bundle/info.json" && -f "$ci_swift_sdk/swift-sdk.json" &&
   -f "$ci_swift_sdk/scripts/setup-android-sdk.sh" &&
   -f "$ci_swift_sdk/swift-resources/usr/lib/swift-aarch64/android/libswiftCore.so" ]] ||
    die 'The pinned Android Swift SDK is missing/incomplete; do not reuse this cache.'
python3 - "$ci_sdk_bundle" "$ci_swift_version" <<'PY'
import json, pathlib, sys
bundle = pathlib.Path(sys.argv[1])
artifact = f"swift-{sys.argv[2]}-RELEASE_android"
assert artifact in json.loads((bundle / "info.json").read_text())["artifacts"], "SDK version mismatch"
assert "aarch64-unknown-linux-android28" in json.loads((bundle / "swift-android/swift-sdk.json").read_text())["targetTriples"], "ARM64/API28 target missing"
PY
[[ -f "$ANDROID_NDK_HOME/source.properties" ]] || die 'The pinned NDK is missing.'
ci_installed_ndk="$(sed -n 's/^Pkg.Revision *= *//p' "$ANDROID_NDK_HOME/source.properties")"
[[ "$ci_installed_ndk" == "$ci_ndk_version" ]] || die 'The NDK revision does not match the pin.'
[[ -f "$ci_android_root/platforms/android-35/android.jar" &&
   -x "$ci_android_root/build-tools/$ci_build_tools_version/aapt" &&
   -x "$ci_android_root/build-tools/$ci_build_tools_version/apksigner" ]] ||
    die 'Android platform 35 and build-tools 35.0.0 are required.'

if [[ "$ci_mode" == --install ]]; then
    # Cached SDKs contain absolute links into the previous runner's NDK. Always
    # recreate them. Unlink the SDK's clang pointer first so upstream ln -sf
    # cannot follow an existing directory symlink and write inside the NDK.
    ci_clang_link="$ci_swift_sdk/swift-resources/usr/lib/swift/clang"
    if [[ -L "$ci_clang_link" ]]; then
        rm -- "$ci_clang_link"
    elif [[ -e "$ci_clang_link" ]]; then
        die 'Expected an SDK clang symlink, not an unmanaged directory.'
    fi
    SWIFT_ANDROID_NDK_LINK=1 bash "$ci_swift_sdk/scripts/setup-android-sdk.sh"
fi

# Reuse the exact environment and path checks used by local builds.
source "$ci_root/scripts/androidswiftui-env.sh"
bash "$ci_root/scripts/androidswiftui.sh" doctor

if [[ "$ci_mode" == --install && -n "${GITHUB_ENV:-}" ]]; then
    # These values are local tool paths, not branch names or other untrusted text.
    for ci_name in SWIFT_VERSION SWIFT_TOOLCHAIN SWIFTKEY_SWIFT TOOLCHAINS JAVA_HOME ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME; do
        ci_value="${!ci_name}"
        [[ "$ci_value" != *$'\n'* && "$ci_value" != *$'\r'* ]] || die 'Invalid newline in tool path.'
        printf '%s=%s\n' "$ci_name" "$ci_value" >> "$GITHUB_ENV"
    done
fi
if [[ "$ci_mode" == --install && -n "${GITHUB_PATH:-}" ]]; then
    printf '%s\n' "$ci_toolchain/usr/bin" "$JAVA_HOME/bin" "$ci_android_root/platform-tools" >> "$GITHUB_PATH"
fi
printf 'SwiftKey CI toolchain %s completed: Swift %s, NDK %s, API 35, ARM64/API 28 target.\n' \
    "$ci_mode" "$ci_swift_version" "$ci_ndk_version"
