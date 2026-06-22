#!/bin/bash
set -e

echo "=== Building AOWIS for macOS using Qt/osxcross ==="

cd /project

BUILD_DIR="build-macos"
QT_VERSION="${QT_VERSION:-6.7.0}"
QT_HOST_PATH="/opt/Qt/${QT_VERSION}/gcc_64"
QT_MACOS_PATH="/opt/Qt/${QT_VERSION}/macos"

echo "=== Build environment ==="
echo "PWD: $(pwd)"
echo "QT_VERSION: $QT_VERSION"
echo "QT_HOST_PATH: $QT_HOST_PATH"
echo "QT_MACOS_PATH: $QT_MACOS_PATH"
echo "qt-cmake: $(command -v qt-cmake || true)"
echo "cmake: $(command -v cmake || true)"
echo "ninja: $(command -v ninja || true)"
echo "========================="

if [ ! -x "$QT_HOST_PATH/libexec/moc" ]; then
    echo "ERROR: Host Qt moc not found or not executable:"
    echo "$QT_HOST_PATH/libexec/moc"
    exit 1
fi

if [ ! -x "$QT_HOST_PATH/libexec/rcc" ]; then
    echo "ERROR: Host Qt rcc not found or not executable:"
    echo "$QT_HOST_PATH/libexec/rcc"
    exit 1
fi

if [ ! -x "$QT_HOST_PATH/libexec/uic" ]; then
    echo "ERROR: Host Qt uic not found or not executable:"
    echo "$QT_HOST_PATH/libexec/uic"
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

qt-cmake . \
  -G Ninja \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DQT_HOST_PATH="$QT_HOST_PATH" \
  -DCONVERT_WARNINGS_TO_ERRORS=OFF \
  -DCMAKE_CXX_FLAGS="-include vector"

cmake --build "$BUILD_DIR" \
  --target aowis-server-gui \
  --parallel "$(nproc)"

APP="$(find "$BUILD_DIR" -maxdepth 5 -type d -name '*.app' | head -n 1)"

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
    echo "ERROR: No .app bundle found in $BUILD_DIR"
    echo
    echo "Available build files:"
    find "$BUILD_DIR" -maxdepth 5 -type f | sort
    exit 1
fi

echo "Found app bundle: $APP"

APP_EXE="$APP/Contents/MacOS/aowis-server-gui"
APP_FRAMEWORKS="$APP/Contents/Frameworks"
APP_PLUGINS="$APP/Contents/PlugIns"
APP_RESOURCES="$APP/Contents/Resources"

mkdir -p "$APP_FRAMEWORKS"
mkdir -p "$APP_PLUGINS"
mkdir -p "$APP_RESOURCES"

echo "=== Manually deploying Qt frameworks ==="

copy_framework_if_exists() {
    local name="$1"
    local src="$QT_MACOS_PATH/lib/${name}.framework"
    local dst="$APP_FRAMEWORKS/${name}.framework"

    if [ -d "$src" ]; then
        echo "Copying framework: $name"
        rm -rf "$dst"
        cp -R "$src" "$APP_FRAMEWORKS/"
    else
        echo "Skipping missing framework: $name"
    fi
}

copy_framework_if_exists QtCore
copy_framework_if_exists QtGui
copy_framework_if_exists QtWidgets
copy_framework_if_exists QtNetwork
copy_framework_if_exists QtPositioning
copy_framework_if_exists QtSerialPort
copy_framework_if_exists QtWebSockets
copy_framework_if_exists QtHttpServer
copy_framework_if_exists QtSvg

echo "=== Manually deploying Qt plugins ==="

copy_plugin_dir_if_exists() {
    local name="$1"
    local src="$QT_MACOS_PATH/plugins/$name"
    local dst="$APP_PLUGINS/$name"

    if [ -d "$src" ]; then
        echo "Copying plugin directory: $name"
        rm -rf "$dst"
        mkdir -p "$APP_PLUGINS"
        cp -R "$src" "$APP_PLUGINS/"
    else
        echo "Skipping missing plugin directory: $name"
    fi
}

copy_plugin_dir_if_exists platforms
copy_plugin_dir_if_exists imageformats
copy_plugin_dir_if_exists iconengines
copy_plugin_dir_if_exists styles
copy_plugin_dir_if_exists tls
copy_plugin_dir_if_exists position

cat > "$APP_RESOURCES/qt.conf" <<'EOF'
[Paths]
Plugins = PlugIns
EOF

echo "=== Fixing rpaths with osxcross install_name_tool ==="

INSTALL_NAME_TOOL="$(command -v x86_64-apple-darwin21.4-install_name_tool || true)"

if [ -z "$INSTALL_NAME_TOOL" ]; then
    echo "WARNING: install_name_tool not found. Bundle may not be self-contained."
else
    echo "install_name_tool: $INSTALL_NAME_TOOL"

    "$INSTALL_NAME_TOOL" -add_rpath "@executable_path/../Frameworks" "$APP_EXE" 2>/dev/null || true

    while IFS= read -r dylib; do
        echo "Adding plugin rpath: $dylib"
        "$INSTALL_NAME_TOOL" -add_rpath "@loader_path/../../Frameworks" "$dylib" 2>/dev/null || true
    done < <(find "$APP_PLUGINS" -type f -name '*.dylib' 2>/dev/null || true)
fi

echo "=== Creating macOS deploy directory ==="

rm -rf "$BUILD_DIR/deploy"
mkdir -p "$BUILD_DIR/deploy"

cp -R "$APP" "$BUILD_DIR/deploy/"

echo "=== macOS build complete ==="
echo "App deployed to: $BUILD_DIR/deploy"
