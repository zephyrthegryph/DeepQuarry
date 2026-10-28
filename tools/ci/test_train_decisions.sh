#!/usr/bin/env bash
# Fast unit checks (a few seconds) of the train's proof-landing decisions, without a scratch repository: the functions are extracted from
# tools/dq_train.sh and tools/dq_merge_batch.sh and called directly. tools/ci/test_train.sh drives the whole train end to end.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# smoke_due: the smoke/gameplay sets run every DQ_TRAIN_SMOKE_EVERY proof landings, and on a batch of DQ_TRAIN_SMOKE_AT_LANES lanes
eval "$(sed -n '/^smoke_due() {/,/^}/p' "$here/tools/dq_train.sh")"
STATE="$tmp"
rm -f "$STATE/smoke_skipped"
check "smoke not due on the first proof landing of one lane" '! DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'
echo 3 >"$STATE/smoke_skipped"
check "smoke due after every-1 skipped proof landings" 'DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'
echo 0 >"$STATE/smoke_skipped"
check "smoke due on a batch of many lanes" 'DQ_TRAIN_SMOKE_AT_LANES=5 smoke_due 5'
echo junk >"$STATE/smoke_skipped"
check "a corrupt counter counts as zero" '! DQ_TRAIN_SMOKE_EVERY=4 smoke_due 1'

# dq_merge_batch: a run with no result is a cap (93), never a failure
re="$(grep -o "grep -qE '[^']*FOCUSED RESULT: CAPPED[^']*'" "$here/tools/dq_merge_batch.sh" | head -n 1 | sed "s/^grep -qE '//; s/'\$//")"
check "merge_batch classifies a no-result run as capped" '[ -n "$re" ] && echo "FOCUSED RESULT: CAPPED or killed before a result (exit 0)" | grep -qE "$re" && echo "FOCUSED RUN CAPPED: x" | grep -qE "$re" && ! echo "FOCUSED RESULT: 3 FAILED" | grep -qE "$re"'
check "merge_batch retries a no-result lane once with only its own tests, then defers it" 'grep -q "pass+=(--no-smoke)" "$here/tools/dq_merge_batch.sh" && grep -q "BATCH_NORESULT" "$here/tools/dq_merge_batch.sh"'

# the gates honour the train's analyze_tests trust
check "dq_merge_gates skips analyze_tests on DQ_GATE_ANALYZE_TRUSTED and logs why" 'grep -q "analyze_tests trusted (not run)" "$here/tools/dq_merge_gates.sh"'


check "a gen failure is shown, retried, then an infra exit that merge_batch treats as a setup error" 'grep -q "exit 95" "$here/tools/dq_merge_gates.sh" && grep -q "\"\$rc\" -eq 95" "$here/tools/dq_merge_batch.sh"'

check "test worlds run below normal (not idle) and log it; ratchets cap rayon beside a world" 'grep -q "PRIORITY_BELOW_NORMAL" "$here/tools/build/lib/byond.ts" && grep -q "world priority:" "$here/tools/build/lib/byond.ts" && grep -q "RAYON_NUM_THREADS=" "$here/tools/dq_merge_gates.sh"'

check "the gates stop sibling jobs when the test build fails to compile" 'grep -q "FAIL FAST: the test build does not compile" "$here/tools/dq_merge_gates.sh"'

# dq_merge_batch: one real conflict between two lanes must not poison the attempts after it (27 October, train-dc: 0 of 12 lanes passed).
# A scratch repository, stub gates; lanes c1 and c2 conflict with each other only, g1 and g2 are clean: c2 waits, the rest pass, and no
# attempt after the conflict starts dirty.
r="$tmp/mb"; git init -q --bare "$r/origin.git"; git clone -q "$r/origin.git" "$r/w" 2>/dev/null
(
	cd "$r/w" || exit 1
	git config user.email t@t; git config user.name t
	mkdir -p tools lanes
	cp "$here/tools/dq_merge_batch.sh" "$here/tools/dq_git_safe.sh" "$here/tools/dq_dme_resolve.sh" "$here/tools/dq_stale_includes.sh" tools/
	echo ': ; merge_lock_require() { return 0; }' >tools/dq_machine_slots.sh
	cat >tools/dq_merge_gates.sh <<'STUB'
#!/usr/bin/env bash
# DQ_STUB_NORESULT=1: two or more lane files give a test phase with no result (the 28 October 03:04 case)
if [ "${DQ_STUB_NORESULT:-0}" = 1 ] && [ "$(ls lanes 2>/dev/null | wc -l)" -gt 1 ]; then
	echo "FOCUSED RESULT: CAPPED or killed before a result (exit 0): the focused run printed no result line"
	echo "dq_merge_gates: FAILED: tests (logs data/merge-gates/x.<job>.log)" >&2; exit 1
fi
echo "stub gates: ok"
STUB
	echo base >shared.txt; printf 'data/\n' >.gitignore
	git add -A; git commit -q -m init; git branch -M master; git push -q origin master; git fetch -q origin
	for l in g1 c1 c2 g2; do
		git switch -q -c "$l" origin/master
		mkdir -p lanes; case "$l" in c*) echo "$l" >shared.txt ;; *) echo "$l" >"lanes/$l.txt" ;; esac
		if [ "$l" = g1 ]; then mkdir -p code/modules/unit_tests; echo x >code/modules/unit_tests/here.dm; printf '#include "here.dm"\n#include "gone.dm"\n' >code/modules/unit_tests/_unit_tests.dm; fi
		git add -A; git commit -q -m "$l"; git push -q origin "$l"
	done
	git switch -q --detach origin/master
	bash tools/dq_merge_batch.sh --lanes "g1 c1 c2 g2" >"$r/out.txt" 2>&1
	git switch -q --detach origin/master
	DQ_STUB_NORESULT=1 bash tools/dq_merge_batch.sh --lanes "g1 g2" >"$r/noresult.txt" 2>&1
) >/dev/null 2>&1
mb_good="$(sed -n 's/^BATCH_GOOD: //p' "$r/out.txt" | tail -n 1)"
mb_later="$(sed -n 's/^BATCH_LATER: //p' "$r/out.txt" | tail -n 1)"
check "a lane-vs-lane conflict holds back only that lane; the clean lanes and the first of the pair pass" '[[ " $mb_good " == *" g1 "* && " $mb_good " == *" g2 "* && " $mb_good " == *" c1 "* ]] && [ "$(echo $mb_later)" = c2 ] && ! grep -q "started dirty" "$r/out.txt"'
check "a merged include of a file that no longer exists is dropped and reported" 'grep -q "STALE INCLUDE dropped .*gone.dm" "$r/out.txt"'
check "a 2-lane attempt with no test result defers both lanes and bisects nobody (03:04: move/effects-wave was blamed)" '! grep -q "^BATCH_BOUNCED: ." "$r/noresult.txt" && grep -q "^BATCH_DEFERRED: .*g1" "$r/noresult.txt" && grep -q "^BATCH_DEFERRED: .*g2" "$r/noresult.txt"'
[ "$fail" -eq 0 ] || { echo "---- merge_batch output:"; tail -n 30 "$r/out.txt"; }

