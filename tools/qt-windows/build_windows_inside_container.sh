#!/bin/bash
set -e

echo "=== Building AOWIS for Windows x64 using Qt/MinGW ==="

cd /project

rm -rf build-windows
mkdir -p build-windows

qt-cmake . \
  -G Ninja \
  -B build-windows \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build-windows \
  --target aowis-server-gui \
  --parallel "$(nproc)"

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

DEPLOY_EXE="build-windows/deploy/aowis-server-gui.exe"

windeployqt \
  --dir build-windows/deploy \
  "$DEPLOY_EXE"

echo "=== Windows build complete ==="
echo "Executable deployed to: build-windows/deploy"
