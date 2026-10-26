#!/bin/bash
# Builds ClipDown.app from source into ~/Applications and launches it.
# Requires Xcode 26 or later (Swift 6 and actool for the Icon Composer icon).
set -euo pipefail

cd "$(dirname "$0")/.."
ID=com.omarshahine.clipdown
APP="$HOME/Applications/ClipDown.app"
# Bundle versions must be numeric: the newest vX.Y.Z tag, and the commit
# count as the build number. The full git description is kept separately.
TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
VERSION=${TAG#v}
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || VERSION=0.0.0
BUILD=$(git rev-list --count HEAD 2>/dev/null) || BUILD=1
DESCRIBE=$(git describe --tags --always --dirty 2>/dev/null || echo unknown)

swift build -c release
BIN="$(swift build -c release --show-bin-path)/clipdown"

# Stage inside .build (already ignored and reused), so a failed run leaves
# nothing behind in temp folders.
STAGE_DIR=.build/stage
STAGE=$STAGE_DIR/ClipDown.app
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/clipdown"
for f in Resources/MenuBarIcon*.png; do
    if [ -e "$f" ]; then cp "$f" "$STAGE/Contents/Resources/"; fi
done

ICON_KEYS=""
if [ -d Resources/ClipDown.icon ]; then
    xcrun actool "$PWD/Resources/ClipDown.icon" --compile "$STAGE/Contents/Resources" \
        --platform macosx --minimum-deployment-target 15.0 --app-icon ClipDown \
        --output-partial-info-plist "$STAGE_DIR/icon.plist" >/dev/null
    HAS_ICON=1
fi

# PlistBuddy escapes values, so nothing in a tag name can break the XML.
PLIST="$STAGE/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null; }
[ -e "$PLIST" ] || pb "Save"
pb "Clear dict"
pb "Add :CFBundleIdentifier string $ID"
pb "Add :CFBundleName string ClipDown"
pb "Add :CFBundleDisplayName string ClipDown"
pb "Add :CFBundleExecutable string clipdown"
pb "Add :CFBundlePackageType string APPL"
pb "Add :CFBundleShortVersionString string $VERSION"
pb "Add :CFBundleVersion string $BUILD"
pb "Add :LSMinimumSystemVersion string 15.0"
pb "Add :LSUIElement bool true"
pb "Add :LSApplicationCategoryType string public.app-category.developer-tools"
if [ "${HAS_ICON:-}" ]; then
    pb "Add :CFBundleIconName string ClipDown"
    pb "Add :CFBundleIconFile string ClipDown"
fi
# plutil takes the value as its own argument, so any tag name round-trips.
plutil -insert ClipDownGitDescription -string "$DESCRIBE" "$PLIST"
plutil -lint "$PLIST" >/dev/null

# Use a Developer ID when there is one, so macOS keeps the clipboard and
# login-item permissions across rebuilds. Otherwise sign ad hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
codesign --force --options runtime --sign "${IDENTITY:--}" "$STAGE"

# Quit a running copy only now, once the new build is ready to drop in.
pgrep -f "ClipDown.app/Contents/MacOS/clipdown" | while read -r pid; do kill "$pid"; done || true

mkdir -p "$HOME/Applications"
[ -e "$APP" ] && trash "$APP"
mv "$STAGE" "$APP"

# Earlier versions ran as a LaunchAgent; the app is now its own login item.
LEGACY="$HOME/Library/LaunchAgents/$ID.plist"
if [ -e "$LEGACY" ]; then
    launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
    trash "$LEGACY"
fi

# Put the CLI on PATH when ~/.local/bin is there, without clobbering a
# different clipdown that's already there.
LINK="$HOME/.local/bin/clipdown"
CLI="$APP/Contents/MacOS/clipdown"
if [ -d "$HOME/.local/bin" ]; then
    if [ ! -e "$LINK" ] && [ ! -L "$LINK" ] || [[ "$(readlink "$LINK" 2>/dev/null)" == *"/ClipDown.app/"* ]]; then
        ln -sfn "$APP/Contents/MacOS/clipdown" "$LINK"
        CLI="clipdown"
    else
        echo "Left $LINK alone: it isn't ClipDown's."
    fi
fi

open "$APP"
echo "ClipDown $VERSION ($BUILD, $DESCRIBE) installed in $APP (signed: ${IDENTITY:-ad hoc})"
echo "CLI: $CLI --help"
