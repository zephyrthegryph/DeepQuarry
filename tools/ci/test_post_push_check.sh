#!/usr/bin/env bash
# Self-test of tools/dq_post_push_check.sh with a stub boot on a scratch repository.
set -uo pipefail
for _v in $(compgen -e | grep -E '^(DQ_|GIT_CONFIG_)'); do unset "$_v"; done; unset _v
unset MSYS_NO_PATHCONV
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
git init -q --bare "$tmp/o.git"; git -C "$tmp/o.git" symbolic-ref HEAD refs/heads/master
git init -q "$tmp/r"; cd "$tmp/r" || exit 1; git config user.email t@t; git config user.name t; git remote add origin "$tmp/o.git"
c() { git commit -q --allow-empty -m "$1"; git push -q origin HEAD:refs/heads/master; git rev-parse HEAD; }
git branch -M master 2>/dev/null
export DQ_HEALTH_STATE="$tmp/s" DQ_HEALTH_REPO="$tmp/r" DQ_HEALTH_MIN_FREE_GB=0 DQ_HEALTH_POLL=0
cat >"$tmp/boot.sh" <<E
#!/usr/bin/env bash
echo "\$1" >>"$tmp/booted"
cat "$tmp/result"
E
export DQ_HEALTH_CMD="bash $tmp/boot.sh"
t="$here/tools/dq_post_push_check.sh"
v() { sed -n "s/^$1=//p" "$tmp/s/verdict.txt"; }
a="$(c one)"; echo 'FOCUSED RESULT: 1 passed, 0 failed (json: x)' >"$tmp/result"; bash "$t" run
[ "$(v status)" = pass ] && [ "$(v last_good)" = "$a" ] && [ ! -f "$tmp/s/MASTER_BROKEN.txt" ] && ok "a passing boot is recorded as last good" || bad "pass: $(cat "$tmp/s/verdict.txt")"
n=$(wc -l <"$tmp/booted"); bash "$t" run; [ "$(wc -l <"$tmp/booted")" = "$n" ] && ok "an unchanged master is not checked again" || bad "rechecked"
c two >/dev/null; b="$(c three)"; : >"$tmp/booted"; echo 'FOCUSED RESULT: 0 passed, 1 failed (json: x)' >"$tmp/result"; bash "$t" run
[ "$(cat "$tmp/booted")" = "$b" ] && ok "a burst of pushes checks only the newest" || bad "burst: $(cat "$tmp/booted")"
[ "$(v status)" = FAIL ] && [ "$(v range)" = "$a..$b" ] && grep -q "$a..$b" "$tmp/s/MASTER_BROKEN.txt" && ok "a failure names the first bad range and writes MASTER_BROKEN.txt" || bad "fail: $(cat "$tmp/s/verdict.txt")"
out="$(bash "$t" status)"; grep -q 'MASTER DOES NOT BOOT' <<<"$out" && ok "status shows it" || bad "status"
d="$(c four)"; echo 'FOCUSED RESULT: no results (exit code 1)' >"$tmp/result"; bash "$t" run
[ "$(v status)" = unknown ] && [ -f "$tmp/s/MASTER_BROKEN.txt" ] && [ "$(v last_good)" = "$a" ] && ok "no result is unknown: it neither blames nor clears" || bad "unknown: $(cat "$tmp/s/verdict.txt")"
d2="$(c four-b)"; echo 'FOCUSED RESULT: 1 passed, 0 failed (json: x) [exit 1: the world was not clean: boot gate, watchdog or crash]' >"$tmp/result"; bash "$t" run
[ "$(v status)" = FAIL ] && [ -f "$tmp/s/MASTER_BROKEN.txt" ] && ok "a not-clean boot with 0 failed is FAIL, not pass" || bad "not clean: $(cat "$tmp/s/verdict.txt")"
e="$(c five)"; echo 'FOCUSED RESULT: 1 passed, 0 failed' >"$tmp/result"; bash "$t" run
[ ! -f "$tmp/s/MASTER_BROKEN.txt" ] && [ "$(v last_good)" = "$e" ] && ok "a pass clears it" || bad "clear"
f="$(c six)"; : >"$tmp/booted"; DQ_HEALTH_MIN_FREE_GB=99999 DQ_HEALTH_RAM_WAITS=1 bash "$t" run
[ ! -s "$tmp/booted" ] && ok "no check starts under the RAM floor" || bad "RAM"
mkdir "$tmp/s/run.lock"; sleep 30 & h=$!; echo "$h" >"$tmp/s/run.lock/pid"; bash "$t" run; [ ! -s "$tmp/booted" ] && ok "one runner at a time" || bad "two runners"; kill "$h" 2>/dev/null
bash "$t" run; [ "$(cat "$tmp/booted")" = "$f" ] && ok "a dead runner's lock is replaced" || bad "dead lock"
s=$(date +%s); bash "$t" start; [ $(( $(date +%s) - s )) -lt 10 ] && ok "start returns at once" || bad "start blocks"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
