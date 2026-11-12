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

# The WireGuard engine's Go modules are fetched on the host (normal host
# network/DNS, usually already cached by Linux builds) and the host module
# cache is mounted; the container builds with GOPROXY=off and needs no network.
NETWORK_BRIDGE="$PROJECT_ROOT/AOWIS-SERVER-GUI/external/AOWIS-NETWORK/bridge"
if ! command -v go >/dev/null 2>&1; then
    echo "Go is required on the host to fetch the WireGuard engine's modules." >&2
    exit 1
fi
if [[ ! -f "$NETWORK_BRIDGE/go.mod" ]]; then
    echo "Missing $NETWORK_BRIDGE/go.mod; run ./git_submodule_update.sh" >&2
    exit 1
fi
echo "=== Fetching WireGuard engine Go modules on the host ==="
(cd "$NETWORK_BRIDGE" && GOWORK=off GOFLAGS=-mod=readonly go mod download)
HOST_GOMODCACHE="$(go env GOMODCACHE)"

docker run --rm \
    -e AOWIS_WINDOWS_BUILD_JOBS="${AOWIS_WINDOWS_BUILD_JOBS:-}" \
    -e GOMODCACHE=/home/user/go-mod \
    -e GOPROXY=off \
    -e GOFLAGS=-mod=readonly \
    -v "$PROJECT_ROOT":/project \
    -v "$HOST_GOMODCACHE":/home/user/go-mod \
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
