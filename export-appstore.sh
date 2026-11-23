#!/bin/bash
# Archive and export KstApp for App Store Connect.
#
# Usage:
#   ./export-appstore.sh                          # archive + export current version
#   ./export-appstore.sh --bump-version           # bump 1.8 -> 1.9 (1.8.1 -> 1.8.2), then archive + export
#   ./export-appstore.sh --version 1.9            # set marketing version, then archive + export
#   ./export-appstore.sh --increment-build        # increment build number, then archive + export
#   ./export-appstore.sh --version 1.9 --build 5  # set marketing version and build number
#   ./export-appstore.sh --no-archive             # export an existing KstApp.xcarchive
#
# Version/build changes require a fresh archive and are incompatible with
# --no-archive.
#
# Overridable:
#   TEAM_ID, PROFILE_NAME, SIGNING_CERTIFICATE, ARCHIVE, EXPORT_PATH
#
# IMPORTANT: Rebuild the archive after changing signing settings. An archive
# created with a different bundle ID or signing style will fail to export with
# "requires a provisioning profile".

set -euo pipefail

SCHEME="KstApp"
PROJECT="KstApp.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"
ARCHIVE="${ARCHIVE:-./KstApp.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-./export}"
TEAM_ID="${TEAM_ID:-VRRTAP3C2B}"
PROFILE_NAME="${PROFILE_NAME:-Kst App Apple Store}"
SIGNING_CERTIFICATE="${SIGNING_CERTIFICATE:-iPhone Distribution}"

VERSION=""
BUMP_VERSION="false"
BUILD_NUMBER=""
INCREMENT_BUILD="false"
SKIP_ARCHIVE="false"

usage() {
  sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-archive)
      SKIP_ARCHIVE="true"
      shift
      ;;
    --version|-v)
      if [ $# -lt 2 ]; then
        echo "Missing value for $1"
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --bump-version)
      BUMP_VERSION="true"
      shift
      ;;
    --build)
      if [ $# -lt 2 ]; then
        echo "Missing value for $1"
        exit 1
      fi
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --increment-build)
      INCREMENT_BUILD="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [ "$BUMP_VERSION" = "true" ] && [ -n "$VERSION" ]; then
  echo "Use either --version or --bump-version, not both."
  exit 1
fi

if [ -n "$BUILD_NUMBER" ] && [ "$INCREMENT_BUILD" = "true" ]; then
  echo "Use either --build or --increment-build, not both."
  exit 1
fi

if [ "$SKIP_ARCHIVE" = "true" ] && { [ -n "$VERSION" ] || [ "$BUMP_VERSION" = "true" ] || [ -n "$BUILD_NUMBER" ] || [ "$INCREMENT_BUILD" = "true" ]; }; then
  echo "Version/build changes require a fresh archive; remove --no-archive."
  exit 1
fi

CURRENT_MARKETING_VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/p' "$PROJECT_FILE" | head -n 1)
CURRENT_BUILD_NUMBER=$(sed -nE 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$PROJECT_FILE" | head -n 1)

if [ "$BUMP_VERSION" = "true" ]; then
  if [ -z "$CURRENT_MARKETING_VERSION" ]; then
    echo "Could not read current MARKETING_VERSION from $PROJECT_FILE"
    exit 1
  fi

  IFS='.' read -r major minor patch <<< "$CURRENT_MARKETING_VERSION"
  if [ -n "${patch:-}" ]; then
    VERSION="$major.$minor.$((patch + 1))"
  else
    VERSION="$major.$((minor + 1))"
  fi
fi

if [ -n "$VERSION" ]; then
  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Invalid version '$VERSION'. Expected X.Y or X.Y.Z."
    exit 1
  fi

  echo "Updating MARKETING_VERSION: $CURRENT_MARKETING_VERSION -> $VERSION"
  sed "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE" > "$PROJECT_FILE.tmp"
  mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"
fi

if [ -n "$BUILD_NUMBER" ] || [ "$INCREMENT_BUILD" = "true" ]; then
  if [ "$INCREMENT_BUILD" = "true" ]; then
    if [ -z "$CURRENT_BUILD_NUMBER" ]; then
      echo "Could not read current CURRENT_PROJECT_VERSION from $PROJECT_FILE"
      exit 1
    fi
    BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
  fi

  if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Invalid build number '$BUILD_NUMBER'. Expected a positive integer."
    exit 1
  fi

  echo "Updating CURRENT_PROJECT_VERSION: $CURRENT_BUILD_NUMBER -> $BUILD_NUMBER"
  sed "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE" > "$PROJECT_FILE.tmp"
  mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"
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
	<string>$SIGNING_CERTIFICATE</string>
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
