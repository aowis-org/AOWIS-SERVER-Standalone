#!/bin/bash
set -e

echo "=== Starting macOS build using Docker ==="

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_REL="tools/qt-macos/build_macos_inside_container.sh"

DIST_NAME="aowis-controller-macos"
DIST_ROOT="$PROJECT_ROOT/build-macos-dist"
DIST_DIR="$DIST_ROOT/$DIST_NAME"
ZIP_FILE="$DIST_ROOT/$DIST_NAME.zip"

docker run --rm \
    -v "$PROJECT_ROOT":/project \
    -w /project \
    aowis-qt-macos:6.7 \
    /bin/bash "/project/$SCRIPT_REL"

echo "=== Creating cleaned up macOS distribution directory build-macos-dist ==="

rm -rf "$DIST_ROOT"
mkdir -p "$DIST_DIR"

cp -R "$PROJECT_ROOT"/build-macos/deploy/* "$DIST_DIR"/

echo "=== Creating ZIP archive ==="

rm -f "$ZIP_FILE"

(
    cd "$DIST_ROOT"
    zip -r "$ZIP_FILE" "$DIST_NAME"
)

echo "=== macOS build finished ==="
echo "Distribution folder: $DIST_DIR"
echo "ZIP archive: $ZIP_FILE"
