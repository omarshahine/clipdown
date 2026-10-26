#!/bin/bash
# Checks a built ClipDown.app: plist, signature, embedded Sparkle, version,
# and that the bundled CLI actually converts text.
# usage: scripts/validate-app.sh path/to/ClipDown.app [expected-version]
set -euo pipefail

APP=${1:?usage: validate-app.sh ClipDown.app [version]}
EXPECTED=${2:-}
PLIST="$APP/Contents/Info.plist"

plutil -lint "$PLIST"
codesign --verify --deep --strict --verbose=2 "$APP"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
for key in SUFeedURL SUPublicEDKey; do
    plutil -extract "$key" raw "$PLIST" >/dev/null
done

VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
if [ -n "$EXPECTED" ] && [ "$VERSION" != "$EXPECTED" ]; then
    echo "Bundle version $VERSION does not match $EXPECTED" >&2
    exit 1
fi

OUTPUT=$(printf 'Run  npm test  first\n' | "$APP/Contents/MacOS/clipdown" --dry-run 2>/dev/null)
if [ "$OUTPUT" != 'Run `npm test` first' ]; then
    echo "Unexpected conversion output: $OUTPUT" >&2
    exit 1
fi
echo "ClipDown $VERSION validated"
