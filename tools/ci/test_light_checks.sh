#!/usr/bin/env bash
# Self-test of the light path (tools/dq_light_paths.sh, dq_light_checks.sh, dq_land_batch.sh submit) in a scratch repository.
#   bash tools/ci/test_light_checks.sh
set -uo pipefail
# Hermetic: the train's own environment (a precheck runs this inside the prechecker, which exports DQ_TRAIN_ORIGIN_REPO and friends) must
# not reach the scratch train, or it reads the real repository (28 October: "lane/doc: the branch no longer exists"). TEST_TRAIN_* stays.
for _v in $(compgen -e | grep -E '^(DQ_|GIT_CONFIG_)'); do unset "$_v"; done; unset _v
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1 [$2]"; fail=1; fi; }
git init -q --bare "$tmp/origin.git"; git clone -q "$tmp/origin.git" "$tmp/r" 2>/dev/null
cd "$tmp/r"; git config user.email t@t; git config user.name t
mkdir -p tools doc code
cp "$here"/tools/dq_light_paths.sh "$here"/tools/dq_light_checks.sh "$here"/tools/dq_land_batch.sh "$here"/tools/dq_git_safe.sh tools/
mkdir -p tools/ci
printf '#!/usr/bin/env bash\necho "ratchets selftests=${DQ_RATCHETS_SELFTESTS:-}" >>"$ST_LOG"\n' >tools/ci/check_ratchets.sh
for t in train foo; do printf '#!/usr/bin/env bash\necho "%s" >>"$ST_LOG"\n' "$t" >"tools/ci/test_$t.sh"; echo "echo $t" >"tools/dq_$t.sh"; done
printf '#!/usr/bin/env bash\nsleep 5\n' >tools/ci/test_slow.sh; echo 'echo slow' >tools/dq_slow.sh
echo 'echo other' >tools/dq_other.sh
echo '[a](b.md)' >doc/a.md; echo b >doc/b.md; echo 'echo hi' >tools/x.sh; echo 'x' >code/a.dm
git add -A; git commit -q -m init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
export DQ_LIGHT_CARGO=0 DQ_LANE_POOL_STATE="$tmp/state" ST_LOG="$tmp/st.log"

git switch -q -c docs/ok; echo '[c](b.md) [web](https://x.y/z) [sec](#top)' >>doc/a.md; echo 'echo two' >>tools/x.sh; git commit -qam ok
check "a docs+script change passes the light checks" 'bash tools/dq_light_checks.sh origin/master HEAD >/dev/null 2>&1'
git switch -q -c docs/badlink master; echo '[gone](missing.md)' >>doc/a.md; git commit -qam bad
check "a broken relative doc link fails" '! bash tools/dq_light_checks.sh origin/master HEAD >/dev/null 2>&1'
git switch -q -c docs/badsh master; echo 'if then' >>tools/x.sh; git commit -qam badsh
check "a script with a syntax error fails (bash -n)" '! bash tools/dq_light_checks.sh origin/master HEAD >/dev/null 2>&1'
git switch -q -c docs/dm master; echo y >>code/a.dm; git commit -qam dm
check "a .dm change is refused by the checks" '! bash tools/dq_light_checks.sh origin/master HEAD >/dev/null 2>&1'
out="$(bash tools/dq_land_batch.sh submit 2>&1)"; rc=$?
check "submit refuses a light branch that touches .dm and queues nothing" '[ "$rc" -ne 0 ] && grep -q REFUSED <<<"$out" && [ -z "$(ls "$tmp/state/light-queue" 2>/dev/null)" ]'
git switch -q docs/ok
out="$(bash tools/dq_land_batch.sh submit 2>&1)"; rc=$?
check "submit pushes a good light branch and queues it" '[ "$rc" -eq 0 ] && git ls-remote origin docs/ok | grep -q . && ls "$tmp/state/light-queue" | grep -q docs_ok'
# self-tests run only for what changed, each capped; the ratchets only for a .dm file or a lint input
runlc() { : >"$ST_LOG"; bash tools/dq_light_checks.sh origin/master HEAD >"$tmp/lc.out" 2>&1; }
git switch -q -c st/foo master; echo '# x' >>tools/dq_foo.sh; git commit -qam foo
runlc; rc=$?
check "a changed tool runs its own self-test only (not test_train, not the ratchets)" '[ "$rc" = 0 ] && [ "$(cat "$ST_LOG")" = foo ]'
git switch -q -c st/train master; echo '# x' >>tools/dq_train.sh; git commit -qam train
runlc
check "test_train.sh runs when dq_train.sh changes" 'grep -qx train "$ST_LOG" && ! grep -qx foo "$ST_LOG"'
git switch -q -c st/other master; echo '# x' >>tools/dq_other.sh; git commit -qam other
runlc
check "a tool with no self-test runs none, and a tools/ci script edit alone does not run the ratchets" '[ ! -s "$ST_LOG" ]'
git switch -q -c st/selftest master; echo '# x' >>tools/ci/test_foo.sh; git commit -qam selftest
runlc
check "a changed self-test runs itself and nothing else" '[ "$(cat "$ST_LOG")" = foo ]'
git switch -q -c st/lint master; echo '# x' >>tools/ci/check_ratchets.sh; git commit -qam lint
runlc
check "a changed lint input runs the ratchets with the changed-only self-tests" 'grep -qx "ratchets selftests=changed" "$ST_LOG"'
git switch -q -c st/slow master; echo '# x' >>tools/dq_slow.sh; git commit -qam slow
: >"$ST_LOG"; DQ_LIGHT_SELFTEST_CAP_SEC=1 bash tools/dq_light_checks.sh origin/master HEAD >"$tmp/lc.out" 2>&1; rc=$?
check "a self-test over its cap is a warning (inconclusive), not a failure" '[ "$rc" = 0 ] && grep -q "hit its 1s cap and was stopped" "$tmp/lc.out"'
[ "$fail" -eq 0 ] && echo "test_light_checks: all passed" || echo "test_light_checks: FAILED"
exit "$fail"
