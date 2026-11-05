#!/bin/bash
# Thin only a staged Sparkle.framework copy, before it is signed.
set -euo pipefail
if [[ $# -ne 2 || ! -d "$1/Versions" || ! -d "$2" ]]; then
  printf 'Usage: %s /path/to/staged/Sparkle.framework /path/to/scratch-directory\n' "$0" >&2
  exit 2
fi
framework="$1"
scratch="$2"
while IFS= read -r -d '' file; do
  if archs=$(xcrun lipo -archs "$file" 2>/dev/null); then
    xcrun lipo "$file" -verify_arch arm64
    if [[ "$archs" != arm64 ]]; then
      thin="$scratch/sparkle-arm64-thin"
      xcrun lipo "$file" -thin arm64 -output "$thin"
      cat "$thin" > "$file"
      rm -f "$thin"
    fi
    [[ "$(xcrun lipo -archs "$file")" == arm64 ]] || exit 1
  fi
done < <(find "$framework/Versions" -type f -print0)
