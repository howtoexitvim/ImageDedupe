#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
bin_path="$(swift build --package-path "$repo_root" --show-bin-path)"
app_path="$bin_path/Image Dedupe.app"
contents_path="$app_path/Contents"
"$repo_root/scripts/refuse-running-bundle.sh" "$contents_path/MacOS/ImageDedupeApp"

swift build --package-path "$repo_root"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$bin_path/ImageDedupeApp" "$contents_path/MacOS/ImageDedupeApp"
# The device helper ships beside the app executable. Each scan runs a fresh copy of it,
# because ImageCaptureCore only ever enumerates a device once per process; without this
# binary present, scanning cannot see changes made since launch.
cp "$bin_path/ImageDedupeHelper" "$contents_path/MacOS/ImageDedupeHelper"
cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Packaging/PrivacyInfo.xcprivacy" "$contents_path/Resources/PrivacyInfo.xcprivacy"
# Nested code must be signed before the bundle that contains it: signing the outer bundle
# seals the helper's signature, so signing them in the other order invalidates the app.
codesign --force --options runtime --sign - "$contents_path/MacOS/ImageDedupeHelper"
codesign --force --options runtime --sign - "$app_path"

print -r -- "$app_path"
