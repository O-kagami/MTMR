#!/bin/sh
# Xcode build phase. Artifacts are bundled; no user files are touched.
set -eu
: "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${DERIVED_FILE_DIR:?}" "${ARCHS:?}"
root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
resources="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Resources/ManagedMedia/v1"
helpers="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
tmp="${DERIVED_FILE_DIR}/managed-media"
mkdir -p "$resources/CPU-Memory" "$resources/SpotifyArtwork" "$helpers" "$tmp/cache"
for f in chart.applescript icon.applescript toggle.applescript cpu.png memory.png; do cp "$root/CPU-Memory/$f" "$resources/CPU-Memory/$f"; done
for f in artwork.applescript artwork-placeholder.png play-state.applescript toggle.applescript previous.applescript next.applescript play.png pause.png unavailable.png previous.png next.png; do cp "$root/SpotifyArtwork/$f" "$resources/SpotifyArtwork/$f"; done
sdk="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
for target in graph artwork-worker; do
  case "$target" in graph) src="$root/CPU-Memory/graph.swift" ;; artwork-worker) src="$root/SpotifyArtwork/artwork-fast.swift" ;; esac
  set --
  for arch in ${ARCHS}; do
    part="$tmp/$target-$arch"
    xcrun swiftc -swift-version 5 -module-cache-path "$tmp/cache" -sdk "$sdk" -target "${arch}-apple-macos${MACOSX_DEPLOYMENT_TARGET:-12.0}" -O "$src" -o "$part"
    set -- "$@" "$part"
  done
  xcrun lipo -create "$@" -output "$helpers/$target"
  if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$helpers/$target"
  fi
done
