#!/bin/bash
set -euo pipefail

WINDOWS_DEPS_PREFIX="C:/aowis-deps"
WINDOWS_DEPS_ROOT="/home/user/.wine/drive_c/aowis-deps"
WINDOWS_DEPS_BIN="$WINDOWS_DEPS_ROOT/bin"
WINDOWS_DEPS_INCLUDE="$WINDOWS_DEPS_ROOT/include"
MAX_DEFAULT_WINDOWS_BUILD_JOBS=8
WINE_RETRY_BUILD_JOBS=2

echo "=== Building AOWIS for Windows x64 using Qt/MinGW ==="

cd /project

rm -rf build-windows
mkdir -p build-windows

if [ ! -f "$WINDOWS_DEPS_INCLUDE/tiffio.h" ]; then
    echo "ERROR: Windows libtiff headers are missing from the Docker image:"
    echo "$WINDOWS_DEPS_INCLUDE/tiffio.h"
    echo
    echo "Rebuild the Windows build image from the repository root:"
    echo "  ./tools/qt-windows/docker_build.sh"
    exit 1
fi

TIFF_DLL="$(find "$WINDOWS_DEPS_BIN" -maxdepth 1 -type f -iname '*tiff*.dll' -print -quit)"
if [ -z "$TIFF_DLL" ]; then
    echo "ERROR: Windows libtiff runtime DLL is missing from the Docker image:"
    echo "$WINDOWS_DEPS_BIN"
    echo
    echo "Rebuild the Windows build image from the repository root:"
    echo "  ./tools/qt-windows/docker_build.sh"
    exit 1
fi

HOST_JOBS="$(nproc)"
WINDOWS_BUILD_JOBS="${AOWIS_WINDOWS_BUILD_JOBS:-}"
if [ -z "$WINDOWS_BUILD_JOBS" ]; then
    WINDOWS_BUILD_JOBS="$HOST_JOBS"
    if [ "$WINDOWS_BUILD_JOBS" -gt "$MAX_DEFAULT_WINDOWS_BUILD_JOBS" ]; then
        WINDOWS_BUILD_JOBS="$MAX_DEFAULT_WINDOWS_BUILD_JOBS"
    fi
fi

if ! [[ "$WINDOWS_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: AOWIS_WINDOWS_BUILD_JOBS must be a positive integer."
    exit 1
fi
if [ "$WINE_RETRY_BUILD_JOBS" -gt "$WINDOWS_BUILD_JOBS" ]; then
    WINE_RETRY_BUILD_JOBS="$WINDOWS_BUILD_JOBS"
fi

echo "Windows build parallelism: $WINDOWS_BUILD_JOBS job(s) (host reports $HOST_JOBS CPU(s))"

qt-cmake . \
  -G Ninja \
  -B build-windows \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$WINDOWS_DEPS_PREFIX"

BUILD_LOG="build-windows/aowis-windows-build.log"

run_gui_build()
{
    local jobs="$1"
    local append_log="$2"
    local status

    set +e
    if [ "$append_log" = "yes" ]; then
        cmake --build build-windows \
          --target aowis-server-gui \
          --parallel "$jobs" 2>&1 | tee -a "$BUILD_LOG"
        status="${PIPESTATUS[0]}"
    else
        cmake --build build-windows \
          --target aowis-server-gui \
          --parallel "$jobs" 2>&1 | tee "$BUILD_LOG"
        status="${PIPESTATUS[0]}"
    fi
    set -e

    return "$status"
}

if ! run_gui_build "$WINDOWS_BUILD_JOBS" "no"; then
    if grep -Eiq \
        'wine: failed to map the shared user data: c0000018|cannot execute .*cc1(plus)?\.exe.*CreateProcess: No such file or directory' \
        "$BUILD_LOG"; then
        echo
        echo "Detected a transient Wine/MinGW process-launch failure."
        echo "Retrying the unfinished Ninja build with $WINE_RETRY_BUILD_JOBS job(s)."
        if command -v wineserver >/dev/null 2>&1; then
            wineserver -k >/dev/null 2>&1 || true
            sleep 1
        fi

        if ! run_gui_build "$WINE_RETRY_BUILD_JOBS" "yes"; then
            echo "ERROR: Windows build still failed after the Wine/MinGW retry."
            exit 1
        fi
    else
        echo "ERROR: Windows build failed. See $BUILD_LOG for details."
        exit 1
    fi
fi

mkdir -p build-windows/deploy

EXE="build-windows/AOWIS-SERVER-GUI/aowis-server-gui.exe"
if [ ! -f "$EXE" ]; then
    echo "ERROR: Expected executable not found:"
    echo "$EXE"
    echo
    echo "Available .exe files:"
    find build-windows \
        -type f \
        -name '*.exe' \
        ! -path '*/CMakeFiles/*' \
        | sort
    exit 1
fi

echo "Found GUI executable: $EXE"

cp "$EXE" build-windows/deploy/

# libtiff and zlib are built for the Windows target into C:/aowis-deps by
# Dockerfile.qt-windows. Ship every runtime DLL from that private prefix.
find "$WINDOWS_DEPS_BIN" \
    -maxdepth 1 \
    -type f \
    -iname '*.dll' \
    -exec cp -v '{}' build-windows/deploy/ \;

DEPLOY_EXE="build-windows/deploy/aowis-server-gui.exe"

windeployqt \
  --compiler-runtime \
  --dir build-windows/deploy \
  "$DEPLOY_EXE"

# EPANET-MSX uses OpenMP when available. MinGW's OpenMP runtime is not
# reliably included by windeployqt, so deploy libgomp explicitly.
if [ ! -f build-windows/deploy/libgomp-1.dll ]; then
    LIBGOMP_DLL="$(find /home/user/.wine/drive_c/Qt/Tools \
        -type f \
        -iname 'libgomp-1.dll' \
        -print -quit)"

    if [ -z "$LIBGOMP_DLL" ] || [ ! -f "$LIBGOMP_DLL" ]; then
        echo "ERROR: libgomp-1.dll is required by the Windows build but was not found."
        echo "Searched below: /home/user/.wine/drive_c/Qt/Tools"
        exit 1
    fi

    cp -v "$LIBGOMP_DLL" build-windows/deploy/libgomp-1.dll
fi

echo "=== Windows build complete ==="
echo "Executable deployed to: build-windows/deploy"
