#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/androidswiftui-env.sh"
workspace_dir="$(cd "$script_dir/.." && pwd)"
mkdir -p "$workspace_dir/artifacts/phone-ui"
"$SWIFTKEY_SWIFT" run --package-path "$workspace_dir/tools/PhoneProtocolPreview" PhoneProtocolPreview "$workspace_dir/artifacts/phone-ui/surfaces.json"
python3 "$workspace_dir/tools/PhoneProtocolPreview/build_catalog.py"
echo 'Preview: python3 -m http.server 8765 --bind 127.0.0.1 --directory artifacts/phone-ui'
