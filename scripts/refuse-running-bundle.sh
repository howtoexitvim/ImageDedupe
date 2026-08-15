#!/bin/zsh

set -euo pipefail

[[ $# -eq 1 ]] || {
    print -u2 "usage: $0 /absolute/path/to/app/executable"
    exit 2
}

executable_path="$1"
if ps -axww -o command= | awk -v executable="$executable_path" '
    $0 == executable || index($0, executable " ") == 1 { found = 1 }
    END { exit(found ? 0 : 1) }
'; then
    print -u2 "build refused: $executable_path is currently running"
    print -u2 "quit the app before replacing or re-signing its bundle"
    exit 1
fi
