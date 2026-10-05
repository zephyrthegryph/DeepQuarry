#!/bin/sh
set -e
cd "$(dirname "$0")"
# Build exactly this checkout: pin the root from the script's own location and
# disable Bun's shared transpiler cache (it can cross worktrees; see build.ts).
DQ_BUILD_ROOT="$(git -C ../.. rev-parse --show-toplevel 2>/dev/null || (cd ../.. && pwd))"
export DQ_BUILD_ROOT
export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
exec ../bootstrap/javascript.sh build.ts "$@"
