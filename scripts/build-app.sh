#!/bin/bash
# Builds a signed ClipDown.app with Sparkle embedded, and prints its path.
# Used by scripts/install.sh and the Release workflow.
#
#   APP_VERSION        CFBundleShortVersionString (default: newest vX.Y.Z tag)
#   BUILD_NUMBER       CFBundleVersion (default: commit count)
#   CODESIGN_IDENTITY  signing identity (default: a Developer ID if one is
#                      installed, otherwise "-" for ad hoc)
#   OUTPUT_DIR         where ClipDown.app goes (default: .build/stage)
set -euo pipefail

cd "$(dirname "$0")/.."
ID=com.omarshahine.clipdown
FEED_URL=https://github.com/omarshahine/clipdown/releases/latest/download/appcast.xml
# Public half of the Sparkle EdDSA key. The private half is the
# SPARKLE_PRIVATE_KEY Actions secret (backed up outside the repo).
SPARKLE_PUBLIC_KEY=ySSJZoXrOGXtJwt1IRDvsXRf6PKmYBwqafUO9EdvItY=

# Bundle versions must be numeric. The full git description is kept separately.
if [ -z "${APP_VERSION:-}" ]; then
    TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
    APP_VERSION=${TAG#v}
fi
[[ "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || APP_VERSION=0.0.0
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null) || BUILD_NUMBER=1
fi
DESCRIBE=$(git describe --tags --always --dirty 2>/dev/null || echo unknown)

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
    CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
fi

swift build -c release >&2
BIN_DIR="$(swift build -c release --show-bin-path)"

# Stage inside .build (ignored and reused), so a failed run leaves nothing in
# temp folders.
OUTPUT_DIR=${OUTPUT_DIR:-.build/stage}
APP="$OUTPUT_DIR/ClipDown.app"
if [ -e "$APP" ]; then trash "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
ditto "$BIN_DIR/clipdown" "$APP/Contents/MacOS/clipdown"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if ! otool -l "$APP/Contents/MacOS/clipdown" | grep -Fq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/clipdown"
fi
for f in Resources/MenuBarIcon*.png Resources/Omar.jpg; do
    if [ -e "$f" ]; then ditto "$f" "$APP/Contents/Resources/$(basename "$f")"; fi
done

HAS_ICON=""
if [ -d Resources/ClipDown.icon ]; then
    xcrun actool "$PWD/Resources/ClipDown.icon" --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target 15.0 --app-icon ClipDown \
        --output-partial-info-plist "$OUTPUT_DIR/icon.plist" >/dev/null
    HAS_ICON=1
fi

# PlistBuddy and plutil escape values, so nothing in a tag name can break the XML.
PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null; }
pb "Save"
pb "Clear dict"
pb "Add :CFBundleIdentifier string $ID"
pb "Add :CFBundleName string ClipDown"
pb "Add :CFBundleDisplayName string ClipDown"
pb "Add :CFBundleExecutable string clipdown"
pb "Add :CFBundlePackageType string APPL"
pb "Add :CFBundleShortVersionString string $APP_VERSION"
pb "Add :CFBundleVersion string $BUILD_NUMBER"
pb "Add :LSMinimumSystemVersion string 15.0"
pb "Add :LSUIElement bool true"
pb "Add :LSApplicationCategoryType string public.app-category.developer-tools"
pb "Add :NSHumanReadableCopyright string Copyright 2026 Omar Shahine. MIT License."
pb "Add :SUFeedURL string $FEED_URL"
pb "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY"
pb "Add :SUEnableAutomaticChecks bool true"
pb "Add :SUSendProfileInfo bool false"
if [ "$HAS_ICON" ]; then
    pb "Add :CFBundleIconName string ClipDown"
    pb "Add :CFBundleIconFile string ClipDown"
fi
plutil -insert ClipDownGitDescription -string "$DESCRIBE" "$PLIST"
plutil -lint "$PLIST" >/dev/null

sign() {
    if [ "$CODESIGN_IDENTITY" = "-" ]; then
        # Ad hoc builds can't share a team with Sparkle, and the hardened
        # runtime's library validation would then refuse to load it.
        codesign --force --sign - "$1"
    else
        codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$1"
    fi
}

# Inside out: Sparkle's helpers, the framework, then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"

codesign --verify --deep --strict "$APP"
echo "$APP"
