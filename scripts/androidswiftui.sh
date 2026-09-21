#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/androidswiftui.sh COMMAND

  doctor          Check the selected host and Android build prerequisites
  core-test       Run SwiftUICore's host tests
  desktop-build   Build the live Swift desktop demo library
  desktop-test    Build the library, then run the desktop JVM bridge test
  desktop-run     Build the library, then launch the desktop catalog
  android-build   Cross-compile ARM64/API 28, stage runtimes, and assemble the APK
  android-run     Build, install, and launch on ANDROID_SERIAL or one USB device

Uses AndroidSwiftUI/.swift-version (6.3.2). An explicit SWIFT_VERSION=6.4.0
can select the installed interim host toolchain. Android needs a matching SDK.
JAVA_HOME, ANDROID_HOME, and ANDROID_NDK_HOME may select existing installations.
ANDROID_SERIAL selects the device for android-run when more than one is connected.
Nothing is downloaded or installed by setup; build tools may resolve dependencies.
USAGE
}

die() {
    printf 'AndroidSwiftUI: %s\n' "$*" >&2
    exit 1
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
command_name="$1"
case "$command_name" in
    -h|--help|help) usage; exit 0 ;;
    doctor|core-test|desktop-build|desktop-test|desktop-run|android-build|android-run) ;;
    *) usage >&2; die "Unknown command: $command_name" ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/androidswiftui-env.sh"
repo_dir="$ANDROIDSWIFTUI_ROOT"
android_target=aarch64-unknown-linux-android28

require_gradle() {
    local configured_sdk
    [[ -x "$repo_dir/gradlew" ]] || die "Missing executable Gradle wrapper: $repo_dir/gradlew"
    [[ -f "$repo_dir/gradle/wrapper/gradle-wrapper.jar" ]] || die 'Missing Gradle wrapper JAR.'
    configured_sdk="$(sed -n 's/^sdk\.dir=//p' "$repo_dir/local.properties" 2>/dev/null || true)"
    if [[ -n "$configured_sdk" && ! "$configured_sdk" -ef "$ANDROID_HOME" ]]; then
        die "Gradle local.properties selects $configured_sdk, but ANDROID_HOME selects $ANDROID_HOME. Make those SDK paths agree."
    fi
    [[ -f "$ANDROID_HOME/platforms/android-35/android.jar" ]] ||
        die "Android platform 35 is missing from ANDROID_HOME: $ANDROID_HOME"
}

