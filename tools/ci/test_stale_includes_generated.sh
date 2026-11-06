#!/usr/bin/env bash
# dq_drop_stale_includes drops an include whose file is gone, but never a gitignored generated include (it is absent until its generator runs).
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tmp" && git init -q && git config user.email t@t && git config user.name t && mkdir -p code tools/ci
  echo '/tools/ci/generated/' >.gitignore; echo x >code/here.dm
  printf '#include "code\\here.dm"\n#include "code\\gone.dm"\n#include "tools\\ci\\generated\\doc_snippets.dm"\n' >d.dme
  git add -A; git commit -qm i ) >/dev/null 2>&1
. "$here/tools/dq_stale_includes.sh"
( cd "$tmp" && dq_drop_stale_includes d.dme . test ) >"$tmp/out" 2>&1
grep -q 'code.gone.dm' "$tmp/d.dme" && bad "a missing tracked-path include is still dropped" || ok "a missing include is dropped"
grep -q 'generated.doc_snippets.dm' "$tmp/d.dme" && ok "a gitignored generated include is kept" || bad "the generated include was dropped"
grep -q 'code.here.dm' "$tmp/d.dme" && ok "an existing include stays" || bad "an existing include was dropped"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
