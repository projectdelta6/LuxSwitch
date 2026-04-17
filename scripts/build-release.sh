#!/bin/bash
set -euo pipefail

# Build a release of LuxSwitch — universal binary, .pkg installer, and .zip archive.
#
# Usage:
#   ./scripts/build-release.sh [version]
#
# If version is omitted, reads from Info.plist CFBundleShortVersionString.
# Examples:
#   ./scripts/build-release.sh 1.0.0
#   ./scripts/build-release.sh          # uses version from Info.plist

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="LuxSwitch"
APP_NAME="LuxSwitch"
BUNDLE_ID="com.projectdelta6.LuxSwitch"

BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
OUTPUT_DIR="$BUILD_DIR/output"

# --- Determine version ---
if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PROJECT_DIR/LuxSwitch/Info.plist")
fi
echo "Building $APP_NAME v$VERSION"

# --- Clean previous build ---
rm -rf "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

# --- Archive (universal binary: x86_64 + arm64) ---
echo ""
echo "==> Archiving universal binary..."
xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=YES \
    | tail -5

# --- Export .app from archive ---
echo ""
echo "==> Exporting app..."
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    # Some Xcode versions put it under usr/local
    APP_PATH=$(find "$ARCHIVE_PATH" -name "$APP_NAME.app" -type d | head -1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Could not find $APP_NAME.app in archive"
    exit 1
fi

echo "Found app at: $APP_PATH"

# Verify architectures
echo ""
echo "==> Verifying architectures..."
lipo -info "$APP_PATH/Contents/MacOS/$APP_NAME"

# --- Create .zip ---
echo ""
echo "==> Creating zip archive..."
ZIP_NAME="${APP_NAME}-v${VERSION}-universal.zip"
ditto -c -k --keepParent "$APP_PATH" "$OUTPUT_DIR/$ZIP_NAME"
echo "Created: $OUTPUT_DIR/$ZIP_NAME"

# --- Create .pkg installer ---
echo ""
echo "==> Creating pkg installer..."
PKG_NAME="${APP_NAME}-v${VERSION}-universal.pkg"

# Stage the app in a root hierarchy for pkgbuild
STAGE_DIR="$BUILD_DIR/pkg-stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Applications"
cp -R "$APP_PATH" "$STAGE_DIR/Applications/"

# Create postinstall script to launch app after install
SCRIPTS_DIR="$BUILD_DIR/pkg-scripts"
mkdir -p "$SCRIPTS_DIR"
cat > "$SCRIPTS_DIR/postinstall" <<'POSTINSTALL'
#!/bin/bash
# Launch LuxSwitch after installation (as the logged-in user, not root)
LOGGED_IN_USER=$(stat -f "%Su" /dev/console)
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ]; then
    sudo -u "$LOGGED_IN_USER" open "/Applications/LuxSwitch.app"
fi
exit 0
POSTINSTALL
chmod +x "$SCRIPTS_DIR/postinstall"

# Build the component package
COMPONENT_PKG="$BUILD_DIR/component.pkg"
pkgbuild \
    --root "$STAGE_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    "$COMPONENT_PKG"

# Build the distribution (product) package — gives a nicer installer UI
DISTRIBUTION_XML="$BUILD_DIR/distribution.xml"
cat > "$DISTRIBUTION_XML" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$APP_NAME</title>
    <welcome mime-type="text/plain"><![CDATA[
This will install $APP_NAME v$VERSION on your Mac.

$APP_NAME automatically switches between light and dark mode based on your ambient light sensor.
]]></welcome>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="$APP_NAME">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">component.pkg</pkg-ref>
</installer-gui-script>
DIST

productbuild \
    --distribution "$DISTRIBUTION_XML" \
    --package-path "$BUILD_DIR" \
    "$OUTPUT_DIR/$PKG_NAME"

echo "Created: $OUTPUT_DIR/$PKG_NAME"

# --- Summary ---
echo ""
echo "=== Build complete ==="
echo "Output directory: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION $OUTPUT_DIR/* --title \"v$VERSION\" --generate-notes"
