#!/bin/bash
# Archive and export KstApp for App Store Connect.
#
# Usage:
#   ./export-appstore.sh                 # archive from source, then export
#   ./export-appstore.sh --no-archive    # export an existing KstApp.xcarchive
#
# Overridable:
#   TEAM_ID, PROFILE_NAME, ARCHIVE, EXPORT_PATH
#
# IMPORTANT: Rebuild the archive after changing signing settings. An archive
# created with a different bundle ID or signing style will fail to export with
# "requires a provisioning profile".

set -euo pipefail

SCHEME="KstApp"
PROJECT="KstApp.xcodeproj"
ARCHIVE="${ARCHIVE:-./KstApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-./export}"
TEAM_ID="${TEAM_ID:-VRRTAP3C2B}"
PROFILE_NAME="${PROFILE_NAME:-Kst App Apple Store}"
SKIP_ARCHIVE="false"

if [ "${1:-}" = "--no-archive" ]; then
  SKIP_ARCHIVE="true"
fi

if [ "$SKIP_ARCHIVE" != "true" ]; then
  echo "Archiving $SCHEME..."
  rm -rf "$ARCHIVE"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive
fi

if [ ! -d "$ARCHIVE" ]; then
  echo "Archive not found at $ARCHIVE"
  exit 1
fi

# Use the bundle identifier actually embedded in the archive so the
# provisioningProfiles key can never drift from the built app.
BUNDLE_ID=$(/usr/libexec/PlistBuddy \
  -c "Print :ApplicationProperties:CFBundleIdentifier" \
  "$ARCHIVE/Info.plist")

if [ -z "$BUNDLE_ID" ]; then
  echo "Could not read CFBundleIdentifier from $ARCHIVE/Info.plist"
  exit 1
fi

echo "Archive bundle ID: $BUNDLE_ID"
echo "Team ID:           $TEAM_ID"
echo "Profile:           $PROFILE_NAME"

TMP_OPTIONS=$(mktemp /tmp/KstAppExportOptions.XXXXXX.plist)
trap 'rm -f "$TMP_OPTIONS"' EXIT

cat > "$TMP_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>iPhone Distribution</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>$BUNDLE_ID</key>
		<string>$PROFILE_NAME</string>
	</dict>
	<key>uploadSymbols</key>
	<true/>
	<key>stripSwiftSymbols</key>
	<true/>
</dict>
</plist>
PLIST

rm -rf "$EXPORT_PATH"

echo "Exporting to $EXPORT_PATH..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$TMP_OPTIONS" \
  -allowProvisioningUpdates

echo "Export complete: $EXPORT_PATH"
