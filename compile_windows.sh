#!/bin/bash
set -euo pipefail

echo "=== Starting Windows build using Docker ==="
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_REL="tools/qt-windows/build_windows_inside_container.sh"
WINDOWS_IMAGE="aowis-qt-windows:6.12.0-mingw15"

if ! docker image inspect "$WINDOWS_IMAGE" >/dev/null 2>&1; then
    echo "Missing Windows toolchain image: $WINDOWS_IMAGE" >&2
    echo "Build it first: ./tools/qt-windows/docker_build.sh" >&2
    exit 1
fi

docker run --rm \
    -e AOWIS_WINDOWS_BUILD_JOBS="${AOWIS_WINDOWS_BUILD_JOBS:-}" \
    -v "$PROJECT_ROOT":/project \
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
