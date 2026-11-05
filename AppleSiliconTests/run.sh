#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ "$(grep -c 'ARCHS = arm64;' MTMR.xcodeproj/project.pbxproj)" == 2 ]]
if grep -q 'ARCHS = "arm64 x86_64";' MTMR.xcodeproj/project.pbxproj; then exit 1; fi
if ARCHS=x86_64 sh ScriptWorker/build.sh >/dev/null 2>&1; then echo 'Worker accepted Intel architecture' >&2; exit 1; fi
if ARCHS=x86_64 sh MediaAssets/build.sh >/dev/null 2>&1; then echo 'Media helpers accepted Intel architecture' >&2; exit 1; fi
if grep -q 'scp ' build.sh || [[ -f .github/workflows/publish.yml ]]; then echo 'Legacy publishing route remains' >&2; exit 1; fi
workdir=$(mktemp -d "${TMPDIR:-/tmp}/mtmr-arm-test.XXXXXXXX")
trap 'rm -rf "$workdir"' EXIT
ditto Sparkle.framework "$workdir/Sparkle.framework"
./scripts/thin-sparkle-arm64.sh "$workdir/Sparkle.framework" "$workdir"
count=0
while IFS= read -r -d '' file; do
  if archs=$(xcrun lipo -archs "$file" 2>/dev/null); then
    [[ "$archs" == arm64 ]] || { echo 'Non-ARM Sparkle component found' >&2; exit 1; }
    count=$((count + 1))
  fi
done < <(find "$workdir/Sparkle.framework/Versions" -type f -print0)
[[ $count -ge 5 ]]
# Thinning a staging copy must not mutate the checked-in framework.
xcrun lipo Sparkle.framework/Sparkle -verify_arch arm64
xcrun lipo Sparkle.framework/Sparkle -verify_arch x86_64
if [[ $# == 1 ]]; then
  app="$1"
  for file in "$app/Contents/MacOS/MTMR" "$app/Contents/Helpers/MTMRScriptWorker" "$app/Contents/Helpers/graph" "$app/Contents/Helpers/artwork-worker"; do
    [[ -f "$file" && "$(xcrun lipo -archs "$file")" == arm64 ]] || { printf 'Not arm64-only: %s\n' "$file" >&2; exit 1; }
  done
fi
printf 'Apple Silicon configuration and staged Sparkle tests passed (%s Mach-O files)\n' "$count"
