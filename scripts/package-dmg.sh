#!/bin/zsh

set -euo pipefail

# Packages an already-built release candidate into a distributable disk image.
#
# This script deliberately does not build. It takes the app produced by
# build-release-candidate.sh so the artifact that ships is byte-identical to the
# one that passed verify-release.sh, rather than a second build that merely
# resembles it.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
allow_adhoc="${IMAGE_DEDUPE_ALLOW_ADHOC:-0}"

if (( $# > 1 )); then
    print -u2 "usage: package-dmg.sh [/path/to/Image\\ Dedupe.app]"
    exit 64
fi

if (( $# == 1 )); then
    app_path="$1"
else
    app_path="$(swift build --package-path "$repo_root" -c release --show-bin-path)/Image Dedupe.app"
fi

[[ -d "$app_path" ]] || {
    print -u2 "packaging refused: no app bundle at $app_path"
    print -u2 "build one first: ./scripts/build-release-candidate.sh"
    exit 1
}

# Re-verify here rather than trusting that the caller ran the builder. A disk image is
# the point where an unverified bundle stops being a local mistake and starts being a
# download, so the same gate that guards distribution has to guard the wrapper too.
if [[ "$allow_adhoc" == "1" ]]; then
    "$repo_root/scripts/verify-release.sh" "$app_path" --allow-adhoc
else
    "$repo_root/scripts/verify-release.sh" "$app_path"
fi

version="$(plutil -extract CFBundleShortVersionString raw -o - "$app_path/Contents/Info.plist")"
distribution_path="$repo_root/dist"
image_path="$distribution_path/Image-Dedupe-$version.dmg"

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/image-dedupe-dmg.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
staging_path="$staging_root/Image Dedupe"
mkdir -p "$staging_path"

# ditto preserves the signature; cp -R does not reliably preserve extended attributes on
# every filesystem, and a mangled signature only shows up on the user's Mac.
ditto "$app_path" "$staging_path/Image Dedupe.app"
ln -s /Applications "$staging_path/Applications"
find "$staging_path" -name '._*' -delete

mkdir -p "$distribution_path"
rm -f "$image_path"

hdiutil create \
    -volname "Image Dedupe" \
    -srcfolder "$staging_path" \
    -fs HFS+ \
    -format UDZO \
    -quiet \
    "$image_path"

# An unsigned disk image around a signed app still triggers a Gatekeeper prompt of its
# own, so sign the image whenever a real identity is available.
signing_identity="${IMAGE_DEDUPE_SIGNING_IDENTITY:-}"
if [[ -n "$signing_identity" && "$signing_identity" != "-" ]]; then
    codesign --force --timestamp --sign "$signing_identity" "$image_path"
    codesign --verify --strict --verbose=2 "$image_path"
else
    print -u2 "note: the disk image itself is unsigned; set IMAGE_DEDUPE_SIGNING_IDENTITY to sign it"
fi

hdiutil verify -quiet "$image_path"
print -r -- "$image_path"
