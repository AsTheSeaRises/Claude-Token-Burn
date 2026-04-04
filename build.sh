#!/bin/bash
set -e

APP_NAME="ClaudeTokenBurn"
BUILD_CONFIG="release"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building $APP_NAME..."
cd "$SCRIPT_DIR"
swift build -c "$BUILD_CONFIG"

BINARY=".build/$BUILD_CONFIG/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "Bundling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "$BINARY"           "$CONTENTS/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$CONTENTS/"

echo "Done: $SCRIPT_DIR/$APP_BUNDLE"
echo ""
echo "To install, run:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo "  open /Applications/$APP_BUNDLE"
echo ""
echo "Or run directly:"
echo "  open $APP_BUNDLE"
