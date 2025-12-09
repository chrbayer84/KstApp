#!/bin/bash

# Build script for KstApp IPA
# Usage: ./build-ipa.sh <version>
# Example: ./build-ipa.sh 1.2

set -e  # Exit on error

# Check if version argument is provided
if [ -z "$1" ]; then
    echo "❌ Error: Version argument is required!"
    echo "Usage: ./build-ipa.sh <version>"
    echo "Example: ./build-ipa.sh 1.2"
    exit 1
fi

VERSION="$1"
SCHEME="KstApp"
PROJECT="KstApp.xcodeproj"
ARCHIVE_PATH="./KstApp.xcarchive"
EXPORT_PATH="./KstApp-Export"
EXPORT_OPTIONS="./ExportOptions.plist"
PROJECT_FILE="$PROJECT/project.pbxproj"
ALSTORE_SOURCE="altstore-source.json"

echo "🔨 Building KstApp IPA version $VERSION..."
echo ""

# Validate version format (basic check - should be like 1.2, 1.2.3, etc.)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ Error: Invalid version format. Expected format: X.Y or X.Y.Z (e.g., 1.2 or 1.2.3)"
    exit 1
fi

# Check if required files exist
if [ ! -f "$EXPORT_OPTIONS" ]; then
    echo "❌ Error: ExportOptions.plist not found!"
    exit 1
fi

if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Error: $PROJECT_FILE not found!"
    exit 1
fi

if [ ! -f "$ALSTORE_SOURCE" ]; then
    echo "❌ Error: $ALSTORE_SOURCE not found!"
    exit 1
fi

# Update MARKETING_VERSION in project.pbxproj (both Debug and Release)
echo "📝 Updating MARKETING_VERSION to $VERSION in project.pbxproj..."
# Use a temporary file for sed on macOS
sed "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE" > "$PROJECT_FILE.tmp" && mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"
if [ $? -eq 0 ]; then
    echo "✅ Updated MARKETING_VERSION in project.pbxproj"
else
    echo "❌ Failed to update MARKETING_VERSION"
    exit 1
fi

# Update version in altstore-source.json
echo "📝 Updating version to $VERSION in altstore-source.json..."
# Use Python to update JSON file safely
python3 << EOF
import json
import sys
import re
from datetime import datetime, timezone

version = "$VERSION"
source_file = "$ALSTORE_SOURCE"

try:
    with open(source_file, 'r') as f:
        data = json.load(f)
    
    # Update version in the first version entry
    if 'apps' in data and len(data['apps']) > 0:
        app = data['apps'][0]
        if 'versions' in app and len(app['versions']) > 0:
            app['versions'][0]['version'] = version
            # Update timestamp to current date/time in ISO 8601 format with timezone
            now = datetime.now(timezone.utc).astimezone()
            # Format as ISO 8601 with timezone offset (e.g., 2025-12-07T19:02:00-04:00)
            current_time = now.strftime('%Y-%m-%dT%H:%M:%S%z')
            # Add colon to timezone offset (e.g., -0400 -> -04:00)
            if len(current_time) > 6 and current_time[-5] != ':':
                current_time = current_time[:-2] + ':' + current_time[-2:]
            app['versions'][0]['date'] = current_time
            # Also update downloadURL to match new version
            if 'downloadURL' in app['versions'][0]:
                url = app['versions'][0]['downloadURL']
                # Replace version in URL (e.g., v1.2 -> v1.3)
                url = re.sub(r'/v[0-9.]+/', f'/v{version}/', url)
                app['versions'][0]['downloadURL'] = url
    
    with open(source_file, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    
    print("✅ Updated version and timestamp in altstore-source.json")
except Exception as e:
    print(f"❌ Error updating altstore-source.json: {e}")
    sys.exit(1)
EOF

if [ $? -ne 0 ]; then
    echo "❌ Failed to update altstore-source.json"
    exit 1
fi

echo ""

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
echo "📦 Version: $VERSION"
echo ""

