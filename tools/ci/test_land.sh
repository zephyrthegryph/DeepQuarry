#!/usr/bin/env bash
# Self-test of tools/dq_land.sh on a scratch origin, including the real tools/hooks/pre-push.
set -uo pipefail
for _v in $(compgen -e | grep -E '^(DQ_|GIT_CONFIG_)'); do unset "$_v"; done; unset _v
unset MSYS_NO_PATHCONV
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
land="$here/tools/dq_land.sh"
export DQ_HEALTH_STATE="$tmp/h" DQ_HEALTH_CMD=true
git init -q --bare "$tmp/o.git"; git -C "$tmp/o.git" symbolic-ref HEAD refs/heads/master
mkdir -p "$tmp/lanes"; git init -q "$tmp/lanes/a"; cd "$tmp/lanes/a" || exit 1
git config user.email t@t; git config user.name t; git remote add origin "$tmp/o.git"
mkdir -p code; echo a >code/a.dm; echo b >code/b.dm; git add -A; git commit -qm init; git branch -M master; git push -q origin master; git fetch -q origin
cp "$here/tools/hooks/pre-push" .git/hooks/pre-push; chmod +x .git/hooks/pre-push
export DQ_LAND_LANE_ROOT="$(cd "$tmp/lanes" && pwd -W 2>/dev/null || pwd)"
master_moves() { git -C "$tmp/lanes/a" push -q origin "$(git -C "$tmp/lanes/a" commit-tree -p origin/master -m other "$(git -C "$tmp/lanes/a" rev-parse origin/master^{tree})"):refs/heads/master"; git fetch -q origin; }
lane() { git switch -qc "$1" origin/master; echo "$1" >>code/a.dm; git add -A; git commit -qm "$1"; }

lane l/plain; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && git merge-base --is-ancestor HEAD origin/master; then ok "a clean lane lands, through the real pre-push hook"; else bad "plain: rc=$rc $out"; fi
git fetch -q origin; git switch -qc l/moved origin/master; echo y >>code/b.dm; git commit -qam moved; master_moves; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && git merge-base --is-ancestor l/moved origin/master; then ok "master moved: it merges and lands"; else bad "moved: rc=$rc $out"; fi
# a lost race: the first push is refused by a hook that moves master just before it, once
git switch -qc l/race origin/master; echo y >>code/b.dm; git commit -qam race
printf '#!/usr/bin/env bash\n[ -f "%s/raced" ] && exit 0\n: >"%s/raced"\nsha="$(git commit-tree -p origin/master -m race "$(git rev-parse origin/master^{tree})")"\ngit push -q --no-verify origin "$sha:refs/heads/master"\nexit 1\n' "$tmp" "$tmp" >.git/hooks/pre-push
out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q 'round 2' <<<"$out"; then ok "a lost race merges and pushes again"; else bad "race: rc=$rc $out"; fi
cp "$here/tools/hooks/pre-push" .git/hooks/pre-push
git fetch -q origin; lane l/dirty; echo z >>code/b.dm; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'not clean' <<<"$out"; then ok "a dirty tree is refused"; else bad "dirty: rc=$rc $out"; fi
git add -A; git commit -qm tidy -q
git switch -qc l/saves origin/master; mkdir -p data/player_saves/a; echo s >data/player_saves/a/p.sav; git add -A -f; git commit -qm saves; before="$(git rev-parse origin/master)"; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'save data' <<<"$out" && [ "$(git rev-parse origin/master)" = "$before" ]; then ok "user save data is refused"; else bad "saves: rc=$rc $out"; fi
git switch -qc l/conflict origin/master; echo mine >code/b.dm; git commit -qam mine; git switch -qc l/other origin/master; echo theirs >code/b.dm; git commit -qam theirs; git push -q origin HEAD:refs/heads/master; git fetch -q origin; git switch -q l/conflict; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'merge conflict' <<<"$out"; then ok "a merge conflict is refused and left to resolve"; else bad "conflict: rc=$rc $out"; fi
echo mine >code/b.dm; git add -A; git commit -qm resolved; out="$(bash "$land" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "after resolving it lands" || bad "resolved: rc=$rc $out"
# a deepquarry.dme both sides edited at the same line merges through the dq-dme driver, not into a conflict
git fetch -q origin; git switch -qc l/dme-base origin/master; mkdir -p tools/build
cp "$here/tools/build/dme_merge_driver.sh" "$here/tools/build/gen_dme.py" tools/build/; printf "scan code\n" >tools/build/dme_spec.txt; cp "$here/.gitattributes" .gitattributes
printf '#include "code\\a.dm"\n#include "code\\b.dm"\n' >deepquarry.dme; echo c >code/c.dm; echo d >code/d.dm; git add -A; git commit -qm dme; bash "$land" >/dev/null 2>&1; git fetch -q origin
git switch -qc l/dme-theirs origin/master; printf '#include "code\\a.dm"\n#include "code\\c.dm"\n#include "code\\b.dm"\n' >deepquarry.dme; git commit -qam theirs; git push -q origin HEAD:master; git fetch -q origin
git switch -qc l/dme-mine HEAD~1; printf '#include "code\\a.dm"\n#include "code\\d.dm"\n#include "code\\b.dm"\n' >deepquarry.dme; git commit -qam mine; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && git show origin/master:deepquarry.dme | grep -q 'c\.dm' && git show origin/master:deepquarry.dme | grep -q 'd\.dm' && ! git show origin/master:deepquarry.dme | grep -q '<<<<'; then ok "a deepquarry.dme conflict resolves through the driver"; else bad "dme: rc=$rc $out"; fi
# a lane whose merged manifest is stale (an order gen_dme.py would not write) lands with it regenerated, never stale
git fetch -q origin; git switch -qc l/dme-stale origin/master; mkdir -p tools/build; cp "$here/tools/build/gen_dme.py" tools/build/; printf "scan code\n" >tools/build/dme_spec.txt; echo e >code/e.dm; printf '#include "code\\e.dm"\n#include "code\\a.dm"\n' >deepquarry.dme; git add -A; git commit -qm stale; out="$(bash "$land" 2>&1)"; rc=$?
want="$(python3 tools/build/gen_dme.py >/dev/null 2>&1; cat deepquarry.dme)"
if [ "$rc" = 0 ] && grep -q 'regenerated' <<<"$out" && [ "$(git show origin/master:deepquarry.dme)" = "$want" ] && [ -z "$(git status --porcelain)" ]; then ok "a stale manifest is regenerated and committed before the push"; else bad "stale dme: rc=$rc $out"; fi
git switch -q master; out="$(bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'on master' <<<"$out"; then ok "master itself is refused"; else bad "master: rc=$rc $out"; fi
git switch -q l/plain
out="$(DQ_LAND_LANE_ROOT=E:/nowhere bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'not under' <<<"$out"; then ok "a checkout outside the lanes (the main checkout) is refused"; else bad "non-lane: rc=$rc $out"; fi
git init -q "$tmp/lanes/test-server"; out="$(cd "$tmp/lanes/test-server" && bash "$land" 2>&1)"; rc=$?
if [ "$rc" != 0 ] && grep -q 'not a lane' <<<"$out"; then ok "test-server is refused"; else bad "test-server: rc=$rc $out"; fi
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
