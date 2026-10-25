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

# validate_enqueue_tests <rev> name...: refuses (returns 1, reasons on stderr) a --tests name that the tree at <rev> cannot run:
#   - unknown: no `/datum/unit_test/<name>` is declared (nearest matches are listed);
#   - abstract parent: declared types exist below it (or it carries `abstract_type`), and naming a parent does not run its subtests
#     (the list of runnable subtests is printed: name those instead).
# A tree without code/modules/unit_tests (a scratch repo) is not validated. Globs pass. Uses one `git grep`, well under a second.
validate_enqueue_tests() {
	local rev="$1" bad=0
	shift
	git cat-file -e "$rev:code/modules/unit_tests" 2>/dev/null || return 0
	local decl
	decl="$(git grep -hE '^(/datum/unit_test/[A-Za-z0-9_/]+|[[:space:]]*abstract_type[[:space:]]*=[[:space:]]*/datum/unit_test/[A-Za-z0-9_/]+)' "$rev" -- code 2>/dev/null)" || true
	printf '%s\n' "$decl" | awk -v names="$*" '
		function note(t) { if (t != "" && !(t in decl)) decl[t] = 1 }
		{
			line = $0
			if (line ~ /abstract_type/) { sub(/^.*=[ \t]*\/datum\/unit_test\//, "", line); gsub(/[ \t\r]+$/, "", line); abs[line] = 1; note(line); next }
			sub(/^\/datum\/unit_test\//, "", line); gsub(/[ \t\r]+$/, "", line)
			if (line ~ /\(/) { if (line ~ /\/Run\(/) { sub(/\/Run\(.*$/, "", line); note(line) } next }
			if (line ~ /(^|\/)(proc|verb|var)(\/|$)/) next
			note(line)
		}
		END {
			# every ancestor of a declared type exists too
			for (t in decl) { p = t; while (sub(/\/[^\/]+$/, "", p)) child[p] = child[p] " " t }
			n = split(names, want, " ")
			for (i = 1; i <= n; i++) {
				w = want[i]; sub(/^\/datum\/unit_test\//, "", w)
				if (w == "" || w ~ /[*?]/) continue
				if (!(w in decl) && !(w in child)) {
					# nearest: names sharing a prefix of at least 8 characters, else containing the first 6
					pre = substr(w, 1, 8); k = 0; s = ""
					for (t in decl) if (index(t, pre) == 1 && k < 5) { s = s "\n      /datum/unit_test/" t; k++ }
					if (k == 0) { pre = substr(w, 1, 5); for (t in decl) if (index(t, pre) && k < 5) { s = s "\n      /datum/unit_test/" t; k++ } }
					printf "dq_train: REFUSED: /datum/unit_test/%s is not declared in this tree (the gate would run nothing for it).%s\n", w, (k ? " Nearest:" s : " No near matches.") > "/dev/stderr"
					bad = 1
				} else if ((w in child) || (w in abs)) {
					m = split(child[w], kids, " "); k = 0; s = ""
					for (j = 1; j <= m; j++) if (!(kids[j] in abs) && !((kids[j]) in child)) { s = s "\n      /datum/unit_test/" kids[j]; k++ }
					printf "dq_train: REFUSED: /datum/unit_test/%s is an abstract parent; naming it does not run its subtests. Name the runnable one(s):%s\n", w, (k ? s : " (none: it has no runnable subtests)") > "/dev/stderr"
					bad = 1
				}
			}
			exit bad
		}'
}
