#!/bin/zsh

set -euo pipefail

if (( $# < 1 || $# > 2 )); then
    print -u2 "usage: verify-release.sh /path/to/iPhone\\ Dedupe.app [--allow-adhoc]"
    exit 64
fi

app_path="$1"
allow_adhoc="${2:-}"
contents_path="$app_path/Contents"
executable="$contents_path/MacOS/iPhoneDedupeApp"
manifest="$contents_path/Resources/PrivacyInfo.xcprivacy"

[[ -d "$app_path" && -f "$executable" && -f "$manifest" ]] || {
    print -u2 "release verification failed: incomplete app bundle"
    exit 1
}

plutil -lint "$contents_path/Info.plist" "$manifest" >/dev/null
codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details="$(codesign -d --verbose=4 "$app_path" 2>&1)"
print -r -- "$signature_details" | grep -q 'flags=.*runtime' || {
    print -u2 "release verification failed: Hardened Runtime flag is absent"
    exit 1
}

if ! entitlements="$(codesign -d --entitlements - "$app_path" 2>&1)"; then
    print -u2 "release verification failed: entitlements could not be inspected"
    exit 1
fi
print -r -- "$entitlements" | grep -Eq 'com\.apple\.security\.cs\.(allow-jit|allow-unsigned-executable-memory|disable-library-validation|disable-executable-page-protection|allow-dyld-environment-variables|debugger)' && {
    print -u2 "release verification failed: a Hardened Runtime exception entitlement is present"
    exit 1
}

executable_count="$(find "$contents_path/MacOS" -type f -perm -111 | wc -l | tr -d ' ')"
[[ "$executable_count" == "1" ]] || {
    print -u2 "release verification failed: unexpected executable count $executable_count"
    exit 1
}

tracking="$(plutil -extract NSPrivacyTracking raw -o - "$manifest")"
[[ "$tracking" == "false" ]] || {
    print -u2 "release verification failed: privacy manifest enables tracking"
    exit 1
}

if print -r -- "$signature_details" | grep -q '^Signature=adhoc$'; then
    [[ "$allow_adhoc" == "--allow-adhoc" ]] || {
        print -u2 "release verification failed: ad-hoc signatures are not distributable"
        exit 1
    }
    print -u2 "note: LOCAL NON-DISTRIBUTABLE ad-hoc Hardened Runtime candidate; notarization and clean-Mac Gatekeeper acceptance remain blocked"
else
    codesign --verify --deep --strict --verbose=2 "$app_path"
fi
