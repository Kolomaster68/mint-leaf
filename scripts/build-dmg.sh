#!/bin/bash
set -e

# ── Configuration ──
APP_NAME="Mint Leaf"
SCHEME="MintLeaf_macOS"
PROJECT="MintLeaf.xcodeproj"
BUILD_DIR="build"
DMG_NAME="MintLeaf-v2.1.1"
VOLUME_NAME="Mint Leaf"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "🍃 Building $APP_NAME..."

# ── Clean & Build ──
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    -quiet

echo "📦 Exporting archive..."

# ── Export the .app from the archive ──
APP_PATH="$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/MintLeaf.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Could not find $APP_PATH"
    echo "   Searching for .app in archive..."
    find "$BUILD_DIR/$APP_NAME.xcarchive" -name "*.app" -type d
    exit 1
fi

# ── Create DMG ──
echo "💿 Creating DMG..."

DMG_TEMP="$BUILD_DIR/dmg-temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME.dmg"

rm -rf "$DMG_TEMP"

# ── Summary ──
DMG_SIZE=$(du -h "$BUILD_DIR/$DMG_NAME.dmg" | cut -f1)
echo ""
echo "✅ DMG created successfully!"
echo "   📍 $BUILD_DIR/$DMG_NAME.dmg"
echo "   📏 Size: $DMG_SIZE"
echo ""
echo "⚠️  Note: This DMG is not notarised."
echo "   Users will need to right-click → Open on first launch."
