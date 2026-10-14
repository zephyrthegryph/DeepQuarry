#!/usr/bin/env bash
# look_keys.txt is the record of VERIFIED look keys: one line per concrete /obj, /mob and /turf type, three tab-separated columns
# (type, key, probes), written only for a type whose look pins (dq_look_state_pin, dq_look_tree_pin) were actually probed and matched
# at that key. It is NOT a function of the tree. The analyzer's CURRENT keys (`analyze look-keys`) are a separate, generated, gitignored
# file, data/look-plan.tsv. A type whose current key differs from its recorded key, or that has no recorded row, is UNVERIFIED and is
# probed by the next look-pin run (a lane's, the merge gates'); nothing but a passing pin run (or --bless) may write a key.
#
#   bash tools/ci/check_look_keys_format.sh                   # format check: 3 columns, 16-hex key, one row per type (no currency demand)
#   bash tools/ci/check_look_keys_format.sh --normalize       # make the file canonical after a union merge; NEVER adds or changes a key
#   bash tools/ci/check_look_keys_format.sh --commit          # --normalize, then commit the file if it changed (merge scripts)
#   bash tools/ci/check_look_keys_format.sh --unverified      # write data/look-plan.tsv, print how many types are unverified (--list: the types)
#   bash tools/ci/check_look_keys_format.sh --diff PLAN       # print the types of PLAN (an `analyze look-keys` file) that are unverified
#   bash tools/ci/check_look_keys_format.sh --record PLAN [ONLY]
#                                                              # called by dq_focused_test.sh after a PASSING pin run: record PLAN's rows
#                                                              # for the types in ONLY (the file of types it probed; none = it probed all)
#                                                              # and for those already verified at the same key
#
# --normalize only DROPS rows (a type gone from the tree, or one a merge left with several different keys), so the worst a merge can do
# is turn a verified type back into an unverified one. A row is verified for the tree when its (type, key) equals the analyzer's current
# pair, so a union-merged file holding both sides' rows keeps exactly the rows that are true. DQ_LOOK_KEYS_FILE overrides the path and DQ_LOOK_PLAN_FILE replaces the analyzer (tests).
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="check"
list=0
args=()
while [ $# -gt 0 ]; do
	case "$1" in
		--normalize) mode="normalize" ;;
		--commit) mode="commit" ;;
		--unverified) mode="unverified" ;;
		--list) list=1 ;;
		--diff) mode="diff" ;;
		--record) mode="record" ;;
		--regen) echo "check_look_keys_format: --regen is gone: the file records probed keys, not the tree's keys; use --normalize" >&2; exit 2 ;;
		*) args+=("$1") ;;
	esac
	shift
done
f="${DQ_LOOK_KEYS_FILE:-code/modules/unit_tests/snapshots/look_keys.txt}"
plan_default="data/look-plan.tsv"

plan() { # <out>: write the analyzer's current keys
	local bin out="$1"
	# DQ_LOOK_PLAN_FILE stands in for the analyzer (tests).
	if [ -n "${DQ_LOOK_PLAN_FILE:-}" ]; then cp "$DQ_LOOK_PLAN_FILE" "$1"; return 0; fi
	bin="$(bash tools/ci/analyze.sh)" || { echo "check_look_keys_format: the analyze engine could not be built" >&2; return 1; }
	# The analyzer is a Windows program: an MSYS path such as /tmp/x (TMPDIR=/tmp) is E:/tmp/x to it, not the file bash reads.
	command -v cygpath >/dev/null 2>&1 && out="$(cygpath -m "$1")"
	"$bin" look-keys --out "$out" >/dev/null || { echo "check_look_keys_format: analyze look-keys failed" >&2; return 1; }
	[ -s "$1" ] || { echo "check_look_keys_format: analyze look-keys wrote an empty plan" >&2; return 1; }
}

unverified_of() { # <plan>: the plan's types whose (type, key) is not a recorded row
	awk -F'\t' 'FILENAME == ARGV[1] { ok[$1 "\t" $2] = 1; next } !(($1 "\t" $2) in ok) { print $1 }' "$f" "$1"
}

