#!/bin/bash
# Create a distributable DMG installer
set -e
cd "$(dirname "$0")/.."

APP_NAME="Simply Markdown Reader"
VERSION="1.0.3"
DMG_NAME="SimplyMarkdownReader-${VERSION}"

APP_PATH="dist/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo "App not found at $APP_PATH. Run build.sh first."
    exit 1
fi

echo "==> Creating DMG..."

# Create staging directory
DMG_DIR="dist/dmg-staging"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app
cp -r "$APP_PATH" "$DMG_DIR/"

# Create Applications symlink (drag-to-install UX)
ln -s /Applications "$DMG_DIR/Applications"

# Remove old DMG if exists
rm -f "dist/${DMG_NAME}.dmg"

# Create DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "dist/${DMG_NAME}.dmg"

# Cleanup
rm -rf "$DMG_DIR"

echo ""
echo "=== DMG created ==="
echo "File: dist/${DMG_NAME}.dmg"
echo ""
echo "Share this file with friends — they can open it and drag the app to Applications."
