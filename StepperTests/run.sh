#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/cache" MTMR/Widgets/BrightnessStepper.swift StepperTests/main.swift -o StepperTests/run-tests
StepperTests/run-tests
