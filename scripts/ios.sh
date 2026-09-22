#!/usr/bin/env bash
set -euo pipefail

# Native SwiftKey mock app + real credential-provider extension entry points.
# Never changes the user's global Xcode/toolchain selection or existing simulator data.
action="${1:-run}"
case "$action" in
    project|build|run|test|device-build) ;;
    *) printf 'Usage: scripts/ios.sh [project|build|run|test|device-build]\n' >&2; exit 2 ;;
esac
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export TOOLCHAINS=com.apple.dt.toolchain.Xcode
unset SWIFT_EXEC SDKROOT
python3 "$repo_dir/scripts/ios/generate-project.py"
[[ "$action" != project ]] || exit 0

derived_dir="${SWIFTKEY_IOS_DERIVED_DATA:-$repo_dir/iOS/DerivedData}"
logs_dir="$derived_dir/Logs/SwiftKey"
mkdir -p "$logs_dir"
build_args=(-project "$repo_dir/iOS/SwiftKey.xcodeproj" -scheme SwiftKeyMock -derivedDataPath "$derived_dir")
if [[ "$action" == device-build ]]; then
    xcodebuild "${build_args[@]}" -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build > "$logs_dir/device-build.log" 2>&1 || {
        tail -90 "$logs_dir/device-build.log" >&2; exit 1;
    }
    printf 'Unsigned iPhone build (mock backend disabled): %s/Build/Products/Release-iphoneos/SwiftKeyMock.app\n' "$derived_dir"
    exit 0
fi

simulator_id="${SIMULATOR_UDID:-$(xcrun simctl list devices available -j | python3 -c '
import json,sys
items=[d for runtime,group in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in group if d["name"] == "SwiftKey Passkeys Mock"]
print(items[0]["udid"] if items else "")
')}"
if [[ -z "$simulator_id" ]]; then
    runtime_id="$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
items=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["name"].startswith("iOS ") and int(r["version"].split(".")[0]) >= 17]
if not items: sys.exit("Install an iOS 17 or newer simulator runtime in Xcode first.")
print(sorted(items,key=lambda r:tuple(map(int,r["version"].split("."))))[-1]["identifier"])
')"
    device_type="$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
runtime=next(r for r in json.load(sys.stdin)["runtimes"] if r["identifier"] == sys.argv[1])
items=[d for d in runtime["supportedDeviceTypes"] if d["name"].startswith("iPhone ") and "Pro" in d["name"]]
if not items: sys.exit("No supported iPhone Pro simulator type was found for this runtime.")
print(items[0]["identifier"])
' "$runtime_id")"
    simulator_id="$(xcrun simctl create 'SwiftKey Passkeys Mock' "$device_type" "$runtime_id")"
fi
printf 'SwiftKey simulator: %s\n' "$simulator_id"
# Xcode embeds simulated app-group/provider entitlements in the Mach-O executable;
# simulator ad-hoc signing needs no account. Physical deployment needs a profile/team.
build_args+=(-configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)
if [[ "$action" == test ]]; then
    result_path="$logs_dir/UITests-$(date +%Y%m%d-%H%M%S).xcresult"
    xcodebuild "${build_args[@]}" -parallel-testing-enabled NO -resultBundlePath "$result_path" test > "$logs_dir/test.log" 2>&1 || {
        tail -100 "$logs_dir/test.log" >&2; exit 1;
    }
    printf 'iOS tests passed: %s\n' "$result_path"
    exit 0
fi
xcodebuild "${build_args[@]}" build > "$logs_dir/build.log" 2>&1 || {
    tail -90 "$logs_dir/build.log" >&2; exit 1;
}
app_path="$derived_dir/Build/Products/Debug-iphonesimulator/SwiftKeyMock.app"
printf 'Built simulator app + extension: %s\n' "$app_path"
[[ "$action" == run ]] || exit 0
state="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
print(next(d["state"] for group in json.load(sys.stdin)["devices"].values() for d in group if d["udid"] == sys.argv[1]))
' "$simulator_id")"
if [[ "$state" != Booted ]]; then xcrun simctl boot "$simulator_id"; fi
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl launch --terminate-running-process "$simulator_id" com.maceip.swiftkey.mock
if [[ "${SWIFTKEY_IOS_HEADLESS:-0}" != 1 ]]; then open -a Simulator --args -CurrentDeviceUDID "$simulator_id"; fi
printf 'Running SwiftKey Mock. Mock credentials stay separate from Android and authority state.\n'
