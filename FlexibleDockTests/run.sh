#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
xcrun swiftc -module-cache-path "$workdir/cache" MTMR/Widgets/FlexibleDockLayout.swift FlexibleDockTests/main.swift -o "$workdir/test"
"$workdir/test"
