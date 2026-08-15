#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$repo_root"

bin_path="$(swift build --package-path "$repo_root" --show-bin-path)"
app_path="$bin_path/iPhone Dedupe.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$bin_path/iPhoneDedupeApp" "$contents_path/MacOS/iPhoneDedupeApp"
cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
cp "$repo_root/Packaging/PrivacyInfo.xcprivacy" "$contents_path/Resources/PrivacyInfo.xcprivacy"
codesign --force --options runtime --sign - "$app_path"

print -r -- "$app_path"
