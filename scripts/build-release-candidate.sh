#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
signing_identity="${IMAGE_DEDUPE_SIGNING_IDENTITY:-}"
allow_adhoc="${IMAGE_DEDUPE_ALLOW_ADHOC:-0}"

if [[ -z "$signing_identity" ]]; then
    [[ "$allow_adhoc" == "1" ]] || {
        print -u2 "release build refused: set IMAGE_DEDUPE_SIGNING_IDENTITY, or explicitly set IMAGE_DEDUPE_ALLOW_ADHOC=1 for a local non-distributable candidate"
        exit 1
    }
    signing_identity="-"
fi

bin_path="$(swift build --package-path "$repo_root" -c release --show-bin-path)"
app_path="$bin_path/Image Dedupe.app"
contents_path="$app_path/Contents"
"$repo_root/scripts/refuse-running-bundle.sh" "$contents_path/MacOS/ImageDedupeApp"

swift build --package-path "$repo_root" -c release

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$bin_path/ImageDedupeApp" "$contents_path/MacOS/ImageDedupeApp"
# The device helper ships beside the app executable. Scanning *is* a helper process, so a
# bundle without this binary fails every scan — which is what a release candidate did until
# 2026-08-16, because only the debug script was updated when the helper was introduced.
cp "$bin_path/ImageDedupeHelper" "$contents_path/MacOS/ImageDedupeHelper"
cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Packaging/PrivacyInfo.xcprivacy" "$contents_path/Resources/PrivacyInfo.xcprivacy"

# Nested code must be signed before the bundle that contains it: signing the outer bundle
# seals the helper's signature, so the reverse order invalidates the app.
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --options runtime --sign - "$contents_path/MacOS/ImageDedupeHelper"
    codesign --force --options runtime --sign - "$app_path"
    "$repo_root/scripts/verify-release.sh" "$app_path" --allow-adhoc
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$contents_path/MacOS/ImageDedupeHelper"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
    "$repo_root/scripts/verify-release.sh" "$app_path"
fi

print -r -- "$app_path"
