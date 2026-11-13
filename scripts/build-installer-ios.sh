#!/bin/bash

set -euo pipefail

# ============================================================
# MintLeaf iOS Build and Package Script
#
# Creates a signed iOS archive and exports it as an IPA.
# ============================================================

PROJECT="MintLeaf.xcodeproj"
SCHEME="MintLeaf_iOS"
CONFIGURATION="Release"

ROOT_DIR="$(pwd)"
BUILD_DIR="$ROOT_DIR/build/ios-installer"
ARCHIVE_PATH="$BUILD_DIR/MintLeaf.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT_DIR/scripts/ExportOptions.plist"

echo "======================================"
echo " MintLeaf iOS Build & Installer"
echo "======================================"
echo

# ------------------------------------------------------------
# Verify required files
# ------------------------------------------------------------

if [ ! -d "$PROJECT" ]; then
    echo "ERROR: $PROJECT not found."
    echo "Run this script from the MintLeaf repository root."
    exit 1
fi

if [ ! -f "$EXPORT_OPTIONS" ]; then
    echo "ERROR: ExportOptions.plist not found:"
    echo "$EXPORT_OPTIONS"
    exit 1
fi

# ------------------------------------------------------------
# Clean previous build
# ------------------------------------------------------------

echo "[1/4] Cleaning previous build..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ------------------------------------------------------------
# Create iOS archive
# ------------------------------------------------------------

echo
echo "[2/4] Archiving MintLeaf for iOS..."

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

# Verify archive

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo
    echo "ERROR: Archive was not created."
    exit 1
fi

echo
echo "Archive created successfully:"
echo "$ARCHIVE_PATH"

# ------------------------------------------------------------
# Export IPA
# ------------------------------------------------------------

echo
echo "[3/4] Exporting IPA..."

mkdir -p "$EXPORT_PATH"

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

# ------------------------------------------------------------
# Verify IPA
# ------------------------------------------------------------

echo
echo "[4/4] Verifying IPA..."

IPA_PATH="$(find "$EXPORT_PATH" -type f -name "*.ipa" -print -quit)"

if [ -z "$IPA_PATH" ]; then
    echo
    echo "ERROR: IPA file was not created."
    exit 1
fi

IPA_SIZE="$(du -h "$IPA_PATH" | cut -f1)"

echo
echo "======================================"
echo " BUILD AND EXPORT SUCCEEDED"
echo "======================================"
echo
echo "Archive:"
echo "$ARCHIVE_PATH"
echo
echo "IPA:"
echo "$IPA_PATH"
echo
echo "IPA size:"
echo "$IPA_SIZE"
echo
echo "MintLeaf is ready for installation."
