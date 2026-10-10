#!/bin/sh
set -e
build_root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
DQ_BUILD_ROOT=$build_root
if command -v cygpath >/dev/null 2>&1; then
  DQ_BUILD_ROOT=$(cygpath -m "$build_root")
fi
export DQ_BUILD_ROOT
export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
exec "$build_root/tools/bootstrap/javascript.sh" "$build_root/tools/build/build.ts" "$@"
