#!/usr/bin/env bash
# Sourced by dq_merge_gates.sh: the test job of a gate, with one retry that tells a flake from a failure.
#
#   gate_tests_with_retry <test selector...>     # runs tools/dq_focused_test.sh (DQ_FOCUSED_TEST_CMD overrides it, for the self-test)
#
# A gate that fails on a flake used to cost the batch a full rerun (6-10 minutes under the merge lock). After a failing run:
#   1. some tests failed (a result record names them): only those are run again, once, in a fresh world (--force skips the rerun guard,
#      which would refuse them). If they all pass, the failure was a flake: the job passes, and each flaked test is recorded in the
#      machine's flake ledger ($(flake_ledger), tools/dq_flake_log.sh prints it) with the gate's sha and lanes, so a fix lane can pick it
#      up; the log ends with a synthetic FOCUSED RESULT / KNOWN FAILURES CHECK pair that counts the recovered tests as passed.
#      A test that fails again is a failure: the job fails with the original and the retry logs together.
#   2. the world never produced a result (it died, the watchdog killed it, the compiler daemon did not start, the shared compiler
#      binary changed under the compile): the whole list runs once more, and the infrastructure failure is recorded the same way.
# DQ_GATE_RETRY=0 turns the retry off. The retry never runs when the tree changed (dq_focused_test.sh checks HEAD itself) and is
# printed loudly: "GATE FLAKE" / "GATE INFRA RETRY" lines in data/merge-gates/<sha>.tests.log.

flake_ledger() {
	if [ -n "${DQ_FLAKE_LEDGER:-}" ]; then echo "$DQ_FLAKE_LEDGER"
	elif [ -d E:/dq-cache ] || [ -d /e/dq-cache ]; then echo "E:/dq-cache/flakes.tsv"
	else echo "$HOME/.cache/dq/flakes.tsv"; fi
}

# flake_record <kind flake|infra> <names> <log tail> : one TSV row: time, kind, gate sha, lanes, names, first error line
flake_record() {
	local ledger
	ledger="$(flake_ledger)"
	mkdir -p "$(dirname "$ledger")" 2>/dev/null || return 0
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(git rev-parse --short=12 HEAD 2>/dev/null)" "${lanes:-}" "$2" "$3" >>"$ledger" 2>/dev/null || true
}

