#!/usr/bin/env bash
set -euo pipefail
# Compatibility entry: the product mock app replaces the historical renderer catalog.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios.sh" "${1:-run}"
