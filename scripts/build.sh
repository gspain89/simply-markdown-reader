#!/bin/bash
# Build Simply Markdown Reader.app bundle
set -e
cd "$(dirname "$0")/.."

APP_NAME="Simply Markdown Reader"
BUNDLE_ID="com.gregy.simply-markdown-reader"
VERSION="1.0.0"

echo "=== Building Simply Markdown Reader ==="

# 1. Check vendor libraries
if [ ! -f "Resources/vendor/marked.min.js" ]; then
    echo "Vendor libraries not found. Running setup..."
    bash scripts/setup.sh
fi

# 2. Generate app icon
if [ ! -f "/tmp/AppIcon.icns" ]; then
    echo "==> Generating app icon..."
    swift scripts/create-icon.swift
fi

# 3. Build Swift executable
echo "==> Compiling Swift..."
swift build -c release 2>&1

BINARY=".build/release/MarkdownReader"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed — binary not found"
    exit 1
fi

# 4. Assemble .app bundle
echo "==> Assembling .app bundle..."
DIST="dist"
APP_DIR="$DIST/${APP_NAME}.app/Contents"
rm -rf "$DIST/${APP_NAME}.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/MacOS/MarkdownReader"

# Copy resources
cp Resources/template.html "$APP_DIR/Resources/"
cp Resources/styles.css "$APP_DIR/Resources/"
cp Resources/app.js "$APP_DIR/Resources/"
cp -r Resources/vendor "$APP_DIR/Resources/"

# Copy icon
if [ -f "/tmp/AppIcon.icns" ]; then
    cp /tmp/AppIcon.icns "$APP_DIR/Resources/AppIcon.icns"
fi

# 5. Write Info.plist
cat > "$APP_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Simply Markdown Reader</string>
    <key>CFBundleDisplayName</key>
    <string>Simply Markdown Reader</string>
    <key>CFBundleIdentifier</key>
    <string>com.gregy.simply-markdown-reader</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>MarkdownReader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mkd</string>
                <string>mdx</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                    <string>mdown</string>
                    <string>mkd</string>
                    <string>mdx</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 6. Ad-hoc code sign
echo "==> Signing..."
codesign --force --sign - "$DIST/${APP_NAME}.app"

echo ""
echo "=== Build complete ==="
echo "App:  $DIST/${APP_NAME}.app"
echo ""
echo "To install:"
echo "  cp -r \"$DIST/${APP_NAME}.app\" /Applications/"
echo ""
echo "To set as default .md viewer:"
echo "  Right-click any .md file → Get Info → Open with → Simply Markdown Reader → Change All"
