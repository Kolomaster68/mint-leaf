#!/bin/bash

set -euo pipefail

ARCHIVE_PATH="$(pwd)/build/ios-device/MintLeaf.xcarchive"
EXPORT_PATH="$(pwd)/build/ios-export"
EXPORT_OPTIONS="$(pwd)/scripts/ExportOptions.plist"

echo "======================================"
echo " Packaging Mint Leaf for iOS"
echo "======================================"

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "ERROR: Archive not found:"
    echo "$ARCHIVE_PATH"
    echo
    echo "Run ./scripts/archive-ios.sh first."
    exit 1
fi

rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

echo
echo "======================================"
echo " Export successful"
echo "======================================"
echo
echo "Export directory:"
echo "$EXPORT_PATH"

find "$EXPORT_PATH" -name "*.ipa" -print
