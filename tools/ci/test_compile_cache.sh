#!/bin/bash
# Proves the test-build compile key (tools/build/lib/compile_hash.ts) changes when a .dm source or a
# FILE_DIR resource changes, and not otherwise. Touches scratch copies only, never tracked files.
set -euo pipefail
cd "$(dirname "$0")/../.."
H() { bun tools/build/lib/compile_hash.ts deepquarry.dme TESTING; }
DM=$(grep -o '#include "code\\datums[^"]*[.]dm"' deepquarry.dme | head -1 | sed 's/#include "//; s/"$//' | tr '\\\\' '/')
RES=sound/_dq_cache_test_resource.ogg
fail() { echo "FAIL: $1"; exit 1; }
cleanup() { rm -f "$RES"; [ -n "${DMBAK:-}" ] && cp "$DMBAK" "$DM" && touch "$DM" || true; rm -f "${DMBAK:-}"; }
trap cleanup EXIT
base=$(H); [ "$base" = "$(H)" ] || fail "hash not stable on an unchanged tree"
DMBAK=$(mktemp); cp "$DM" "$DMBAK"
echo "// cache test" >> "$DM"
[ "$base" != "$(H)" ] || fail ".dm edit did not change the key"
cp "$DMBAK" "$DM"; touch "$DM"
echo x > "$RES"; withres=$(H)
[ "$base" != "$withres" ] || fail "added resource did not change the key"
echo y >> "$RES"
[ "$withres" != "$(H)" ] || fail "edited resource did not change the key"
echo "PASS: .dm and resource changes invalidate the compile cache key"
