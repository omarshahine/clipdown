#!/usr/bin/env bash
# Prints release notes from CHANGELOG.md.
#   scripts/release-notes.sh 1.2.3            the notes for 1.2.3 (GitHub release body)
#   scripts/release-notes.sh 1.2.3 --recent 3 1.2.3 and the two versions before it,
#                                             each under its heading (Sparkle shows only
#                                             the newest release, so people who skipped
#                                             one still see what changed)
# Fails when CHANGELOG.md has no section for the version.

set -euo pipefail

version="${1:?usage: release-notes.sh VERSION [--recent N]}"
recent=0
if [[ "${2:-}" == "--recent" ]]; then
	recent="${3:?--recent needs a count}"
fi
changelog="$(dirname "$0")/../CHANGELOG.md"

awk -v version="$version" -v recent="$recent" '
	/^## / {
		heading = $0
		sub(/^## +/, "", heading)
		sub(/[ \t]+$/, "", heading)
		if (heading == version) found = 1
		if (found) shown++
		if (recent == 0 && shown == 2) exit
		if (recent > 0 && shown > recent) exit
		if (recent > 0 && found) { print; next }
		if (found) next
	}
	found { print }
	END { if (!found) { print "CHANGELOG.md has no section for " version > "/dev/stderr"; exit 1 } }
' "$changelog" | awk 'NF { blank = 0; started = 1 } !NF { blank++ } started && blank < 2' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
