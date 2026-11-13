#!/bin/bash

set -euo pipefail

PROJECT="MintLeaf.xcodeproj"
SCHEME="MintLeaf_iOS"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build/ios"

echo "======================================"
echo " Building Mint Leaf for iOS Simulator"
echo "======================================"

rm -rf "$BUILD_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build

echo
echo "======================================"
echo " Build successful"
echo "======================================"
echo
echo "Application:"
echo "$BUILD_DIR/Build/Products/Release-iphonesimulator/MintLeaf.app"
