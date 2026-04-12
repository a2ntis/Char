#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/dist"
APP_NAME="Char"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_SOURCE="$ROOT_DIR/Assets/Tubasa/icon.jpg"
EXECUTABLE_SOURCE="$ROOT_DIR/.build/release/Char"

echo "Building release executable..."
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache" \
swift build -c release

rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$ICONSET_DIR"

echo "Creating app icon..."
sips -s format png -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -s format png -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

echo "Copying app resources..."
cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_SOURCE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
ditto "$ROOT_DIR/Assets" "$RESOURCES_DIR/Assets"
ditto "$ROOT_DIR/ThirdParty/CubismSdkForNative-5-r.5/Framework/src/Rendering/OpenGL/Shaders/Standard" "$RESOURCES_DIR/FrameworkShaders"

echo "Bundling dynamic libraries..."
cp /opt/homebrew/opt/glew/lib/libGLEW.2.3.dylib "$FRAMEWORKS_DIR/"
cp /opt/homebrew/opt/glfw/lib/libglfw.3.dylib "$FRAMEWORKS_DIR/"

install_name_tool -change /opt/homebrew/opt/glew/lib/libGLEW.2.3.dylib "@executable_path/../Frameworks/libGLEW.2.3.dylib" "$MACOS_DIR/$APP_NAME"
install_name_tool -change /opt/homebrew/opt/glfw/lib/libglfw.3.dylib "@executable_path/../Frameworks/libglfw.3.dylib" "$MACOS_DIR/$APP_NAME"

install_name_tool -id "@executable_path/../Frameworks/libGLEW.2.3.dylib" "$FRAMEWORKS_DIR/libGLEW.2.3.dylib"
install_name_tool -id "@executable_path/../Frameworks/libglfw.3.dylib" "$FRAMEWORKS_DIR/libglfw.3.dylib"

echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo
echo "App bundle ready:"
echo "  $APP_BUNDLE"
echo
echo "Launch with:"
echo "  open \"$APP_BUNDLE\""
