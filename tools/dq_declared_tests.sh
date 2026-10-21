#!/usr/bin/env bash
# Shared rule for stamped test lists: a name that no `/datum/unit_test/` declares any more is dropped (and logged), never run.
# A lane stamped before master deleted or renamed a test still lists it; running it ends the gate with "no compiled /datum/unit_test
# type named '...'". Globs are kept (they match whatever exists). A name the user types on the command line is NOT filtered: a typo
# there must fail loudly (tools/dq_focused_test.sh, tools/dq_lane_ready.sh --tests). Sourced by tools/dq_merge_gates.sh (the lane
# stamp lists and the re-proof list) and tools/dq_lane_ready.sh (the lite re-proof list).
#
#   . tools/dq_declared_tests.sh
#   mapfile -t kept < <(filter_declared_tests "<where the list came from>" name...)   # kept names on stdout, drops on stderr
#
# DQ_DECLARED_TESTS_ROOT names the directory searched for declarations (default `code`; the self-test points it at a scratch tree).
filter_declared_tests() {
	local origin="$1" t declared
	shift
	declared=" $(grep -rhoE '^/datum/unit_test/[A-Za-z0-9_/]+' "${DQ_DECLARED_TESTS_ROOT:-code}" 2>/dev/null | sed 's#^/datum/unit_test/##' | tr '\n' ' ') "
	for t in "$@"; do
		[ -n "$t" ] || continue
		t="${t#/datum/unit_test/}"
		case "$t" in
			*'*'*|*'?'*) printf '%s\n' "$t" ;;
			*)
				case "$declared" in
					*" $t "*|*" ${t%%/*} "*) printf '%s\n' "$t" ;;
					*) echo "      -> dropped (no longer declared, $origin): $t" >&2 ;;
				esac
				;;
		esac
	done
}
