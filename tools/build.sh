#!/usr/bin/env bash
# Build Shadow Rig: preflight -> generate -> compile ATS plugin -> package both Melty components.
# Usage: tools/build.sh [version]     (needs: python3, x86_64-w64-mingw32-g++, zip, curl, unzip)
set -euo pipefail
VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"; DIST="$ROOT/dist"
SDK_URL="https://download.eurotrucksimulator2.com/scs_sdk_1_15.zip"

python3 "$ROOT/tools/preflight.py" > "$BUILD.preflight.txt" || { cat "$BUILD.preflight.txt"; echo "preflight failed"; exit 1; }
head -3 "$BUILD.preflight.txt"; rm -f "$BUILD.preflight.txt"
python3 "$ROOT/tools/gen.py"

mkdir -p "$BUILD" "$DIST"
if [ ! -d "$BUILD/scs_sdk/include" ]; then
  curl -sSfL -o "$BUILD/scs_sdk.zip" "$SDK_URL"
  unzip -q -o "$BUILD/scs_sdk.zip" -d "$BUILD/scs_sdk"
fi

x86_64-w64-mingw32-g++ -std=c++17 -O2 -shared -Wall -Wextra \
  -I"$BUILD/scs_sdk/include" \
  -o "$BUILD/shadow_rig.dll" "$ROOT/ats_plugin/src/shadow_rig.cpp" "$ROOT/ats_plugin/src/shadow_rig.def" \
  -static -static-libgcc -static-libstdc++ -lws2_32

# Component 1: ATS plugin -> {game}/bin/win_x64/plugins
rm -rf "$BUILD/pkg_ats" && mkdir -p "$BUILD/pkg_ats"
cp "$BUILD/shadow_rig.dll" "$BUILD/pkg_ats/"
cp "$BUILD/scs_sdk/sdk_license.txt" "$BUILD/pkg_ats/shadow_rig_SCS_SDK_LICENSE.txt"
(cd "$BUILD/pkg_ats" && rm -f "$DIST/ShadowRig-ATS-$VERSION.zip" && zip -q -X -r "$DIST/ShadowRig-ATS-$VERSION.zip" .)

# Component 2: BeamNG mod (unpacked) -> BeamNG mods/unpacked/shadowrig
rm -f "$DIST/ShadowRig-BeamNG-$VERSION.zip"
(cd "$ROOT/beamng_mod" && zip -q -X -r "$DIST/ShadowRig-BeamNG-$VERSION.zip" lua scripts)

ls -l "$DIST"
sha256sum "$DIST"/*.zip
