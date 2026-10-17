#!/usr/bin/env bash
# Self-test of tools/dq_gate_retry.sh with a stub focused-test command (no compiler, no world): a flake is recovered by one isolated
# rerun and ledgered, a test that fails twice stays a failure, an infrastructure failure reruns the whole list once, a pass runs once.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

cd "$tmp"
git init -q . 2>/dev/null
git config user.email t@t; git config user.name t
git commit -q --allow-empty -m init
export DQ_FLAKE_LEDGER="$tmp/flakes.tsv"
lanes="lane-a"
. "$here/tools/dq_gate_retry.sh"

# The stub: STUB_MODE picks the behaviour; every call is appended to calls.log.
cat >stub.sh <<'STUB'
#!/usr/bin/env bash
echo "$*" >>calls.log
n=$(wc -l <calls.log)
case "$STUB_MODE" in
	pass) echo "FOCUSED RESULT: 5 passed, 0 failed (json: none)"; exit 0 ;;
	flake)
		if [ "$n" -eq 1 ]; then
			echo '{"failed":["/datum/unit_test/dq_flaky_one"],"counts":{"passed":4,"failed":1,"skipped":0}}' >run.json
			echo "FAIL dq_flaky_one"; echo "FOCUSED RESULT: 4 passed, 1 failed (json: run.json)"; echo "KNOWN FAILURES CHECK: 1 NEW, 0 KNOWN"; exit 1
		fi
		echo "FOCUSED RESULT: 1 passed, 0 failed (json: none)"; exit 0 ;;
	twice)
		echo '{"failed":["/datum/unit_test/dq_real_bug"],"counts":{"passed":4,"failed":1,"skipped":0}}' >run.json
		echo "FOCUSED RESULT: 4 passed, 1 failed (json: run.json)"; exit 1 ;;
	infra)
		if [ "$n" -eq 1 ]; then echo "Native executable changed during compilation."; echo "FOCUSED RESULT: no results (exit code 1; the world died or the build failed)"; exit 1; fi
		echo "FOCUSED RESULT: 5 passed, 0 failed (json: none)"; exit 0 ;;
esac
STUB
chmod +x stub.sh
export DQ_FOCUSED_TEST_CMD="bash $tmp/stub.sh"

run() { rm -f calls.log "$DQ_FLAKE_LEDGER"; STUB_MODE="$1" gate_tests_with_retry a b c >out.log 2>&1; echo $?; }

rc="$(run pass)"
check "a passing run runs once" '[ "$rc" = 0 ] && [ "$(wc -l <calls.log)" = 1 ] && [ ! -f "$DQ_FLAKE_LEDGER" ]'
rc="$(run flake)"
check "a flake passes on the isolated rerun" '[ "$rc" = 0 ] && [ "$(wc -l <calls.log)" = 2 ] && sed -n 2p calls.log | grep -q -- "--force dq_flaky_one"'
check "the flake is ledgered with the lane" 'grep -q "flake.*lane-a.*dq_flaky_one" "$DQ_FLAKE_LEDGER"'
check "the log ends with counts that include the recovered test" 'tail -n 2 out.log | head -n 1 | grep -q "^FOCUSED RESULT: 5 passed, 0 failed" && tail -n 1 out.log | grep -q "^KNOWN FAILURES CHECK: 0 NEW"'
check "the log carries the GATE FLAKE line the gate reads" 'grep -q "^GATE FLAKE: dq_flaky_one failed once" out.log'
check "the ledger count lists the test" 'bash "$here/tools/dq_flake_log.sh" --count | grep -q "1.dq_flaky_one"'
rc="$(run twice)"
check "a test that fails twice is a failure" '[ "$rc" = 1 ] && [ "$(wc -l <calls.log)" = 2 ] && [ ! -f "$DQ_FLAKE_LEDGER" ]'
rc="$(run infra)"
check "an infrastructure failure reruns the whole list once" '[ "$rc" = 0 ] && [ "$(wc -l <calls.log)" = 2 ] && sed -n 2p calls.log | grep -q -- "--force a b c" && grep -q "infra" "$DQ_FLAKE_LEDGER"'
rc="$(DQ_GATE_RETRY=0 run twice)"
check "DQ_GATE_RETRY=0 turns the retry off" '[ "$rc" = 1 ] && [ "$(wc -l <calls.log)" = 1 ]'

[ "$fail" = 0 ] && echo "test_gate_retry: all passed" || { echo "test_gate_retry: FAILED"; exit 1; }