# dq_light_checks.sh: a light lane merged onto an older master, checked against a newer origin/master, is judged by its own changes only
# (28 October: tools/analyze-dreamchecker, docs only, was bounced for master's own .dm landings).
lc="$tmp/lc"; git init -q --bare "$lc/origin.git"; git clone -q "$lc/origin.git" "$lc/w" 2>/dev/null
(
	cd "$lc/w" || exit 1
	git config user.email t@t; git config user.name t
	mkdir -p tools doc code; cp "$here/tools/dq_light_checks.sh" "$here/tools/dq_light_paths.sh" tools/
	echo a >doc/a.md; echo x >code/x.dm; git add -A; git commit -q -m init; git branch -M master; git push -q origin master
	git switch -q -c lane; echo b >doc/b.md; git add -A; git commit -q -m lane
	git switch -q --detach origin/master; git merge -q --no-ff --no-edit lane      # the precheck's merge, on the old master
	git switch -q -c newer origin/master; echo y >>code/x.dm; git add -A; git commit -q -m "master moves (heavy)"; git push -q origin HEAD:master
	git switch -q --detach "HEAD@{2}" 2>/dev/null || git switch -q --detach "$(git rev-list -n1 --merges --all)"
	git fetch -q origin
	DQ_LIGHT_CARGO=0 bash tools/dq_light_checks.sh origin/master HEAD >"$lc/out.txt" 2>&1
) >/dev/null 2>&1
check "light checks count only the lane's changes when master moved since its merge" '! grep -q "heavy paths in a light batch" "$lc/out.txt" && grep -q "1 changed file" "$lc/out.txt"'

