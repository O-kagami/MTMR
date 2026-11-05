#!/bin/bash
# Legacy upstream build.sh uploaded releases to an external server. This fork
# only builds a local, explicitly named test package; it never publishes.
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd -P)"
exec "$root/scripts/package-local-test.sh" "$@"
