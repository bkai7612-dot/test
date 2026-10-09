#!/usr/bin/env bash
# Runs the offline test suite with the standalone Luau CLI.
# Requires `luau` on PATH (https://github.com/luau-lang/luau/releases) or LUAU=/path/to/luau.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/build_test_bundle.py build/test_bundle.luau
"${LUAU:-luau}" build/test_bundle.luau
