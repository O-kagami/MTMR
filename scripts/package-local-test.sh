#!/bin/bash
# Creates a local, unsigned-for-distribution trial package. Does not install it.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s /absolute/path/to/new-output-directory\n' "$0" >&2
  exit 2
fi
case "$1" in /*) output="$1" ;; *) printf 'Output path must be absolute.\n' >&2; exit 2 ;; esac
if [[ -e "$output" || -L "$output" ]]; then
  printf 'Output already exists; choose a new path.\n' >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd -P)"
# Do not distribute an upstream feed that can replace this fork.
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$root/MTMR/Info.plist" >/dev/null 2>&1; then
  printf 'Remove the upstream update feed before packaging this fork.\n' >&2
  exit 2
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
bundle_id="${MTMR_TEST_BUNDLE_ID:-com.github.O-kagami.MTMR}"
case "$bundle_id" in *[!A-Za-z0-9.-]*|'') printf 'Invalid bundle identifier.\n' >&2; exit 2 ;; esac
scratch="$(mktemp -d "${TMPDIR:-/tmp}/mtmr-package.XXXXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/stage"
xcodebuild -project "$root/MTMR.xcodeproj" -scheme MTMR -configuration Release \
  -derivedDataPath "$scratch/build" ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" build >"$scratch/build.log" 2>&1 || {
    tail -n 60 "$scratch/build.log" >&2
    exit 1
  }
app="$scratch/stage/MTMR.app"
ditto "$scratch/build/Build/Products/Release/MTMR.app" "$app"
# Thin the staged copy, including nested Sparkle executables, before signing.
"$root/scripts/thin-sparkle-arm64.sh" "$app/Contents/Frameworks/Sparkle.framework" "$scratch"
# Remove debug-map paths from the distributed executable before signing.
/usr/bin/strip -S "$app/Contents/MacOS/MTMR"
/usr/bin/strip -S "$app/Contents/MacOS/TouchBarBrightnessHelper"
# Reject an accidentally embedded local home path instead of packaging it.
if [[ -n "${HOME:-}" && "$HOME" != / ]]; then
  while IFS= read -r -d '' file; do
    if LC_ALL=C grep -aFq -- "$HOME/" "$file"; then
      printf 'Local home path embedded in build: %s\n' "${file#"$app"/}" >&2
      exit 1
    fi
  done < <(find "$app/Contents" -type f -print0)
fi
brightness="$app/Contents/MacOS/TouchBarBrightnessHelper"
worker="$app/Contents/Helpers/MTMRScriptWorker"
graph="$app/Contents/Helpers/graph"
artwork="$app/Contents/Helpers/artwork-worker"
for file in "$app/Contents/MacOS/MTMR" "$brightness" "$worker" "$graph" "$artwork" "$app/Contents/Frameworks/Sparkle.framework/Sparkle"; do
  [[ -f "$file" ]] || { printf 'Missing required executable: %s\n' "$file" >&2; exit 1; }
  xcrun lipo "$file" -verify_arch arm64
  [[ "$(xcrun lipo -archs "$file")" == arm64 ]] || { printf 'Unexpected non-ARM architecture: %s\n' "$file" >&2; exit 1; }
done
# Verify the Sparkle nested executables as well as the framework itself.
while IFS= read -r -d '' file; do
  if archs=$(xcrun lipo -archs "$file" 2>/dev/null); then
    [[ "$archs" == arm64 ]] || { printf 'Unexpected Sparkle architecture: %s\n' "$file" >&2; exit 1; }
  fi
done < <(find "$app/Contents/Frameworks/Sparkle.framework/Versions" -type f -print0)
# Ad-hoc signing provides integrity for this local test only. It is not Developer ID.
for helper in "$brightness" "$worker" "$graph" "$artwork"; do codesign --force --sign - "$helper"; done
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
for helper in "$brightness" "$worker" "$graph" "$artwork"; do codesign --verify --strict "$helper"; done
cat > "$scratch/stage/README-UNNOTARIZED.txt" <<'NOTE'
LOCAL TEST BUILD — NOT A RELEASE

Apple Silicon (arm64) only. Intel Macs are not supported.

This build uses an ad-hoc signature. It has not been signed with Developer ID
or notarized by Apple and is not a verified public distribution. macOS can
refuse to open it on other Macs. Do not bypass system security to install it.

The existing MTMR settings are shared; back them up before testing and avoid
running two Touch Bar managers simultaneously. Some widgets require their own
support files and permissions. Automatic updates for this fork are not set up;
the update menu opens the fork's GitHub releases page. Availability and all
features require separate validation on a real Mac.
NOTE
ln -s /Applications "$scratch/stage/Applications"
mkdir -p "$(dirname "$output")"
mkdir "$output"
if ! hdiutil create -quiet -fs HFS+ -format UDZO -srcfolder "$scratch/stage" \
  -volname 'MTMR Local Test' "$output/MTMR-UNNOTARIZED.dmg"; then
  rmdir "$output" 2>/dev/null || true
  exit 1
fi
cp "$scratch/stage/README-UNNOTARIZED.txt" "$output/"
(cd "$output" && shasum -a 256 MTMR-UNNOTARIZED.dmg > SHA256SUMS.txt)
printf 'Local test package: %s\n' "$output/MTMR-UNNOTARIZED.dmg"
printf 'Not notarized; not a verified public distribution.\n'