# The failed test names (without /datum/unit_test/) of a result record, one per line.
gate_failed_names() {
	node -e '
		const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
		for (const t of r.failed || []) console.log(t.replace(/^\/datum\/unit_test\//, ""));' "$1" 2>/dev/null
}

# Does a log hold the signature of an infrastructure failure (not a test failure)?
gate_infra_failure() { # <log>
	grep -qiE 'Native executable changed during compilation|daemon startup deadline expired|no method named `evict_to_budget`|watchdog|world did not start|FOCUSED RESULT: no results' "$1"
}

# gate_cap_minutes <test count>: the wall-clock cap a gate gives dq_focused_test.sh (base 5 min plus 1 min per test, ceiling 10).
# Gate-only: it travels as DQ_GATE_FOCUSED_MAX_MIN, which dq_focused_test.sh honours instead of the agent cap (DQ_FOCUSED_MAX_MIN).
gate_cap_minutes() {
	local n="${1:-0}" cap
	case "$n" in '' | *[!0-9]*) n=0 ;; esac
	cap=$(( 5 + n ))
	[ "$cap" -gt 10 ] && cap=10
	echo "$cap"
}

# gate_ensure_result <log> <rc>: a focused run killed before it could print (a cap, a wrapper timeout, a dead shell) leaves no FOCUSED RESULT
# line, and the evidence check then says only "missing or inconsistent". Print a clear one, so the cause is in the log.
gate_ensure_result() {
	grep -q '^FOCUSED RESULT:' "$1" 2>/dev/null && return 0
	local line="FOCUSED RESULT: CAPPED or killed before a result (exit $2): the focused run printed no result line; see the guard log (data/focused-runs/guard.*.log) and the 'FOCUSED RUN CAPPED' / queued-time lines above. Not a test failure."
	echo "$line"
	echo "$line" >>"$1"
}

gate_tests_with_retry() {
	local focused="${DQ_FOCUSED_TEST_CMD:-bash tools/dq_focused_test.sh}" log rc json names n first_line res passed failed rlog
	log="$(mktemp)"
	# shellcheck disable=SC2086  # the command may be several words
	DQ_GATE_FOCUSED_MAX_MIN="$(gate_cap_minutes $#)" $focused "$@" 2>&1 | tee "$log"
	rc=${PIPESTATUS[0]}
	gate_ensure_result "$log" "$rc"
	if [ "$rc" -eq 0 ] || [ "${DQ_GATE_RETRY:-1}" = 0 ]; then rm -f "$log"; return "$rc"; fi
	# A run killed at its wall-clock cap is a verdict on the size of the list: another run would only spend the cap again
	# (the batch train, tools/dq_train.sh, reads the cap line and shrinks the batch instead).
	if grep -q '^FOCUSED RUN CAPPED' "$log"; then echo "== GATE: the test run hit its wall-clock cap; no retry (the batch is too big for it)"; rm -f "$log"; return "$rc"; fi
	res="$(grep -h '^FOCUSED RESULT:' "$log" | tail -n 1)"
	json="$(sed -n 's/.*(json: \([^)]*\)).*/\1/p' <<<"$res")"
	names=()
	if [ -n "$json" ] && [ -f "$json" ]; then mapfile -t names < <(gate_failed_names "$json"); fi
	first_line="$(grep -m1 -iE 'FAIL|error|deadline|watchdog|changed during' "$log" | head -c 200 | tr '\t' ' ')"
	if [ ${#names[@]} -gt 0 ]; then
		echo "== GATE RETRY: ${#names[@]} test(s) failed; running only those once more in a fresh world: ${names[*]:0:8}"
		rlog="$(mktemp)"
		# shellcheck disable=SC2086
		DQ_GATE_FOCUSED_MAX_MIN="$(gate_cap_minutes ${#names[@]})" $focused --force "${names[@]}" 2>&1 | tee "$rlog"
		if [ "${PIPESTATUS[0]}" -eq 0 ]; then
			passed="$(sed -n 's/^FOCUSED RESULT: \([0-9]*\) passed.*/\1/p' <<<"$res")"
			failed="$(sed -n 's/^FOCUSED RESULT: [0-9]* passed, \([0-9]*\) failed.*/\1/p' <<<"$res")"
			n=${#names[@]}
			echo "GATE FLAKE: ${names[*]} failed once and passed in isolation; recorded in $(flake_ledger); needs a fix lane (tools/dq_flake_log.sh)"
			flake_record flake "${names[*]}" "$first_line"
			# The first run's record still says "failed": write a merged record beside it (same commit, the recovered tests moved from
			# failed to passed, the flaked names kept under "recovered") so the counts on the result line match the JSON it names.
			rjson="$json"
			if [ -n "$json" ] && [ -f "$json" ]; then
				rjson="${json%.json}.recovered.json"
				node -e '
					const fs = require("fs");
					const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
					const names = process.argv[3].split(" ").filter(Boolean);
					const set = new Set(names.map(n => "/datum/unit_test/" + n));
					r.failed = (r.failed || []).filter(t => !set.has(t));
					r.recovered = names;
					r.counts = Object.assign({}, r.counts, { passed: r.counts.passed + names.length, failed: r.counts.failed - names.length });
					fs.writeFileSync(process.argv[2], JSON.stringify(r));' "$json" "$rjson" "${names[*]}" || rjson="$json"
			fi
			echo "FOCUSED RESULT: $(( ${passed:-0} + n )) passed, $(( ${failed:-0} - n )) failed (json: ${rjson:-none}) [recovered by an isolated rerun: ${names[*]}]"
			echo "KNOWN FAILURES CHECK: 0 NEW, 0 KNOWN (the failures above passed in an isolated rerun: flakes)"
			rm -f "$log" "$rlog"
			return 0
		fi
		echo "== GATE RETRY: the test(s) failed again in isolation; this is a failure, not a flake"
		rm -f "$log" "$rlog"
		return 1
	fi
	if gate_infra_failure "$log"; then
		echo "== GATE INFRA RETRY: the world produced no result (${first_line:-no detail}); running the whole list once more"
		flake_record infra "-" "$first_line"
		rm -f "$log"
		# shellcheck disable=SC2086
		DQ_GATE_FOCUSED_MAX_MIN="$(gate_cap_minutes $#)" $focused --force "$@"
		return $?
	fi
	rm -f "$log"
	return "$rc"
}
