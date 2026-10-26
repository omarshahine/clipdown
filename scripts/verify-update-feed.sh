#!/usr/bin/env bash

set -euo pipefail

app_path="${1:-/Applications/ClipDown.app}"
expected_version="${2:-}"

if [[ ! -d "$app_path" ]]; then
	echo "ClipDown app not found at $app_path" >&2
	exit 1
fi

info_plist="$app_path/Contents/Info.plist"
installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
feed_url="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$info_plist")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info_plist")"
temp_dir="$(mktemp -d /private/tmp/clipdown-update-check.XXXXXX)"

cleanup() {
	/usr/bin/trash "$temp_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

appcast_path="$temp_dir/appcast.xml"
archive_path="$temp_dir/ClipDown-update.zip"
feed_version=""
for attempt in {1..10}; do
	curl --fail --location --silent --show-error \
		--retry 5 --retry-delay 2 --retry-all-errors \
		"$feed_url" --output "$appcast_path"
	xmllint --noout "$appcast_path"
	feed_version="$(xmllint --xpath 'string(//*[local-name()="shortVersionString"])' "$appcast_path")"
	if [[ -z "$expected_version" || "$feed_version" == "$expected_version" ]]; then
		break
	fi
	if [[ "$attempt" -eq 10 ]]; then
		echo "Expected update $expected_version, found $feed_version" >&2
		exit 1
	fi
	sleep 3
done

archive_url="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@url)' "$appcast_path")"
archive_length="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@length)' "$appcast_path")"
archive_signature="$(xmllint --xpath 'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' "$appcast_path")"

version_is_newer() {
	local candidate_major candidate_minor candidate_patch
	local installed_major installed_minor installed_patch
	IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$1"
	IFS=. read -r installed_major installed_minor installed_patch <<< "$2"
	((
		candidate_major > installed_major
			|| (candidate_major == installed_major && candidate_minor > installed_minor)
			|| (candidate_major == installed_major && candidate_minor == installed_minor && candidate_patch > installed_patch)
	))
}

if ! version_is_newer "$feed_version" "$installed_version"; then
	echo "Feed version $feed_version is not newer than installed version $installed_version" >&2
	exit 1
fi

curl --fail --location --silent --show-error \
	--retry 5 --retry-delay 2 --retry-all-errors \
	"$archive_url" --output "$archive_path"

actual_length="$(stat -f%z "$archive_path")"
if [[ "$actual_length" != "$archive_length" ]]; then
	echo "Archive length mismatch: expected $archive_length, found $actual_length" >&2
	exit 1
fi

printf '302a300506032b6570032100' | xxd -r -p > "$temp_dir/public.der"
printf '%s' "$public_key" | base64 --decode >> "$temp_dir/public.der"
printf '%s' "$archive_signature" | base64 --decode > "$temp_dir/signature.bin"
openssl pkeyutl \
	-verify -rawin -pubin -keyform DER \
	-inkey "$temp_dir/public.der" \
	-sigfile "$temp_dir/signature.bin" \
	-in "$archive_path"

mkdir -p "$temp_dir/candidate"
ditto -x -k "$archive_path" "$temp_dir/candidate"
candidate_app="$temp_dir/candidate/ClipDown.app"
candidate_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate_app/Contents/Info.plist")"
if [[ "$candidate_version" != "$feed_version" ]]; then
	echo "Archive version $candidate_version does not match appcast version $feed_version" >&2
	exit 1
fi

codesign --verify --deep --strict --verbose=2 "$candidate_app"
spctl --assess --type execute --verbose=2 "$candidate_app"
xcrun stapler validate "$candidate_app"

echo "Sparkle update verified: ClipDown $installed_version -> $feed_version"
