#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/mtmr-actions.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" WorkerIntegrationTests/FakeWorker.swift -o "$test_dir/worker"
xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/cache" MTMR/WorkerSession.swift WorkerIntegrationTests/Stubs.swift ActionRunnerTests/main.swift -o "$test_dir/tests"
"$test_dir/tests" "$test_dir/worker"
