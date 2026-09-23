#!/bin/bash
# Fails when code/__defines/verdigris/_bindings.dm or verdigris/ffi/src/abi.rs
# is stale relative to the #[auxmacros::bind] functions in verdigris/.
# Fix: tools/build/build.sh verdigris-bindings, then commit the result.
set -euo pipefail
cd "$(dirname "$0")/../.."
if command -v bun >/dev/null 2>&1; then
	exec bun tools/build/lib/verdigris_bindings.ts --check
fi
exec tools/bootstrap/javascript.sh tools/build/lib/verdigris_bindings.ts --check
