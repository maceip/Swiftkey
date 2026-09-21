#!/usr/bin/env bash
# Source from Bash to select this checkout's toolchain in the current shell.
# The androidswiftui.sh wrapper sources it only inside its own process.

androidswiftui_environment() {
    local script_dir repo_dir swift_version toolchain toolchain_id java_dir java_version
    local android_dir ndk_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
    repo_dir="$(cd "$script_dir/../AndroidSwiftUI" && pwd)" || return 1

    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'AndroidSwiftUI setup requires macOS.\n' >&2
        return 1
    fi
    if [[ ! -f "$repo_dir/.swift-version" ]]; then
        printf 'Missing Swift version pin: %s/.swift-version\n' "$repo_dir" >&2
        return 1
    fi
    swift_version="${SWIFT_VERSION:-$(cat "$repo_dir/.swift-version")}"
    toolchain="$HOME/Library/Developer/Toolchains/swift-${swift_version}-RELEASE.xctoolchain"
    if [[ ! -x "$toolchain/usr/bin/swift" || ! -f "$toolchain/Info.plist" ]]; then
        printf 'Missing Swift %s release toolchain: %s\n' "$swift_version" "$toolchain" >&2
        printf 'Install the pinned release, or explicitly set SWIFT_VERSION for a host-only experiment.\n' >&2
        return 1
    fi
    toolchain_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw "$toolchain/Info.plist")" || return 1

    java_dir="${JAVA_HOME:-}"
    if [[ -z "$java_dir" ]]; then
        java_dir="$(/usr/libexec/java_home -v 21 2>/dev/null)" || {
            printf 'JDK 21 is required; install it or set JAVA_HOME to an existing JDK 21.\n' >&2
            return 1
        }
    fi
    if [[ ! -x "$java_dir/bin/java" || ! -x "$java_dir/bin/javac" || ! -f "$java_dir/release" ]]; then
        printf 'JAVA_HOME is not a complete JDK: %s\n' "$java_dir" >&2
        return 1
    fi
    java_version="$(sed -n 's/^JAVA_VERSION="\([^"]*\)".*/\1/p' "$java_dir/release")"
    if [[ "$java_version" != 21 && "$java_version" != 21.* ]]; then
        printf 'JDK 21 is required; JAVA_HOME selects Java %s at %s\n' "$java_version" "$java_dir" >&2
        return 1
    fi

    android_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
    if [[ -z "$android_dir" ]]; then
        if [[ -d /opt/homebrew/share/android-commandlinetools ]]; then
            android_dir=/opt/homebrew/share/android-commandlinetools
        else
            android_dir="$HOME/Library/Android/sdk"
        fi
    fi
    if [[ -n "${ANDROID_SDK_ROOT:-}" && "$ANDROID_SDK_ROOT" != "$android_dir" ]]; then
        printf 'ANDROID_HOME and ANDROID_SDK_ROOT disagree; select the same SDK path.\n' >&2
        return 1
    fi
    ndk_dir="${ANDROID_NDK_HOME:-$android_dir/ndk/27.3.13750724}"

    # Commit the environment only after the host prerequisites are valid. Do not
    # change shell options, cwd, Xcode selection, or persistent user settings.
    export ANDROIDSWIFTUI_ROOT="$repo_dir"
    export SWIFT_VERSION="$swift_version"
    export SWIFT_TOOLCHAIN="$toolchain"
    export SWIFTKEY_SWIFT="$toolchain/usr/bin/swift"
    export TOOLCHAINS="$toolchain_id"
    export JAVA_HOME="$java_dir"
    export ANDROID_HOME="$android_dir"
    export ANDROID_NDK_HOME="$ndk_dir"
    export PATH="$toolchain/usr/bin:$java_dir/bin:$android_dir/platform-tools:$PATH"
}

androidswiftui_environment
