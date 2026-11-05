#!/bin/sh
set -eu
: "${SRCROOT:?}" "${BUILT_PRODUCTS_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${DERIVED_FILE_DIR:?}"
mkdir -p "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS" "${DERIVED_FILE_DIR}/touchbar-helper-cache"
/usr/bin/xcrun swiftc -target arm64-apple-macos12.0 -sdk "${SDKROOT}" \
  -module-cache-path "${DERIVED_FILE_DIR}/touchbar-helper-cache" \
  "${SRCROOT}/TouchBarHelper/TouchBarBrightnessSession.swift" \
  "${SRCROOT}/TouchBarHelper/TouchBarBrightnessDevice.swift" \
  "${SRCROOT}/TouchBarHelper/ParentWatcher.swift" \
  "${SRCROOT}/TouchBarHelper/main.swift" \
  -o "${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/TouchBarBrightnessHelper"
