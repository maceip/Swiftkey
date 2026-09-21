#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd "$script_dir/.." && pwd)"
source "$script_dir/androidswiftui-env.sh"

case "${1:-}" in
  test)
    "$SWIFTKEY_SWIFT" test --package-path "$workspace_dir/SwiftKeyCore"
    "$SWIFTKEY_SWIFT" test --package-path "$workspace_dir/SwiftKeyClient"
    "$SWIFTKEY_SWIFT" test --package-path "$workspace_dir/SwiftKeyApplication"
    "$SWIFTKEY_SWIFT" test --package-path "$workspace_dir/SwiftKeyUI"
    "$SWIFTKEY_SWIFT" test --package-path "$workspace_dir/SwiftKeyServer"
    ;;
  server)
    state_dir="$workspace_dir/SwiftKeyServer/.state"
    mkdir -p "$state_dir"
    chmod 700 "$state_dir"
    token_file="$state_dir/bootstrap-token"
    if [[ ! -f "$token_file" ]]; then
      (umask 077; openssl rand -hex 32 > "$token_file")
    fi
    chmod 600 "$token_file"
    admin_file="$state_dir/admin-token"
    if [[ ! -f "$admin_file" ]]; then
      (umask 077; openssl rand -hex 32 > "$admin_file")
    fi
    chmod 600 "$admin_file"
    cd "$workspace_dir/SwiftKeyServer"
    exec "$SWIFTKEY_SWIFT" run swiftkey-server --config config/device.json --bootstrap-token-file "$token_file" --admin-token-file "$admin_file"
    ;;
  status|ledger)
    # Only public registry/ledger values reach stdout. Admin credentials stay
    # inside the local process and Authorization header, never command arguments.
    python3 - "$workspace_dir" "$1" <<'PY'
import json, sys, urllib.request
from pathlib import Path
root = Path(sys.argv[1]) / 'SwiftKeyServer'
config = json.loads((root / 'config/device.json').read_text())
token = (root / '.state/admin-token').read_text().strip()
url = f"http://{config['host']}:{config['port']}/v1/admin/{sys.argv[2]}"
request = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + token})
with urllib.request.urlopen(request, timeout=10) as response:
    print(json.dumps(json.load(response), indent=2))
PY
    ;;
  configure-android)
    [[ $# -eq 2 && -f "$2" ]] || {
      echo 'Usage: scripts/swiftkey-protocol.sh configure-android /private/enrollment-bundle.json' >&2
      echo 'Export an enrollment bundle for the intended account from the website.' >&2
      exit 2
    }
    bundle_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    serial="${ANDROID_SERIAL:-$(adb -d get-serialno)}"
    [[ -n "$serial" && "$serial" != unknown ]] || { echo 'Connect one authorized Android device or set ANDROID_SERIAL.' >&2; exit 1; }
    # The Swift operator validates expiry, the independent authority pin, and
    # expectedAccountID before touching the device. It refuses existing state.
    exec "$SWIFTKEY_SWIFT" run --package-path "$workspace_dir/SwiftKeyServer" swiftkey-operator \
      provision-android --bundle-file "$bundle_file" \
      --pin-file "$workspace_dir/SwiftKeyServer/.state/server-public-key.txt" --serial "$serial"
    ;;
  *)
    echo 'Usage: scripts/swiftkey-protocol.sh {test|server|status|ledger|configure-android}' >&2
    exit 2
    ;;
esac
