#!/usr/bin/env bash
# Install one known Qt/MinGW ABI pair. This script runs as user inside Docker.
set -euo pipefail

: "${AOWIS_QT_VERSION:?AOWIS_QT_VERSION is required}"
: "${AOWIS_MINGW_VERSION:?AOWIS_MINGW_VERSION is required}"
: "${WINEPREFIX:?WINEPREFIX is required}"

qt_root="${WINEPREFIX}/drive_c/Qt"
aqt=/opt/aqt/bin/aqt
mkdir -p "$qt_root"
# Establish a real 64-bit Wine prefix before populating its C: drive.
wineboot --init
wineserver -w

# aqt is run natively on Linux to download the official Windows Qt archives.
# Wine is used to execute the downloaded Windows compiler/CMake/Qt tools.
"$aqt" install-qt -O "$qt_root" \
    windows desktop "$AOWIS_QT_VERSION" win64_mingw \
    -m qtwebsockets qthttpserver qtpositioning qtserialport qtshadertools

qt_bin="$qt_root/$AOWIS_QT_VERSION/mingw_64/bin"
qt_cmake="$qt_root/$AOWIS_QT_VERSION/mingw_64/lib/cmake"
for component in Qt6 Qt6Widgets Qt6Network Qt6Sql Qt6WebSockets Qt6HttpServer Qt6Positioning Qt6SerialPort; do
    if [ ! -d "$qt_cmake/$component" ]; then
        printf 'Required Qt %s component is missing: %s\n' "$AOWIS_QT_VERSION" "$component" >&2
        exit 1
    fi
done
if [ ! -f "$qt_bin/qt-cmake.bat" ] && [ ! -f "$qt_bin/qt-cmake.exe" ]; then
    echo "Missing qt-cmake launcher in $qt_bin" >&2
    exit 1
fi

# Prefer an official Qt tool archive if the selected compiler is published.
# Qt 6.12 itself uses GCC 15.1, but Qt's public `tools_mingw*` metadata
# may still offer only GCC 13.1; in that case use the *same* upstream
# MinGW-builds variant documented for the Qt 6.12 release (MSVCRT,
# POSIX threads, SEH exceptions). Never silently substitute UCRT/GCC 13.
tool_names=$("$aqt" list-tool windows desktop)
mingw_group=''
mingw_variant=''
for group in $tool_names; do
    case "$group" in
        tools_mingw*) ;;
        *) continue ;;
    esac
    details=$("$aqt" list-tool windows desktop "$group" --long)
    variant=$(printf '%s\n' "$details" | awk -v version="$AOWIS_MINGW_VERSION" \
        '$1 ~ /^qt[.]tools[.].*mingw/ && index($0, version) {print $1; exit}')
    if [ -n "$variant" ]; then
        if [ -n "$mingw_variant" ]; then
            echo "Multiple MinGW $AOWIS_MINGW_VERSION packages; refusing ambiguous selection" >&2
            exit 1
        fi
        mingw_group=$group
        mingw_variant=$variant
    fi
done
if [ -n "$mingw_variant" ]; then
    echo "Installing Qt tool package $mingw_variant ($mingw_group)"
    "$aqt" install-tool -O "$qt_root" windows desktop "$mingw_group" "$mingw_variant"
else
    if [ "$AOWIS_MINGW_VERSION" != '15.1.0' ]; then
        echo "No Qt MinGW tool package matches required GCC $AOWIS_MINGW_VERSION" >&2
        exit 1
    fi
    echo 'Qt tool repository does not list GCC 15.1; installing its matching MinGW-builds toolchain.'
    # Exact GCC 15.1 POSIX/SEH/MSVCRT distribution used in Qt 6.12 CI.
    # https://wiki.qt.io/Qt_6.12_Tools_and_Versions
    compiler_url='https://github.com/niXman/mingw-builds-binaries/releases/download/15.1.0-rt_v12-rev0/x86_64-15.1.0-release-posix-seh-msvcrt-rt_v12-rev0.7z'
    archive=$(mktemp --suffix=.7z)
    staging=$(mktemp -d)
    trap 'rm -f "$archive"; rm -rf "$staging"' EXIT
    curl --fail --location --retry 4 --retry-delay 5 --silent --show-error \
        "$compiler_url" -o "$archive"
    7z x -y -o"$staging" "$archive" >/dev/null
    if [ ! -f "$staging/mingw64/bin/g++.exe" ]; then
        echo 'Unexpected GCC archive structure: missing mingw64/bin/g++.exe' >&2
        exit 1
    fi
    mkdir -p "$qt_root/Tools"
    mv "$staging/mingw64" "$qt_root/Tools/mingw1510_64"
    rm -f "$archive"
    rm -rf "$staging"
    trap - EXIT