find_android_runtime() {
    local candidate
    local matches=()
    for candidate in "$HOME/Library/org.swift.swiftpm/swift-sdks"/swift-"$SWIFT_VERSION"-RELEASE*_android.artifactbundle/swift-android; do
        [[ -d "$candidate/swift-resources/usr/lib/swift-aarch64/android" ]] || continue
        matches+=("$candidate")
    done
    [[ ${#matches[@]} -eq 1 ]] ||
        die "Expected one installed Swift $SWIFT_VERSION Android SDK bundle; found ${#matches[@]}. Install the matching SDK with swift sdk install first."
    android_swift_sdk="${matches[0]}"
    android_runtime="$android_swift_sdk/swift-resources/usr/lib/swift-aarch64/android"
    [[ -f "$android_runtime/libswiftCore.so" ]] || die "Swift runtime is incomplete: $android_runtime"
}

find_ndk_runtime() {
    local candidate
    local matches=()
    [[ -f "$ANDROID_NDK_HOME/source.properties" ]] || die "Incomplete Android NDK: $ANDROID_NDK_HOME"
    for candidate in "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/darwin-*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so; do
        [[ -f "$candidate" ]] && matches+=("$candidate")
    done
    [[ ${#matches[@]} -eq 1 ]] ||
        die "Expected one ARM64 libc++_shared.so in $ANDROID_NDK_HOME; found ${#matches[@]}. Use a complete NDK installation."
    ndk_runtime="${matches[0]}"
}

validate_ndk_configuration() {
    local sdk_libc="$android_swift_sdk/ndk-sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
    [[ -f "$android_swift_sdk/ndk-sysroot/usr/include/stdlib.h" && "$sdk_libc" -ef "$ndk_runtime" ]] ||
        die "Swift Android SDK sysroot is missing or selects a different NDK. Run ANDROID_NDK_HOME=\"$ANDROID_NDK_HOME\" bash \"$android_swift_sdk/scripts/setup-android-sdk.sh\"."
}

desktop_build() {
    "$SWIFTKEY_SWIFT" build --package-path "$repo_dir" --product SwiftUIDesktopDemo --disable-sandbox
    desktop_bin_dir="$("$SWIFTKEY_SWIFT" build --package-path "$repo_dir" --show-bin-path)"
    desktop_library="$desktop_bin_dir/libSwiftUIDesktopDemo.dylib"
    [[ -f "$desktop_library" ]] || die "Desktop build did not produce $desktop_library"
    [[ -f "$desktop_bin_dir/libSwiftJava.dylib" ]] || die "Desktop bridge runtime is missing: $desktop_bin_dir/libSwiftJava.dylib"
}

gradle() {
    (cd "$repo_dir" && ./gradlew "$@")
}

is_test_runtime() {
    case "${1##*/}" in
        libXCTest*|libTesting*|lib_Testing*) return 0 ;;
        *) return 1 ;;
    esac
}

android_apk() {
    command -v python3 >/dev/null || die 'python3 is required to read Android APK output metadata.'
    python3 - "$repo_dir/Demo/app/build/outputs/apk/debug/output-metadata.json" <<'PY'
import json
import sys
from pathlib import Path

metadata = Path(sys.argv[1])
try:
    elements = json.loads(metadata.read_text())["elements"]
    if len(elements) != 1:
        raise ValueError(f"expected one debug APK, found {len(elements)}")
    filename = elements[0]["outputFile"]
    if not isinstance(filename, str) or Path(filename).name != filename or not filename.endswith(".apk"):
        raise ValueError("invalid APK output filename")
    apk = metadata.parent / filename
    if not apk.is_file():
        raise ValueError(f"APK is missing: {apk}")
except (OSError, ValueError, KeyError, TypeError) as error:
    sys.exit(f"AndroidSwiftUI: Cannot read APK output metadata {metadata}: {error}")
print(apk)
PY
}

android_build() {
    require_gradle
    find_android_runtime
    find_ndk_runtime
    validate_ndk_configuration
    local package_dir="$repo_dir/Demo/swift"
    local bin_dir library jni_dir
    "$SWIFTKEY_SWIFT" build --package-path "$package_dir" --swift-sdk "$android_target" --product SwiftAndroidApp --disable-sandbox
    bin_dir="$("$SWIFTKEY_SWIFT" build --package-path "$package_dir" --swift-sdk "$android_target" --show-bin-path)"
    [[ -f "$bin_dir/libSwiftAndroidApp.so" ]] || die "Android app library is missing: $bin_dir/libSwiftAndroidApp.so"
    [[ -f "$bin_dir/libSwiftJava.so" ]] || die "Android bridge library is missing: $bin_dir/libSwiftJava.so"

    jni_dir="$repo_dir/Demo/app/src/main/jniLibs/arm64-v8a"
    mkdir -p "$jni_dir"
    staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/androidswiftui-jni.XXXXXX")"
    # This function runs in a subshell so the staging variable and cleanup trap
    # cannot affect callers. Keep staging_dir in that shell until its EXIT trap.
    trap 'rm -rf -- "$staging_dir"' EXIT
    for library in "$android_runtime"/*.so "$bin_dir"/*.so; do
        [[ -f "$library" ]] || continue
        is_test_runtime "$library" && continue
        cp "$library" "$staging_dir/"
    done
    cp "$ndk_runtime" "$staging_dir/libc++_shared.so"
    # jniLibs is generated and ignored by Git. Replace only its .so outputs, so
    # libraries from a prior SDK (including test runtimes) cannot leak into APKs.
    rm -f "$jni_dir"/*.so
    cp "$staging_dir"/*.so "$jni_dir/"
    gradle :demo-app:assembleDebug
    local apk
    apk="$(android_apk)"
    printf 'APK: %s\n' "$apk"
}

android_run() {
    (android_build)
    command -v adb >/dev/null || die "adb is missing; install Android platform-tools in $ANDROID_HOME."
    local serial device_state apk launch_result app_pid
    serial="${ANDROID_SERIAL:-}"
    if [[ -z "$serial" ]]; then
        serial="$(adb -d get-serialno 2>&1)" ||
            die "Expected one connected physical USB device. Connect and authorize it, or set ANDROID_SERIAL to select a device. adb: $serial"
    fi
    [[ -n "$serial" && "$serial" != unknown ]] ||
        die 'No unique connected physical device found; connect and authorize it or set ANDROID_SERIAL.'
    device_state="$(adb -s "$serial" get-state 2>&1)" ||
        die "Device $serial is unavailable or unauthorized. adb: $device_state"
    [[ "$device_state" == device ]] || die "Device $serial is not ready: $device_state"
    apk="$(android_apk)"
    printf 'Device: %s\n' "$serial"
    adb -s "$serial" install -r "$apk"
    launch_result="$(adb -s "$serial" shell am start -W -n com.pureswift.swiftandroidui/com.pureswift.swiftandroid.MainActivity 2>&1)" ||
        die "Could not launch AndroidSwiftUI on $serial: $launch_result"
    printf '%s\n' "$launch_result"
    [[ "$launch_result" == *'Status: ok'* ]] || die "Android activity launch did not succeed on $serial."
    app_pid="$(adb -s "$serial" shell pidof com.pureswift.swiftandroidui 2>/dev/null | tr -d '\r')" ||
        die "AndroidSwiftUI has no running process on $serial after launch."
    [[ "$app_pid" =~ ^[0-9]+([[:space:]]+[0-9]+)*$ ]] ||
        die "AndroidSwiftUI has no valid process ID on $serial after launch."
    printf 'AndroidSwiftUI PID: %s\n' "$app_pid"
}

case "$command_name" in
    doctor)
        printf 'Swift pin/selection: %s\nSwift executable: %s\nToolchain ID: %s\nJDK: %s\nAndroid SDK: %s\nAndroid NDK: %s\n' \
            "$SWIFT_VERSION" "$SWIFTKEY_SWIFT" "$TOOLCHAINS" "$JAVA_HOME" "$ANDROID_HOME" "$ANDROID_NDK_HOME"
        "$SWIFTKEY_SWIFT" --version
        "$JAVA_HOME/bin/java" -version
        status=0
        (require_gradle) || status=1
        (find_android_runtime; find_ndk_runtime; validate_ndk_configuration
            printf 'Swift Android runtime: %s\nNDK C++ runtime: %s\n' "$android_runtime" "$ndk_runtime") || status=1
        exit "$status"
        ;;
    core-test)
        "$SWIFTKEY_SWIFT" test --package-path "$repo_dir/SwiftUICore"
        ;;
    desktop-build)
        desktop_build
        printf 'Desktop library: %s\n' "$desktop_library"
        ;;
    desktop-test)
        require_gradle
        desktop_build
        gradle "-Pswiftui.library=$desktop_library" :demo-desktop:jvmTest
        ;;
    desktop-run)
        require_gradle
        desktop_build
        gradle "-Pswiftui.library=$desktop_library" :demo-desktop:run
        ;;
    android-build)
        (android_build)
        ;;
    android-run)
        android_run
        ;;
esac
