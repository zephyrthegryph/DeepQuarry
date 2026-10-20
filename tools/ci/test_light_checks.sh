#!/usr/bin/env bash
# Self-test of the light path (tools/dq_light_paths.sh, dq_light_checks.sh, dq_land_batch.sh submit) in a scratch repository.
#   bash tools/ci/test_light_checks.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
check() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1 [$2]"; fail=1; fi; }
git init -q --bare "$tmp/origin.git"; git clone -q "$tmp/origin.git" "$tmp/r" 2>/dev/null
cd "$tmp/r"; git config user.email t@t; git config user.name t
mkdir -p tools doc code
cp "$here"/tools/dq_light_paths.sh "$here"/tools/dq_light_checks.sh "$here"/tools/dq_land_batch.sh "$here"/tools/dq_git_safe.sh tools/
echo '[a](b.md)' >doc/a.md; echo b >doc/b.md; echo 'echo hi' >tools/x.sh; echo 'x' >code/a.dm
git add -A; git commit -q -m init; git branch -M master; git push -q origin master 2>/dev/null; git fetch -q origin
export DQ_LIGHT_CARGO=0 DQ_LANE_POOL_STATE="$tmp/state"

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
[ "$fail" -eq 0 ] && echo "test_light_checks: all passed" || echo "test_light_checks: FAILED"
exit "$fail"
