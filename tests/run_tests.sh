#!/usr/bin/env bash
# Offline tests (no game needed): preflight, generated plugin code + crash detector, BeamNG logic.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
python3 tools/preflight.py > /dev/null || { python3 tools/preflight.py; exit 1; }
python3 tools/gen.py > /dev/null
SDK="$ROOT/build/scs_sdk/include"
[ -d "$SDK" ] || { echo "run tools/build.sh first (fetches the SCS SDK)"; exit 1; }
g++ -std=c++17 -Wall -Wextra -I"$SDK" -o build/test_plugin tests/test_plugin.cpp
build/test_plugin > build/messages.jsonl
python3 -c "
import json,sys
for line in open('build/messages.jsonl'):
    m=json.loads(line); print('  json ok:', m['t'], sorted(m))
"
lua5.1 tests/test_beamng.lua
