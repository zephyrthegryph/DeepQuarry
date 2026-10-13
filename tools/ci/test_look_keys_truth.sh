#!/usr/bin/env bash
# look_keys.txt records only keys a pin run probed. This builds a scratch repo with the real script and drives the cases that used to
# mark unverified types verified: a regeneration (gone), a union merge where a type's look changed in one branch, and a conflict.
# A fake analyzer plan (DQ_LOOK_PLAN_FILE) stands in for `analyze look-keys`.
set -euo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; work="$tmp/repo"; mkdir "$work"
trap 'rm -rf "$tmp"' EXIT
cd "$work"
git init -q -b master .
git config user.email t@t; git config user.name t
mkdir -p tools/ci code/modules/unit_tests/snapshots data
cp "$here/tools/ci/check_look_keys_format.sh" tools/ci/
K=code/modules/unit_tests/snapshots/look_keys.txt
printf '%s\n' "$K merge=union" >.gitattributes
S="bash tools/ci/check_look_keys_format.sh"
tab=$'\t'
row() { printf '/obj/%s%s%016x%s*\n' "$1" "$tab" "$2" "$tab"; }
plan() { : >"$tmp/plan.tsv"; for kv in "$@"; do row "${kv%%=*}" "${kv##*=}" >>"$tmp/plan.tsv"; done; export DQ_LOOK_PLAN_FILE="$tmp/plan.tsv"; }
fail() { echo "test_look_keys_truth: FAIL: $*" >&2; exit 1; }
unv() { $S --diff "$tmp/plan.tsv" | tr '\n' ' '; }

# base: three types verified.
plan a=1 b=2 c=3
{ row a 1; row b 2; row c 3; } >"$K"
git add -A; git commit -q -m base
$S >/dev/null || fail "format check on a good file"
[ -z "$(unv)" ] || fail "fresh file has unverified types: $(unv)"

# 1. the analyzer moves b, c: the file is untouched by --normalize, they are unverified.
plan a=1 b=22 c=33
$S --normalize >/dev/null
[ "$(unv)" = "/obj/b /obj/c " ] || fail "moved types must be unverified, got: $(unv)"
grep -q "$(printf '/obj/b\t0000000000000002')" "$K" || fail "normalize must not change b's key"
$S >/dev/null || fail "a stale (but well-formed) file must pass the format check"

# 2. record after a pin run that probed only b: b verified, c still not, nothing else touched.
printf '/obj/b\n' >"$tmp/probed.txt"
$S --record "$tmp/plan.tsv" "$tmp/probed.txt" >/dev/null
[ "$(unv)" = "/obj/c " ] || fail "after probing b only, c must stay unverified, got: $(unv)"
git add -A; git commit -q -m "b probed"

# 3. simulated merge: branch L changes and verifies type a (a=1 -> 7); master changes and verifies type c (c=33 -> 44).
git branch lane
plan a=1 b=22 c=44
printf '/obj/c\n' >"$tmp/probed.txt"; $S --record "$tmp/plan.tsv" "$tmp/probed.txt" >/dev/null
git add -A; git commit -q -m "master: c verified at 44"
git switch -q lane
plan a=7 b=22 c=33
printf '/obj/a\n' >"$tmp/probed.txt"; $S --record "$tmp/plan.tsv" "$tmp/probed.txt" >/dev/null
git add -A; git commit -q -m "lane: a verified at 7"
git switch -q master
git merge -q --no-edit lane || fail "the union merge must not conflict"
plan a=7 b=22 c=44            # the merged tree: both changes present
$S --normalize >/dev/null
[ -z "$(unv)" ] || fail "both sides' verified rows survive the merge, unverified: $(unv)"

# 4. the merged tree's key for c differs from both sides (the lane touched code c's look reads): c is unverified, a stays verified.
plan a=7 b=22 c=55
$S --normalize >/dev/null
[ "$(unv)" = "/obj/c " ] || fail "a type whose merged key matches no recorded row must be unverified, got: $(unv)"

# 5. both branches verified the same type at different keys: the union holds both rows; none matches -> dropped, probed next.
{ row a 7; row b 22; row c 44; row c 66; } >"$K"
plan a=7 b=22 c=77
$S >/dev/null 2>&1 && fail "a type with two rows must fail the format check"
$S --normalize >/dev/null
$S >/dev/null || fail "normalize must leave a well-formed file"
[ "$(unv)" = "/obj/c " ] || fail "ambiguous rows must leave the type unverified, got: $(unv)"
[ "$(grep -c '^/obj/c' "$K")" = "0" ] || fail "ambiguous rows must be dropped"
# ...and when one of the two rows is the tree's current key it is the verified one.
{ row a 7; row b 22; row c 44; row c 66; } >"$K"
plan a=7 b=22 c=66
$S --normalize >/dev/null
[ -z "$(unv)" ] || fail "the row equal to the current key is verified, unverified: $(unv)"
[ "$(grep -c '^/obj/c' "$K")" = "1" ] || fail "one row for c must remain"

# 6. a type gone from the tree is dropped; a type new to the tree is unverified; --commit commits only when the file changed.
plan a=7 b=22 c=66 d=9
{ row a 7; row b 22; row c 66; row z 5; } >"$K"
git add -A; git commit -q -m pre
$S --commit >/dev/null
[ "$(unv)" = "/obj/d " ] || fail "new type must be unverified, got: $(unv)"
grep -q '/obj/z' "$K" && fail "a type gone from the tree must be dropped"
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "--commit must commit its change"

# 7. --record with no probed list (a full run) records every plan type.
$S --record "$tmp/plan.tsv" >/dev/null
[ -z "$(unv)" ] || fail "a full run verifies every type"
# 8. --regen is refused.
$S --regen >/dev/null 2>&1 && fail "--regen must be refused"
echo "test_look_keys_truth: PASS"