case "$mode" in
check)
	[ -f "$f" ] || { echo "check_look_keys_format: $f is missing" >&2; exit 1; }
	bad="$(awk -F'\t' 'NF != 3 || $1 !~ /^\// || $2 !~ /^[0-9a-f]{16}$/ { n++ } END { print n + 0 }' "$f")"
	if [ "$bad" -ne 0 ]; then
		echo "check_look_keys_format: $bad line(s) in $f are not \`type TAB 16-hex-key TAB probes\`" >&2
		exit 1
	fi
	dup="$(awk -F'\t' '$1 in seen { n++ } { seen[$1] = 1 } END { print n + 0 }' "$f")"
	if [ "$dup" -ne 0 ]; then
		echo "check_look_keys_format: $dup type(s) in $f have more than one row (a union merge); fix: bash tools/ci/check_look_keys_format.sh --normalize" >&2
		exit 1
	fi
	;;
normalize|commit)
	[ -f "$f" ] || : >"$f"
	tmp="$(mktemp)"
	trap 'rm -f "$tmp" "${tmp}.plan"' EXIT
	have_plan=0
	if plan "${tmp}.plan" 2>/dev/null; then have_plan=1; else : >"${tmp}.plan"; fi
	# Per type: keep the row equal to the analyzer's current pair (verified for this tree); else keep the single distinct row (a stale
	# marker, harmless); several different keys with none current are ambiguous: drop them. A type absent from the plan is gone: drop it.
	awk -F'\t' -v have_plan="$have_plan" '
		FILENAME == ARGV[1] && have_plan == 1 { cur[$1] = $2; next }
		FILENAME == ARGV[1] { next }
		NF != 3 { next }
		{
			if (!($1 in order)) { order[$1] = ++n; name[n] = $1 }
			rowkey = $1 "\t" $2
			if (!(rowkey in seen)) { seen[rowkey] = 1; nkeys[$1]++; line[$1 "\t" nkeys[$1]] = $0; keyat[$1 "\t" nkeys[$1]] = $2 }
		}
		END {
			for (i = 1; i <= n; i++) {
				t = name[i]
				if (have_plan == 1 && !(t in cur)) continue
				out = ""
				for (j = 1; j <= nkeys[t]; j++) if (have_plan == 1 && keyat[t "\t" j] == cur[t]) out = line[t "\t" j]
				if (out == "" && nkeys[t] == 1) out = line[t "\t" 1]
				if (out != "") print out
			}
		}' "${tmp}.plan" "$f" >"$tmp"
	if cmp -s "$tmp" "$f"; then
		echo "check_look_keys_format: $f already canonical"
		exit 0
	fi
	cp "$tmp" "$f"
	echo "check_look_keys_format: normalized $f (rows dropped or merged, no key changed)"
	if [ "$mode" = "commit" ]; then
		git add -- "$f"
		git commit -q -m "Normalize look_keys.txt after the merge (verified rows only)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" -- "$f"
	fi
	;;
unverified)
	mkdir -p "$(dirname "$plan_default")"
	plan "$plan_default" || exit 1
	tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
	unverified_of "$plan_default" >"$tmp"
	if [ "$list" -eq 1 ]; then cat "$tmp"; else echo "$(wc -l <"$tmp" | tr -d ' ') of $(wc -l <"$plan_default" | tr -d ' ') types unverified"; fi
	;;
diff)
	[ -n "${args[0]:-}" ] && [ -f "${args[0]}" ] || { echo "usage: check_look_keys_format.sh --diff PLAN" >&2; exit 2; }
	[ -f "$f" ] || : >"$f"
	unverified_of "${args[0]}"
	;;
record)
	p="${args[0]:-}"
	only="${args[1]:-}"
	[ -n "$p" ] && [ -s "$p" ] || { echo "usage: check_look_keys_format.sh --record PLAN [ONLY]" >&2; exit 2; }
	[ -f "$f" ] || : >"$f"
	tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
	# Third input: the probed types. Absent (an empty or missing ONLY with no argument) means the run probed every type.
	if [ -n "$only" ]; then
		[ -f "$only" ] || { echo "check_look_keys_format: no such probed-types file: $only" >&2; exit 2; }
		awk -F'\t' -v all=0 'FILENAME == ARGV[1] { ok[$1 "\t" $2] = 1; next } FILENAME == ARGV[2] { probed[$1] = 1; next } probed[$1] || (($1 "\t" $2) in ok) { print }' "$f" "$only" "$p" >"$tmp"
	else
		cp "$p" "$tmp"
	fi
	cp "$tmp" "$f"
	echo "check_look_keys_format: recorded $(wc -l <"$f" | tr -d ' ') verified type keys in $f"
	;;
esac
