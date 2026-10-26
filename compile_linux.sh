#!/usr/bin/env bash
set -euo pipefail

# Stop on configuration/build errors instead of continuing with a missing
# build.ninja or trying to launch a nonexistent executable.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

cmake -S . -B build-linux -G Ninja -DCMAKE_COLOR_DIAGNOSTICS=ON
cmake --build build-linux --parallel

./build-linux/AOWIS-SERVER-GUI/aowis-server-gui
