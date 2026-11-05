#!/bin/sh
set -eu
# This fork supports Apple Silicon only; fail rather than silently ship Intel code.
for arch in ${ARCHS:-}; do
  [ "$arch" = arm64 ] || { printf 'Only arm64 is supported (got %s)\n' "$arch" >&2; exit 1; }
done
out="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers/MTMRScriptWorker"
mkdir -p "$(dirname "$out")" "${DERIVED_FILE_DIR}/mtmr-workers"
set --
for arch in ${ARCHS}; do
  part="${DERIVED_FILE_DIR}/mtmr-workers/worker-${arch}"
  xcrun swiftc -module-cache-path "${DERIVED_FILE_DIR}/mtmr-workers/cache" -swift-version 5 -target "${arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET}" -sdk "${SDKROOT}" "${SRCROOT}/ScriptWorker/main.swift" -o "$part"
  set -- "$@" "$part"
done
xcrun lipo -create "$@" -output "$out"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$out"
fi
