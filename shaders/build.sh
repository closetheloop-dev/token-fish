#!/usr/bin/env bash
# Regenerate wave.frag.qsb from wave.frag with a pinned, reviewable qsb command.
#
# Requires Qt Shader Tools (`qsb`, from the qt6-shadertools package). Run from anywhere:
#   ./build.sh
# Inspect the result with:
#   qsb -d wave.frag.qsb
#
# CI runs this in a pinned toolchain and fails if the committed wave.frag.qsb differs from a
# fresh build, so the .qsb is always reproducible from source.
set -euo pipefail
cd "$(dirname "$0")"

QSB="${QSB:-qsb}"
command -v "$QSB" >/dev/null 2>&1 || QSB=/usr/lib/qt6/bin/qsb

# Targets match what the committed artifact ships (verify with: qsb -d wave.frag.qsb):
#   SPIR-V 100, GLSL 100es/120/150/300es, HLSL 50, MSL 12.
"$QSB" --glsl "100es,120,150,300es" --hlsl 50 --msl 12 -o wave.frag.qsb wave.frag
