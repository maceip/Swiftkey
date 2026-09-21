#!/usr/bin/env bash
set -euo pipefail

action="${1:-run}"
case "$action" in
    build|run) ;;
    *) printf 'Usage: scripts/ios-simulator.sh [build|run]\n' >&2; exit 2 ;;
esac

workspace_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ios_dir="$workspace_dir/ios-simulator"
source_dir="$workspace_dir/AndroidSwiftUI/Demo/App.swiftpm"
package_dir="$ios_dir/App.swiftpm"
derived_dir="$ios_dir/DerivedData"
bundle_id=com.swiftkey.catalog.demo
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export TOOLCHAINS=com.apple.dt.toolchain.Xcode
unset SWIFT_EXEC SDKROOT

# This directory is generated from the shared demo. Native overrides live
# outside it so every invocation refreshes the common sources from upstream.
mkdir -p "$package_dir/Sources" "$package_dir/Assets.xcassets" "$ios_dir/evidence"
cp "$source_dir/Package.swift" "$package_dir/Package.swift"
rsync -a --delete "$source_dir/Sources/" "$package_dir/Sources/"
rsync -a --delete "$source_dir/Assets.xcassets/" "$package_dir/Assets.xcassets/"
cp "$ios_dir/NativeAdapters.swift" "$ios_dir/MapPlaygrounds.swift" "$package_dir/Sources/"
sed 's/\.toggleStyle(\.checkbox)/.toggleStyle(NativeCheckboxToggleStyle())/' \
    "$source_dir/Sources/ControlStylePlaygrounds.swift" > "$package_dir/Sources/ControlStylePlaygrounds.swift"

simulator_id="${SIMULATOR_UDID:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
matches = [d for runtime, group in devices.items() if "iOS-26-4" in runtime for d in group if d["name"] == "iPhone 17 Pro"]
if not matches:
    sys.exit("No iPhone 17 Pro / iOS 26.4 simulator; set SIMULATOR_UDID to an available device.")
print(matches[0]["udid"])
')}"

printf 'Building native iOS catalog for simulator %s\n' "$simulator_id"
if ! (cd "$package_dir" && xcodebuild -scheme DemoApp \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_dir" \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" CODE_SIGNING_ALLOWED=NO build) \
    > "$ios_dir/evidence/build.log" 2>&1; then
    tail -80 "$ios_dir/evidence/build.log" >&2
    exit 1
fi

app_path="$derived_dir/Build/Products/Debug-iphonesimulator/DemoApp.app"
[[ -d "$app_path" ]] || { printf 'Missing app: %s\n' "$app_path" >&2; exit 1; }
printf 'Built: %s\n' "$app_path"
[[ "$action" == run ]] || exit 0

state="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
target = sys.argv[1]
print(next(d["state"] for group in json.load(sys.stdin)["devices"].values() for d in group if d["udid"] == target))
' "$simulator_id")"
if [[ "$state" != Booted ]]; then
    xcrun simctl boot "$simulator_id"
fi
open -a Simulator --args -CurrentDeviceUDID "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$app_path"
xcrun simctl launch --terminate-running-process "$simulator_id" "$bundle_id" | tee "$ios_dir/evidence/launch.log"
sleep 2
xcrun simctl io "$simulator_id" screenshot "$ios_dir/evidence/catalog.png"
printf 'Screenshot: %s/evidence/catalog.png\n' "$ios_dir"
