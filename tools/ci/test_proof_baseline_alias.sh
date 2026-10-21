#!/usr/bin/env bash
# Test for proof_alias_baseline_shrink() (tools/dq_proof_cache.sh): a proof stored under the baseline-shrunk tree also covers the unshrunk tree a
# plain merge makes, so dq_land does not prove the lane again; any other difference gets no alias.
#   bash tools/ci/test_proof_baseline_alias.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
ok() { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
export DQ_PROOF_DIR="$T/proofs"
. "$ROOT/tools/dq_proof_cache.sh"
cd "$T" && git init -q repo && cd repo && git config user.email t@t && git config user.name t
mkdir -p tools/ci && echo a >tools/ci/x_baseline.txt && echo a >a.txt && git add -A && git commit -q -m one
unshrunk="$(proof_tree HEAD)"
echo b >tools/ci/x_baseline.txt && git commit -q -am shrink
shrunk="$(proof_tree HEAD)"
echo c >a.txt && git commit -q -am code
other="$(proof_tree HEAD)"
proof_store "$shrunk" m "t1" 1 0 0 0 0 ""
proof_store "$other" m "t1" 1 0 0 0 0 ""

proof_alias_baseline_shrink "$unshrunk" "$shrunk"
[ -f "$DQ_PROOF_DIR/$unshrunk.proof" ] && grep -q "^tree=$unshrunk" "$DQ_PROOF_DIR/$unshrunk.proof" && ok "baseline-only difference: the unshrunk tree is covered" || fail "no alias for a baseline-only shrink"
rm -f "$DQ_PROOF_DIR/$unshrunk.proof"
proof_alias_baseline_shrink "$unshrunk" "$other"
[ ! -f "$DQ_PROOF_DIR/$unshrunk.proof" ] && ok "a code difference gets no alias" || fail "aliased across a non-baseline change"
proof_alias_baseline_shrink "$shrunk" "$shrunk"
ok "same tree is a no-op"
[ "$fails" -eq 0 ] && echo "test_proof_baseline_alias: all passed" || { echo "test_proof_baseline_alias: FAILED"; exit 1; }
