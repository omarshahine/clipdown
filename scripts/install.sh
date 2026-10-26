#!/bin/bash
# Builds ClipDown.app from source into ~/Applications and launches it.
# Requires Xcode 26 or later (Swift 6 and actool for the Icon Composer icon).
set -euo pipefail

cd "$(dirname "$0")/.."
ID=com.omarshahine.clipdown
APP="$HOME/Applications/ClipDown.app"
VERSION=$(git describe --tags --always 2>/dev/null || echo dev)

swift build -c release
BIN="$(swift build -c release --show-bin-path)/clipdown"

# Quit a running copy before replacing it.
pgrep -f "ClipDown.app/Contents/MacOS/clipdown" | while read -r pid; do kill "$pid"; done || true

STAGE=$(mktemp -d)/ClipDown.app
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/clipdown"
for f in Resources/MenuBarIcon*.png; do [ -e "$f" ] && cp "$f" "$STAGE/Contents/Resources/"; done

ICON_KEYS=""
if [ -d Resources/ClipDown.icon ]; then
    xcrun actool "$PWD/Resources/ClipDown.icon" --compile "$STAGE/Contents/Resources" \
        --platform macosx --minimum-deployment-target 15.0 --app-icon ClipDown \
        --output-partial-info-plist "$(dirname "$STAGE")/icon.plist" >/dev/null
    ICON_KEYS="<key>CFBundleIconName</key><string>ClipDown</string><key>CFBundleIconFile</key><string>ClipDown</string>"
fi

cat > "$STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$ID</string>
    <key>CFBundleName</key><string>ClipDown</string>
    <key>CFBundleDisplayName</key><string>ClipDown</string>
    <key>CFBundleExecutable</key><string>clipdown</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    $ICON_KEYS
</dict>
</plist>
EOF

# Use a Developer ID when there is one, so macOS keeps the clipboard and
# login-item permissions across rebuilds. Otherwise sign ad hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
codesign --force --options runtime --sign "${IDENTITY:--}" "$STAGE"

mkdir -p "$HOME/Applications"
[ -e "$APP" ] && trash "$APP"
mv "$STAGE" "$APP"

# Earlier versions ran as a LaunchAgent; the app is now its own login item.
LEGACY="$HOME/Library/LaunchAgents/$ID.plist"
if [ -e "$LEGACY" ]; then
    launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true
    trash "$LEGACY"
fi

# Put the CLI on PATH when ~/.local/bin is there.
if [ -d "$HOME/.local/bin" ]; then
    ln -sf "$APP/Contents/MacOS/clipdown" "$HOME/.local/bin/clipdown"
    CLI="clipdown"
else
    CLI="$APP/Contents/MacOS/clipdown"
fi

open "$APP"
echo "ClipDown $VERSION installed in $APP (signed: ${IDENTITY:-ad hoc})"
echo "CLI: $CLI --help"
