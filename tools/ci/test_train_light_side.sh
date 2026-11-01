#!/usr/bin/env bash
# Light lanes landing beside a heavy gate (tools/dq_train.sh light_side) and the gate's push across them (tools/dq_push_master.sh DQ_PUSH_NEUTRAL_OK).
# The push runs the real dq_push_master.sh and dq_push_stamp.sh against a scratch origin; the compile and the ratchets are stubs that leave a mark.
#   bash tools/ci/test_train_light_side.sh
set -uo pipefail
for _v in $(compgen -e | grep -E '^(DQ_|GIT_CONFIG_)'); do unset "$_v"; done; unset _v
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }

# ---- which paths a gate does not read ------------------------------------------------------------------------------------------
. "$here/tools/dq_light_paths.sh"
for p in doc/a.md README.md html/changelogs/x.yml tools/dq_train.sh tools/train/a.py tools/ci/test_x.sh tools/hooks/pre-push; do
	light_gate_neutral "$p" && ok "neutral: $p" || bad "should be neutral: $p"
done
for p in code/a.dm maps/a.dmm deepquarry.dme tools/build/build.ts tools/dmb/crates/x/src/a.rs tools/analyze/src/a.rs verdigris/src/a.rs tools/ci/check_x.sh \
	tools/ci/lint_scopes.toml tools/ci/known_failures.txt tools/ci/smoke_tests.txt tools/ci/x_baseline.txt config/a.txt tools/other.py .github/x.yml; do
	light_gate_neutral "$p" && bad "should not be neutral: $p" || ok "not neutral: $p"
done

# ---- a scratch origin, and a gated commit with its stamps -------------------------------------------------------------------------
git init -q --bare "$tmp/origin.git"; git -C "$tmp/origin.git" symbolic-ref HEAD refs/heads/master
git init -q "$tmp/r"; cd "$tmp/r" || exit 1
git remote add origin "$tmp/origin.git"
git config user.email t@t; git config user.name t
mkdir -p tools/ci tools/build tools/analyze code/mod data doc
for f in dq_push_master.sh dq_push_stamp.sh dq_light_paths.sh dq_git_safe.sh dq_machine_slots.sh dq_lane_check.js; do cp "$here/tools/$f" tools/; done
printf '#!/usr/bin/env bash\ngit merge --no-edit -q origin/master\n' >tools/dq_merge_master.sh
printf '#!/usr/bin/env bash\nexit 0\n' >tools/dq_prebuild_tools.sh; cp tools/dq_prebuild_tools.sh tools/dq_worktree.sh
printf '#!/usr/bin/env bash\necho ratchets >>"$MARK"\n' >tools/ci/check_ratchets.sh
printf '#!/usr/bin/env bash\necho "build $*" >>"$MARK"\necho "deepquarry.dmb - 0 errors"\n' >tools/build/build.sh
echo 'tools/analyze/' >tools/ci/lane_ready_global.txt
printf 'data/\n' >.gitignore
echo a >code/mod/a.dm; echo x >tools/analyze/x.rs; echo d >doc/d.md; echo t >tools/dq_side.sh; echo c >tools/ci/test_c.sh
git add -A; git commit -qm init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
export MARK="$tmp/mark" DQ_MACHINE_SLOTS_DIR="$tmp/slots" DQ_SLOTS_DIR="$tmp/slots" DQ_PUSH_GC=0 DQ_MERGE_SESSION=test DQ_PUSH_STRICT=1 DQ_PUSH_NO_REPROOF=1 DQ_PUSH_NO_DREAMCHECKER=1