# dc_disjoint (the batch keeps its lanes' DreamChecker verdicts): a seeded cross-lane diagnostic. Lane A removes a var, lane B's
# other file reads it; each passed DreamChecker alone, together they fail. Disjoint files must not keep the verdicts: the batch runs
# DreamChecker and so catches it. One DM lane plus a docs-only lane keeps them.
dd="$tmp/dd"; git init -q --bare "$dd/origin.git"; git clone -q "$dd/origin.git" "$dd/w" 2>/dev/null
(
	cd "$dd/w" || exit 1
	git config user.email t@t; git config user.name t
	mkdir -p code doc
	printf '/obj/thing\n\tvar/power = 1\n' >code/a.dm; printf '/obj/thing/proc/use()\n\treturn 0\n' >code/b.dm; echo d >doc/x.md
	git add -A; git commit -q -m init; git branch -M master; git push -q origin master
	git switch -q -c lane/a origin/master; printf '/obj/thing\n' >code/a.dm; git commit -qam "a: drop power"; git push -q origin lane/a
	git switch -q -c lane/b origin/master; printf '/obj/thing/proc/use()\n\treturn power\n' >code/b.dm; git commit -qam "b: read power"; git push -q origin lane/b
	git switch -q -c lane/d origin/master; echo e >>doc/x.md; git commit -qam "docs"; git push -q origin lane/d
	git switch -q --detach origin/master
) >/dev/null 2>&1
dd_run() { # <lanes...>: prints "keep" or "run"
	(
		set +u
		unset DQ_TRAIN_DC_DISJOINT
		export DQ_TRAIN_STATE="$dd/state" DQ_TRAIN_WT="$dd/no-wt" DQ_TRAIN_ORIGIN_REPO="$dd/w" DQ_TRAIN_NO_START=1
		cd "$dd/w" || exit 1
		. "$here/tools/dq_train.sh" __lib
		init_state
		m="$(git rev-parse origin/master)"
		for b in "$@"; do
			t="$(git rev-parse "$b")"
			printf 'seq=1\nbranch=%s\ntip=%s\ntests=\nlight=0\n' "$b" "$t" >"$(qfile "$b")"
			printf 'branch=%s\ntip=%s\nmaster=%s\nverdict=pass\n' "$b" "$t" "$m" >"$PRE/v/$(pre_key "$b" "$t")@${m:0:12}"
			printf 'branch=%s\ntip=%s\nmaster=%s\nverdict=pass\n' "$b" "$t" "$m" >"$PRE/dc/v/$(pre_key "$b" "$t")@${m:0:12}"
		done
		if dc_disjoint "$@"; then echo keep; else echo "run ($DC_DISJOINT_WHY_NOT)"; fi
	) 2>/dev/null
}
dd_ab="$(dd_run lane/a lane/b)"; dd_ad="$(dd_run lane/a lane/d)"
check "a seeded cross-lane DreamChecker break (disjoint files) makes the batch run DreamChecker" '[ "$dd_ab" = "run (two lanes change DreamChecker inputs)" ]'
check "one DM lane plus a docs-only lane keeps the precheck DreamChecker verdict" '[ "$dd_ad" = keep ]'

# lint_scopes.toml merge driver: adjacent lowered ceilings merge (the lower wins on the same key); a real disagreement still conflicts.
ls_d="$tmp/lsd"; mkdir -p "$ls_d"
printf '[lint.check_grep.ceilings]\nalpha = 10\nbeta = 20\ngamma = 30\n' >"$ls_d/O"
printf '[lint.check_grep.ceilings]\nalpha = 9\nbeta = 18\ngamma = 30\n' >"$ls_d/A"
printf '[lint.check_grep.ceilings]\nalpha = 10\nbeta = 17\ngamma = 25\n' >"$ls_d/B"
(cd "$here" && bash tools/ci/lint_scopes_merge_driver.sh "$ls_d/O" "$ls_d/A" "$ls_d/B" lint_scopes.toml) >/dev/null 2>&1; ls_rc=$?
check "lint_scopes driver: adjacent and same-key lowered ceilings merge to the lower values" '[ "$ls_rc" = 0 ] && [ "$(cat "$ls_d/A")" = "$(printf "[lint.check_grep.ceilings]\nalpha = 9\nbeta = 17\ngamma = 25")" ]'
# the 09:52 case: adjacent ceilings lowered on each side, and theirs also adds a line elsewhere (line counts differ)
printf 'a = 1\nimproper = 2\nbump = 17\ntransform = 46\ndata = 42\n\n[l]\n# c1\nx = 1\n' >"$ls_d/O3"
printf 'a = 1\nimproper = 2\nbump = 2\ntransform = 46\ndata = 42\n\n[l]\n# c1\nx = 1\n' >"$ls_d/A3"
printf 'a = 1\nimproper = 2\nbump = 17\ntransform = 37\ndata = 42\n\n[l]\n# c1\n# c2 added\nx = 1\n' >"$ls_d/B3"
(cd "$here" && bash tools/ci/lint_scopes_merge_driver.sh "$ls_d/O3" "$ls_d/A3" "$ls_d/B3" lint_scopes.toml) >/dev/null 2>&1; ls_rc3=$?
check "lint_scopes driver: adjacent lowered ceilings merge although the other side added a line elsewhere (gr/bumped-notices 09:52)" '[ "$ls_rc3" = 0 ] && grep -qx "bump = 2" "$ls_d/A3" && grep -qx "transform = 37" "$ls_d/A3" && grep -qx "# c2 added" "$ls_d/A3" && ! grep -q "<<<<" "$ls_d/A3"'
printf '[x]\nname = "one"\n' >"$ls_d/O2"; printf '[x]\nname = "two"\n' >"$ls_d/A2"; printf '[x]\nname = "three"\n' >"$ls_d/B2"
(cd "$here" && bash tools/ci/lint_scopes_merge_driver.sh "$ls_d/O2" "$ls_d/A2" "$ls_d/B2" lint_scopes.toml) >/dev/null 2>&1; ls_rc2=$?
check "lint_scopes driver: a text disagreement is still a conflict" '[ "$ls_rc2" != 0 ] && grep -q "<<<<<<<" "$ls_d/A2"'

