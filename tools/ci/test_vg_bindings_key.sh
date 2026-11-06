#!/usr/bin/env bash
# A new .dm file does not regenerate the verdigris bindings (the file list left the check's key on 1 November); a Rust change is still in the key.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
probe=code/zz_vg_key_probe.dm
trap 'rm -f code/zz_vg_key_probe.dm' EXIT
fail=0
tools/build/build.sh verdigris-bindings-check >/dev/null 2>&1
echo "// probe" >"$probe"
out="$(tools/build/build.sh verdigris-bindings-check 2>&1)"
grep -q 'inputs unchanged since the last passing check' <<<"$out" && echo "PASS: a new .dm file keeps the check skipped" || { echo "FAIL: a new .dm file regenerated the bindings"; fail=1; }
grep -q "walk('verdigris', (n) => n.endsWith('.rs')" tools/build/build.ts && echo "PASS: the Rust sources stay in the key" || { echo "FAIL: Rust sources left the key"; fail=1; }
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
