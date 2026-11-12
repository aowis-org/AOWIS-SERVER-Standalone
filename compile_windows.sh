#!/bin/bash
set -euo pipefail

echo "=== Starting Windows build using Docker ==="
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Ensure the nested MAP dependency is pinned and initialized before Docker
# mounts the Standalone checkout. No Git operation on an already-populated tree.
if [[ ! -f "$PROJECT_ROOT/AOWIS-SERVER-MAP/external/AOWIS-CONFIG/CMakeLists.txt" ]]; then
    "$PROJECT_ROOT/tools/init_map_config_submodule.sh"
fi

SCRIPT_REL="tools/qt-windows/build_windows_inside_container.sh"
WINDOWS_IMAGE="aowis-qt-windows:6.12.0-mingw15"

if ! docker image inspect "$WINDOWS_IMAGE" >/dev/null 2>&1; then
    echo "Missing Windows toolchain image: $WINDOWS_IMAGE" >&2
    echo "Build it first: ./tools/qt-windows/docker_build.sh" >&2
    exit 1
fi

# Host networking: Docker's bridge DNS times out on this LAN (Go module
# downloads); the image build uses --network=host for the same reason.
docker run --rm \
    --network host \
    -e AOWIS_WINDOWS_BUILD_JOBS="${AOWIS_WINDOWS_BUILD_JOBS:-}" \
    -v "$PROJECT_ROOT":/project \
    -v aowis-windows-go-cache:/home/user/.cache/aowis-go \
    -w /project \
    "$WINDOWS_IMAGE" \
    /bin/bash "/project/$SCRIPT_REL"

echo "=== Creating cleaned up Windows distribution directory build-windows-dist ==="
DIST_NAME="aowis-controller-windows-x64"
DIST_ROOT="$PROJECT_ROOT/build-windows-dist"
DIST_DIR="$DIST_ROOT/$DIST_NAME"
ZIP_FILE="$DIST_ROOT/$DIST_NAME.zip"
rm -rf "$DIST_ROOT"
mkdir -p "$DIST_DIR"
cp -r "$PROJECT_ROOT"/build-windows/deploy/* "$DIST_DIR"/

echo "=== Creating ZIP archive ==="
(
    cd "$DIST_ROOT"
    zip -r "$ZIP_FILE" "$DIST_NAME"
)

echo "=== Windows build finished ==="
echo "Distribution folder: $DIST_DIR"
echo "ZIP archive: $ZIP_FILE"