# dq_drop_stale_includes (dq_merge_master.sh and the batch merge): includes of files that no longer exist are dropped, staged and reported,
# in _unit_tests.dm (relative to its folder) and in deepquarry.dme (root-relative, backslashes); the includes that exist stay.
si="$tmp/si"; mkdir -p "$si"; (
	cd "$si" && git init -q && git config user.email t@t && git config user.name t
	mkdir -p code/modules/unit_tests code/game; echo x >code/modules/unit_tests/here.dm; echo y >code/game/kept.dm
	printf '#include "here.dm"\n#include "moved_away.dm"\n' >code/modules/unit_tests/_unit_tests.dm
	printf '#include "code\\game\\kept.dm"\n#include "code\\modules\\unit_tests\\gone.dm"\n' >deepquarry.dme
	git add -A; git commit -q -m init
	. "$here/tools/dq_stale_includes.sh"
	dq_drop_stale_includes code/modules/unit_tests/_unit_tests.dm code/modules/unit_tests test
	dq_drop_stale_includes deepquarry.dme . test
) >"$si.out" 2>&1
check "stale includes are dropped and reported in _unit_tests.dm and deepquarry.dme; existing ones stay" 'grep -q "moved_away.dm" "$si.out" && grep -q "gone.dm" "$si.out" && ! grep -q moved_away "$si/code/modules/unit_tests/_unit_tests.dm" && grep -q "here.dm" "$si/code/modules/unit_tests/_unit_tests.dm" && grep -q "kept.dm" "$si/deepquarry.dme" && ! grep -q "gone.dm" "$si/deepquarry.dme" && [ -n "$(git -C "$si" diff --cached --name-only)" ]'
check "dq_merge_master.sh drops stale includes during a merge" 'grep -q "dq_drop_stale_includes code/modules/unit_tests/_unit_tests.dm" "$here/tools/dq_merge_master.sh"'

# gates: an sccache server drop is infra (retried without sccache, then exit 95); a real compile error is not
eval "$(sed -n '/^gate_sccache_failure() {/p' "$here/tools/dq_merge_gates.sh")"
printf 'error: failed to compile vg-ffi\nsccache: error reading compile response from server\nCaused by: An existing connection was forcibly closed by the remote host. (os error 10054)\n' >"$tmp/sc1.log"
printf 'error[E0425]: cannot find value `x` in this scope\n  --> src/lib.rs:3:5\nwarning: build used sccache at C:/sccache\n' >"$tmp/sc2.log"
check "an sccache connection failure is classified as infra" 'gate_sccache_failure "$tmp/sc1.log"'
check "a real Rust compile error is not classified as sccache infra" '! gate_sccache_failure "$tmp/sc2.log"'
check "the gate retries without sccache and exits 95 on a second sccache failure" 'grep -q "RUSTC_WRAPPER= SCCACHE_DISABLE=1" "$here/tools/dq_merge_gates.sh" && grep -q "failed on sccache twice" "$here/tools/dq_merge_gates.sh"'

# light checks: the verdigris crates test for the 32-bit target BYOND loads (byondapi-sys refuses the 64-bit host); other crates use the host
lc_v="$(bash "$here/tools/dq_light_checks.sh" --target-args verdigris/ffi/Cargo.toml)"; lc_t="$(bash "$here/tools/dq_light_checks.sh" --target-args tools/dmb/crates/dmbc/Cargo.toml)"
check "light checks test the verdigris crates for i686 and other crates for the host" '{ [ "$lc_v" = "--target i686-pc-windows-msvc" ] || ! uname -s | grep -qE "MINGW|MSYS|CYGWIN"; } && [ -z "$lc_t" ]'

[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
