#!/usr/bin/env bash
set -euo pipefail

# Stop on configuration/build errors instead of continuing with a missing
# build.ninja or trying to launch a nonexistent executable.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Standalone shares GUI's pinned CONFIG, including when MAP is embedded.
# Repair that checkout only if missing; never initialize MAP's second copy.
if [[ ! -f AOWIS-SERVER-GUI/external/AOWIS-CONFIG/CMakeLists.txt ]]; then
    (cd AOWIS-SERVER-GUI && bash ./git_submodule_init.sh --config)
fi

cmake -S . -B build-linux -G Ninja -DCMAKE_COLOR_DIAGNOSTICS=ON
# Build only the Controller executable and its transitive dependencies.
# A bare cmake --build would also build unrelated ALL targets, including tests.
cmake --build build-linux --target aowis-server-gui --parallel

./build-linux/AOWIS-SERVER-GUI/aowis-server-gui