gated() { # <name> [file]: a lane merged onto origin/master at the moment the gate starts, stamped as the gates stamp it
	local b="$1" file="${2:-code/mod/a.dm}" sha short
	git switch -q -C "$b" origin/master; echo "$b" >>"$file"; git add -A; git commit -qm "$b"; git push -q origin "$b" 2>/dev/null
	git switch -q --detach origin/master; git merge --no-ff --no-edit -q "$b"
	sha="$(git rev-parse HEAD)"; short="${sha:0:12}"; mkdir -p data/merge-gates
	printf 'sha=%s\nbase_master=%s\nlane_tips=%s\n' "$sha" "$(git rev-parse origin/master)" "$(git rev-parse "$b")" >"data/merge-gates/$short.ok"
	echo "$sha" >"data/merge-gates/$short.ratchets.ok"; echo "$sha" >"data/merge-gates/$short.analyze.ok"; echo "$sha" >"data/merge-gates/$short.dm.ok"
	git notes --ref=merge-gates add -f -m "{\"ok\":true,\"commit\":\"$sha\",\"tests\":[]}" "$sha"
	GATED="$sha"
}
land_on_master() { # <file>: another process lands a change on origin/master while the gate runs
	local keep; keep="$(git rev-parse HEAD)"
	git switch -q --detach origin/master; echo more >>"$1"; git add -A; git commit -qm "landed beside the gate: $1"; git push -q origin HEAD:refs/heads/master 2>/dev/null
	git switch -q --detach "$keep"
}
push() { : >"$MARK"; out="$(DQ_PUSH_NEUTRAL_OK="${1:-1}" bash tools/dq_push_master.sh 2>&1)"; rc=$?; git fetch -q origin; }

gated lane/a; land_on_master doc/d.md; push
if [ "$rc" -eq 0 ] && git merge-base --is-ancestor "$GATED" origin/master && [ ! -s "$MARK" ]; then ok "a doc landed during the gate: the gated commit lands across it, no compile, no ratchets"; else bad "doc beside the gate: rc=$rc mark=[$(cat "$MARK")] $out"; fi
git log -1 --format=%P origin/master | grep -q "$GATED" && ok "the pushed commit is a merge of the gated commit and master" || bad "pushed commit is not a merge over the gated commit"

gated lane/b; land_on_master tools/dq_side.sh; push
if [ "$rc" -eq 0 ] && git merge-base --is-ancestor "$GATED" origin/master && [ ! -s "$MARK" ]; then ok "a lane script landed during the gate: the same"; else bad "script beside the gate: rc=$rc mark=[$(cat "$MARK")] $out"; fi

before="$(git rev-parse origin/master)"
gated lane/c; before="$(git rev-parse origin/master)"; land_on_master tools/analyze/x.rs; moved="$(git rev-parse origin/master)"; push
if [ "$rc" -ne 0 ] && grep -q 'origin/master moved' <<<"$out" && [ "$(git rev-parse origin/master)" = "$moved" ]; then ok "the analyzer moved during the gate: refused as master moved, nothing pushed (a fresh gate)"; else bad "analyzer beside the gate: rc=$rc $out"; fi

gated lane/d; land_on_master code/mod/a.dm; moved="$(git rev-parse origin/master)"; push
if [ "$rc" -ne 0 ] && grep -q 'origin/master moved' <<<"$out" && [ "$(git rev-parse origin/master)" = "$moved" ]; then ok "game code moved during the gate: refused"; else bad "game code beside the gate: rc=$rc $out"; fi

gated lane/e; land_on_master doc/d.md; moved="$(git rev-parse origin/master)"; push 0
if [ "$rc" -ne 0 ] && [ "$(git rev-parse origin/master)" = "$moved" ]; then ok "without DQ_PUSH_NEUTRAL_OK any move still refuses (every push but the train's heavy one)"; else bad "strict without the flag: rc=$rc $out"; fi

gated lane/f doc/d.md; land_on_master doc/other.md; moved="$(git rev-parse origin/master)"; push
if [ "$rc" -ne 0 ] && grep -q 'origin/master moved' <<<"$out" && [ "$(git rev-parse origin/master)" = "$moved" ]; then ok "a neutral change in a directory the gated lanes touch: the stamp does not carry, refused as master moved (never a bounce)"; else bad "shared directory: rc=$rc $out"; fi

