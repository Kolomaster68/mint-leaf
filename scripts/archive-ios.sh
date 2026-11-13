#!/bin/bash

set -euo pipefail

PROJECT="MintLeaf.xcodeproj"
SCHEME="MintLeaf_iOS"
CONFIGURATION="Release"

BUILD_DIR="$(pwd)/build/ios-device"
ARCHIVE_PATH="$BUILD_DIR/MintLeaf.xcarchive"

echo "======================================"
echo " Archiving Mint Leaf for iOS"
echo "======================================"

mkdir -p "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

echo
echo "======================================"
echo " Archive successful"
echo "======================================"
echo
echo "Archive:"
echo "$ARCHIVE_PATH"