fi
"$aqt" install-tool -O "$qt_root" windows desktop tools_cmake
"$aqt" install-tool -O "$qt_root" windows desktop tools_ninja

# A fresh image has one MinGW toolchain; verify it rather than relying on its
# directory naming convention (which has changed repeatedly in Qt installers).
shopt -s nullglob
compiler_paths=("$qt_root"/Tools/mingw*/bin/g++.exe)
if [ "${#compiler_paths[@]}" -ne 1 ]; then
    printf 'Expected one MinGW compiler, found %d:\n' "${#compiler_paths[@]}" >&2
    printf '  %s\n' "${compiler_paths[@]}" >&2
    exit 1
fi
compiler_bin=$(dirname "${compiler_paths[0]}")
compiler_version=$(wine "${compiler_paths[0]}" -dumpfullversion -dumpversion | tr -d '\r')
if [ "$compiler_version" != "$AOWIS_MINGW_VERSION" ]; then
    echo "Incorrect MinGW compiler: expected $AOWIS_MINGW_VERSION, got $compiler_version" >&2
    exit 1
fi

cmake_bin="$qt_root/Tools/CMake_64/bin"
ninja_bin="$qt_root/Tools/Ninja"
test -f "$cmake_bin/cmake.exe"
test -f "$ninja_bin/ninja.exe"

# Resolve the Windows toolchain unambiguously.  Wine's Linux PATH must not
# be confused with Windows' user environment Path.
compiler_relative="$(basename "$(dirname "$compiler_bin")")"
windows_path="C:\\Qt\\$AOWIS_QT_VERSION\\mingw_64\\bin;C:\\Qt\\Tools\\$compiler_relative\\bin;C:\\Qt\\Tools\\CMake_64\\bin;C:\\Qt\\Tools\\Ninja"
wine reg add 'HKCU\Environment' /v Path /t REG_SZ /d "$windows_path" /f
wineserver -k || true

# Maintain compatibility with Standalone's existing Wine-based build scripts.
# These intentionally run the *Windows* CMake/Ninja and Qt utilities.
for tool in cmake ninja windeployqt; do
    printf '#!/bin/sh\nexec wine %s "$@"\n' "$tool" > "/home/user/bin/$tool"
done
cat > /home/user/bin/qt-cmake <<'SH'
#!/bin/sh
exec wine cmd /c qt-cmake "$@"
SH
chmod +x /home/user/bin/*

# Build-time sanity checks before attempting large third-party libraries.
echo "=== Windows toolchain preflight ==="
wine cmd /c g++ -dumpfullversion -dumpversion
wine cmd /c cmake --version
wine cmd /c ninja --version
wine cmd /c windeployqt --version

mkdir -p /tmp/aowis-mingw-preflight
cat > /tmp/aowis-mingw-preflight/CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.25)
project(AOWISWindowsToolchainProbe LANGUAGES CXX)
find_package(Qt6 6.12 REQUIRED COMPONENTS Widgets Network Sql HttpServer Positioning SerialPort WebSockets)
add_executable(aowis-toolchain-probe main.cpp)
target_compile_features(aowis-toolchain-probe PRIVATE cxx_std_20)
target_link_libraries(aowis-toolchain-probe PRIVATE Qt6::Widgets Qt6::HttpServer)
CMAKE
cat > /tmp/aowis-mingw-preflight/main.cpp <<'CPP'
#include <QApplication>
#include <QHttpServer>
#include <d3d11.h>
int main(int argc, char **argv)
{
    // Exercise the exact nested union initializers that failed with GCC 11.2.
    const D3D11_DEPTH_STENCIL_VIEW_DESC depth = {
        .Format = DXGI_FORMAT_D24_UNORM_S8_UINT,
        .ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2DARRAY,
        .Flags = 0,
        .Texture2DArray = {
            .MipSlice = 0,
            .FirstArraySlice = 0,
            .ArraySize = 1,
        },
    };
    const D3D11_SHADER_RESOURCE_VIEW_DESC shader = {
        .Format = DXGI_FORMAT_R32_FLOAT,
        .ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2DARRAY,
        .Texture2DArray = {
            .MostDetailedMip = 0,
            .MipLevels = 1,
            .FirstArraySlice = 0,
            .ArraySize = 1,
        },
    };
    QApplication app(argc, argv);
    QHttpServer server;
    return (depth.Texture2DArray.ArraySize == 1 &&
            shader.Texture2DArray.ArraySize == 1) ? 0 : 1;
}
CPP
qt-cmake /tmp/aowis-mingw-preflight -G Ninja -B /tmp/aowis-mingw-preflight/build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/aowis-mingw-preflight/build --parallel 2
rm -rf /tmp/aowis-mingw-preflight

echo "=== Verified Qt $AOWIS_QT_VERSION / MinGW $compiler_version ==="
