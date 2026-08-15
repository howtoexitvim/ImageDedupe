#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
signing_identity="${IPHONE_DEDUPE_SIGNING_IDENTITY:-}"
allow_adhoc="${IPHONE_DEDUPE_ALLOW_ADHOC:-0}"

if [[ -z "$signing_identity" ]]; then
    [[ "$allow_adhoc" == "1" ]] || {
        print -u2 "release build refused: set IPHONE_DEDUPE_SIGNING_IDENTITY, or explicitly set IPHONE_DEDUPE_ALLOW_ADHOC=1 for a local non-distributable candidate"
        exit 1
    }
    signing_identity="-"
fi

swift build --package-path "$repo_root" -c release
bin_path="$(swift build --package-path "$repo_root" -c release --show-bin-path)"
app_path="$bin_path/iPhone Dedupe.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$bin_path/iPhoneDedupeApp" "$contents_path/MacOS/iPhoneDedupeApp"
cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Packaging/PrivacyInfo.xcprivacy" "$contents_path/Resources/PrivacyInfo.xcprivacy"

if [[ "$signing_identity" == "-" ]]; then
    codesign --force --options runtime --sign - "$app_path"
    "$repo_root/scripts/verify-release.sh" "$app_path" --allow-adhoc
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
    "$repo_root/scripts/verify-release.sh" "$app_path"
fi

print -r -- "$app_path"
