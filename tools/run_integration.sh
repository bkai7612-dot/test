#!/usr/bin/env bash
# Runs the integration scenarios: the real CombatController (client) and CombatService (server)
# against a mocked Roblox runtime with a controllable clock. Covers double jump, front/back
# flips, and the staff/seal spell <-> mana-free strike move sets.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/integration/make_bundle.py
"${LUAU:-luau}" build/integration_bundle.luau
