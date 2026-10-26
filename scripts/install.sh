#!/bin/bash
# Builds ClipDown.app from source into ~/Applications and launches it.
# Requires Xcode 26 or later (Swift 6 and actool for the Icon Composer icon).
# Most people should install a release instead: brew install --cask omarshahine/tap/clipdown
set -euo pipefail

cd "$(dirname "$0")/.."
ID=com.omarshahine.clipdown
APP="$HOME/Applications/ClipDown.app"

STAGED=$(scripts/build-app.sh)

# Quit a running copy only now, once the new build is ready to drop in.
pgrep -f "ClipDown.app/Contents/MacOS/clipdown" | while read -r pid; do kill "$pid"; done || true

mkdir -p "$HOME/Applications"
if [ -e "$APP" ]; then trash "$APP"; fi
mv "$STAGED" "$APP"

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
PLIST="$APP/Contents/Info.plist"
echo "ClipDown $(plutil -extract CFBundleShortVersionString raw "$PLIST") ($(plutil -extract CFBundleVersion raw "$PLIST"), $(plutil -extract ClipDownGitDescription raw "$PLIST")) installed in $APP"
echo "CLI: $CLI --help"
