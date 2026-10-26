#!/bin/bash
# Quits ClipDown, removes its login item and moves the app to the Trash.
# Your settings stay; remove them with: defaults delete com.omarshahine.clipdown
set -euo pipefail

ID=com.omarshahine.clipdown
APP="$HOME/Applications/ClipDown.app"

if [ -x "$APP/Contents/MacOS/clipdown" ]; then
    "$APP/Contents/MacOS/clipdown" --unregister-login-item || true
fi
pgrep -f "ClipDown.app/Contents/MacOS/clipdown" | while read -r pid; do kill "$pid"; done || true
launchctl bootout "gui/$(id -u)/$ID" 2>/dev/null || true

for f in "$APP" "$HOME/Library/LaunchAgents/$ID.plist"; do
    if [ -e "$f" ]; then trash "$f"; fi
done
# Only remove the CLI link if it's ClipDown's.
LINK="$HOME/.local/bin/clipdown"
if [ -L "$LINK" ] && [[ "$(readlink "$LINK")" == *"/ClipDown.app/"* ]]; then
    trash "$LINK"
fi
echo "ClipDown removed"