# ---- the side lander's decisions --------------------------------------------------------------------------------------------------
git switch -q --detach origin/master
mk_light() { git switch -q -C "$1" origin/master; mkdir -p "$(dirname "$2")"; echo "$1" >>"$2"; git add -A; git commit -qm "$1"; git push -q origin "$1" 2>/dev/null; git rev-parse HEAD; }
t_doc="$(mk_light side/doc doc/side.md)"; t_tool="$(mk_light side/analyze tools/analyze/y.rs)"; t_share="$(mk_light side/share code2/z.md)"; t_nopre="$(mk_light side/nopre doc/nopre.md)"; t_fail="$(mk_light side/fail doc/fail.md)"
t_gate="$(mk_light gate/lane code2/y.txt)"
git switch -q --detach origin/master
cat >"$tmp/side.sh" <<EOF
set +u
export DQ_TRAIN_STATE="$tmp/state" DQ_TRAIN_WT="$tmp/r" DQ_TRAIN_ORIGIN_REPO="$tmp/r" DQ_TRAIN_NO_START=1 DQ_TRAIN_LIGHT_SIDE_POLL=1
. "$here/tools/dq_train.sh" __lib
mkdir -p "\$Q" "\$BOUNCED" "\$LOGS"
enq() { printf 'seq=%s\nbranch=%s\ntip=%s\nlight=%s\nsince=2026-11-01T00:00:00Z\n' "\$1" "\$2" "\$3" "\$4" >"\$(qfile "\$2")"; }
enq 1 side/analyze $t_tool 1; enq 2 side/share $t_share 1; enq 3 side/nopre $t_nopre 1; enq 4 side/fail $t_fail 1; enq 5 side/doc $t_doc 1
echo gate/lane >"\$STATE/batch.lanes"; enq 9 gate/lane $t_gate 0
pre_status() { [ "\$1" = side/nopre ] && echo none || echo pass; }
light_cycle() { # stub: records the lane and the scripts it would run; side/fail fails as a failed landing does in light_cycle
	echo "landed \${CHOSEN[*]} tools=\${DQ_LAND_TOOLS_DIR:-}" >>"$tmp/side.log"
	[ "\${CHOSEN[0]}" != side/fail ] || bounce side/fail "stub failure"
}
( n=0; while [ \$n -lt "\${STOP_AFTER:-120}" ] && ! grep -q side/doc "$tmp/side.log" 2>/dev/null; do sleep 1; n=\$((n + 1)); done; : >"\$STATE/light_side.stop" ) &
light_side_loop \$\$
EOF
out="$(bash "$tmp/side.sh" 2>&1)"
log="$(cat "$tmp/side.log" 2>/dev/null)"
grep -q 'landed side/doc tools=.*side-tools' <<<"$log" && ok "a neutral lane with a passing precheck lands beside the gate, from its own copy of the scripts" || bad "side/doc did not land: $log $out"
grep -q 'side/analyze' <<<"$log" && bad "a lane that changes the analyzer landed beside the gate" || ok "a lane that changes what a gate reads waits for the normal light cycle"
grep -q 'side/analyze waits for the normal light cycle' <<<"$out" && ok "the log says why it waits" || bad "no reason logged: $out"
grep -q 'side/share' <<<"$log" && bad "a lane sharing a directory with the gated lanes landed" || ok "a lane sharing a directory with the gated lanes waits (its landing would cost the gate its stamp)"
grep -q 'side/nopre' <<<"$log" && bad "a lane with no passing precheck landed" || ok "a lane with no passing precheck waits"
[ -z "$(ls "$tmp/state/bounced" 2>/dev/null)" ] && grep -q 'side/fail did not land beside the gate' <<<"$out" && ok "a failed side landing bounces nobody" || bad "side/fail: $(ls "$tmp/state/bounced" 2>/dev/null) $out"
[ "$(grep -c 'side/fail' <<<"$log")" = 1 ] && ok "one try per tip per gate" || bad "side/fail tried $(grep -c 'side/fail' <<<"$log") times"

# a bisect being resumed: nothing lands (its verdict cache is keyed to origin/master)
rm -f "$tmp/side.log"; rm -rf "$tmp/state"; mkdir -p "$tmp/state"; echo gate/lane >"$tmp/state/bisect.lanes"
STOP_AFTER=5 bash "$tmp/side.sh" >/dev/null 2>&1
[ ! -s "$tmp/side.log" ] && ok "nothing lands beside a resumed bisect" || bad "landed during a bisect: $(cat "$tmp/side.log")"

grep -q 'DQ_PUSH_NEUTRAL_OK="${DQ_TRAIN_LIGHT_SIDE:-1}"' "$here/tools/dq_train.sh" && ok "the heavy push is the push that takes the flag" || bad "heavy push does not pass DQ_PUSH_NEUTRAL_OK"
[ "$(grep -c 'DQ_PUSH_NEUTRAL_OK=' "$here/tools/dq_train.sh")" = 1 ] && ok "and no other train push does" || bad "another train push takes the flag"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
