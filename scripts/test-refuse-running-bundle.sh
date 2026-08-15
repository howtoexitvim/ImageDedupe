#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
guard="$repo_root/scripts/refuse-running-bundle.sh"
mock_path="$repo_root/scripts/test-fixtures:$PATH"
test_executable="/tmp/Image Dedupe.app/Contents/MacOS/ImageDedupeApp"

IMAGE_DEDUPE_TEST_PROCESS="/Applications/Other.app/Contents/MacOS/Other" \
    PATH="$mock_path" "$guard" "$test_executable"

if IMAGE_DEDUPE_TEST_PROCESS="$test_executable --test-argument" \
    PATH="$mock_path" "$guard" "$test_executable"; then
    print -u2 "expected a running bundle to be rejected"
    exit 1
fi

print -r -- "running-bundle guard passed"
