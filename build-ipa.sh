#!/bin/bash

# Build script for KstApp IPA
# Usage: ./build-ipa.sh

set -e  # Exit on error

SCHEME="KstApp"
PROJECT="KstApp.xcodeproj"
ARCHIVE_PATH="./KstApp.xcarchive"
EXPORT_PATH="./KstApp-Export"
EXPORT_OPTIONS="./ExportOptions.plist"

echo "🔨 Building KstApp IPA..."
echo ""

# Check if ExportOptions.plist exists
if [ ! -f "$EXPORT_OPTIONS" ]; then
    echo "❌ Error: ExportOptions.plist not found!"
    exit 1
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# Archive
echo "📦 Creating archive..."
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [ $? -ne 0 ]; then
    echo "❌ Archive failed!"
    exit 1
fi

echo "✅ Archive created successfully!"
echo ""

# Export IPA
echo "📤 Exporting IPA..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

if [ $? -ne 0 ]; then
    echo "❌ IPA export failed!"
    exit 1
fi

echo ""
echo "✅ IPA created successfully!"
echo "📍 Location: $EXPORT_PATH/KstApp.ipa"
echo ""

