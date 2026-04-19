#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "Building FileClassifier (universal binary)..."
swift build -c release --arch arm64 --arch x86_64

APP_DIR="$ROOT_DIR/build/FileClassifier.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$ROOT_DIR/.build/apple/Products/Release/FileClassifier"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/FileClassifier"
chmod +x "$MACOS_DIR/FileClassifier"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

# Ad-hoc sign so Gatekeeper doesn't immediately kill the process
codesign --force --sign - "$APP_DIR"

# Create distributable zip
cd "$ROOT_DIR/build"
rm -f FileClassifier.zip
ditto -c -k --sequesterRsrc --keepParent FileClassifier.app FileClassifier.zip

echo
echo "App bundle created:"
echo "  $APP_DIR"
echo
echo "Distributable zip:"
echo "  $ROOT_DIR/build/FileClassifier.zip ($(du -h FileClassifier.zip | cut -f1 | xargs))"
echo
echo "Run it with:"
echo "  open \"$APP_DIR\""
echo
echo "To share: send FileClassifier.zip"
echo "  Friend: unzip → right-click FileClassifier.app → Open"
