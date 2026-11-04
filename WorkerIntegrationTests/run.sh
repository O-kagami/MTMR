#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mtmr-workers.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/cache"
for name in FakeWorker BlockWorker CloseInputWorker; do
 xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" "WorkerIntegrationTests/$name.swift" -o "$test_dir/$name"
done
xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" MTMR/WorkerSession.swift WorkerIntegrationTests/Stubs.swift WorkerIntegrationTests/main.swift -o "$test_dir/tests"
"$test_dir/tests" "${1:?pass built worker path}" "$test_dir/FakeWorker" "$test_dir/BlockWorker" "$test_dir/CloseInputWorker"
