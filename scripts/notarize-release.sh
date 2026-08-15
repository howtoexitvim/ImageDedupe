#!/bin/zsh

set -euo pipefail

if (( $# != 1 )); then
    print -u2 "usage: notarize-release.sh /path/to/iPhone\\ Dedupe.app"
    exit 64
fi

app_path="$1"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${IPHONE_DEDUPE_SIGNING_IDENTITY:?Set IPHONE_DEDUPE_SIGNING_IDENTITY to a Developer ID Application identity}"
: "${IPHONE_DEDUPE_NOTARY_PROFILE:?Set IPHONE_DEDUPE_NOTARY_PROFILE to an existing notarytool keychain profile}"

[[ "$IPHONE_DEDUPE_SIGNING_IDENTITY" != "-" ]] || {
    print -u2 "notarization refused: an ad-hoc identity cannot be notarized"
    exit 1
}

"$repo_root/scripts/verify-release.sh" "$app_path"
codesign_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
print -r -- "$codesign_details" | grep -q 'Authority=Developer ID Application:' || {
    print -u2 "notarization refused: bundle is not signed with Developer ID Application"
    exit 1
}

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/image-dedupe-notary.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT
archive_path="$temporary_directory/iPhone-Dedupe.zip"
result_path="$temporary_directory/notary-result.json"

ditto -c -k --keepParent "$app_path" "$archive_path"
if ! xcrun notarytool submit "$archive_path" \
    --keychain-profile "$IPHONE_DEDUPE_NOTARY_PROFILE" \
    --wait \
    --output-format json >"$result_path"; then
    submission_id="$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" --keychain-profile "$IPHONE_DEDUPE_NOTARY_PROFILE" || true
    fi
    print -u2 "notarization failed"
    exit 1
fi

notarization_status="$(plutil -extract status raw -o - "$result_path")"
[[ "$notarization_status" == "Accepted" ]] || {
    submission_id="$(plutil -extract id raw -o - "$result_path")"
    xcrun notarytool log "$submission_id" --keychain-profile "$IPHONE_DEDUPE_NOTARY_PROFILE" || true
    print -u2 "notarization was not accepted: $notarization_status"
    exit 1
}

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
