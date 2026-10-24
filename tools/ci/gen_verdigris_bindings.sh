#!/bin/bash
# Writes the generated Verdigris bindings (code/__defines/verdigris/_bindings.dm, _bindings_types.dm and
# verdigris/ffi/src/abi.rs) from the #[auxmacros::bind] functions in verdigris/. They are build output and
# not committed; run this before any direct `cargo` use or DM compile outside build.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
if command -v bun >/dev/null 2>&1; then
	exec bun tools/build/lib/verdigris_bindings.ts
fi
exec tools/bootstrap/javascript.sh tools/build/lib/verdigris_bindings.ts
