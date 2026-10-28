#!/usr/bin/env bash
# The cheap checks of a light batch, for exactly what changed (no DM compile, no test world):
#
#   bash tools/dq_light_checks.sh <base> <head>     # exit 0 when every check for the changed files passed
#
#   - bash -n on every changed *.sh (and shellcheck -S error when it is installed);
#   - doc links: every relative link in a changed *.md / doc/*.html must resolve to a file in <head>;
#   - cargo test for every Cargo manifest above a changed file under tools/ or verdigris/ (inside a machine cargo slot);
#   - the ratchets (tools/ci/check_ratchets.sh) only when a .dm file changed or a lint input did (tools/analyze, lint_scopes.toml, baselines, check_*.sh);
#   - the self-test of each changed tool (tools/ci/test_*.sh, mapped from the tool; test_train.sh only for the train / merge drivers), each capped;
#   - a changed heavy path (tools/dq_light_paths.sh) is a refusal: a light batch never carries it.
# DQ_LIGHT_CARGO=0 skips cargo (fixture tests). Run from the worktree that holds <head>.
set -uo pipefail
# light_cargo_target_args <manifest>: the --target a crate's tests need. The verdigris crates link byondapi-sys, which builds only for
# the 32-bit target BYOND loads (28 October: perf/frame-stalls failed "BYOND API only functions with 32-bit/x86 targets" on the 64-bit
# host target): on Windows they test as verdigris builds, i686-pc-windows-msvc (DQ_LIGHT_VERDIGRIS_TARGET overrides).
light_cargo_target_args() {
	case "$1" in
		verdigris/*) case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) echo "--target ${DQ_LIGHT_VERDIGRIS_TARGET:-i686-pc-windows-msvc}" ;; *) [ -z "${DQ_LIGHT_VERDIGRIS_TARGET:-}" ] || echo "--target $DQ_LIGHT_VERDIGRIS_TARGET" ;; esac ;;
	esac
}
[ "${1:-}" != --target-args ] || { light_cargo_target_args "$2"; exit 0; }
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_light_paths.sh"
base="${1:?base}"; head="${2:-HEAD}"
# The lane's own changes: diff from the merge base, never from <base> itself. A precheck merged onto an older master is diffed
# against a newer origin/master when master moved meanwhile, and a two-dot diff then counted master's own landings as the
# lane's (28 October: a docs-only lane was bounced for "heavy paths" from 24dac9cec2).
mb="$(git merge-base "$base" "$head" 2>/dev/null)" && [ -n "$mb" ] && base="$mb"
fail=0
bad() { echo "light check FAILED: $*" >&2; fail=1; }
mapfile -t changed < <(git diff --name-only --diff-filter=ACMR "$base" "$head")
mapfile -t deleted < <(git diff --name-only --diff-filter=D "$base" "$head")
echo "== light checks: ${#changed[@]} changed file(s), ${#deleted[@]} deleted"

heavy="$(git diff --name-only "$base" "$head" | while IFS= read -r f; do light_heavy_path "$f" && echo "$f"; done)"
[ -z "$heavy" ] || bad "heavy paths in a light batch (use a general lane): $(echo "$heavy" | head -5 | tr '\n' ' ')"

for f in "${changed[@]}"; do
	case "$f" in *.sh) bash -n "$f" 2>&1 || bad "bash -n $f"; command -v shellcheck >/dev/null 2>&1 && { shellcheck -S error "$f" || bad "shellcheck $f"; } ;; esac
done

check_links() { # <file>
	local file="$1" dir t target
	dir="$(dirname "$file")"
	while IFS= read -r t; do
		target="${t%%#*}"; target="${target%%\?*}"
		[ -n "$target" ] || continue
		case "$target" in http:*|https:*|mailto:*|data:*|javascript:*|//*) continue ;; esac
		case "$target" in /*) target="${target#/}" ;; *) target="$dir/$target" ;; esac
		git cat-file -e "$head:$(realpath -m --relative-to=. "$target" 2>/dev/null || echo "$target")" 2>/dev/null || bad "$file links to $t, which does not exist"
	done < <(
		case "$file" in
			*.md) git show "$head:$file" | grep -o -E '\]\([^)[:space:]]+\)' | sed -E 's/^\]\((.*)\)$/\1/' ;;
			*) git show "$head:$file" | grep -o -E '(href|src)="[^"]+"' | sed -E 's/^[a-z]+="(.*)"$/\1/' ;;
		esac
	)
}
for f in "${changed[@]}"; do
	case "$f" in *.md|doc/*.html) check_links "$f" ;; esac
done


if [ "${DQ_LIGHT_CARGO:-1}" = 1 ]; then
	declare -A manifests=()
	for f in "${changed[@]}"; do
		case "$f" in tools/*|verdigris/*) ;; *) continue ;; esac
		d="$(dirname "$f")"
		while [ "$d" != "." ] && [ "$d" != "/" ]; do
			if git cat-file -e "$head:$d/Cargo.toml" 2>/dev/null; then manifests["$d/Cargo.toml"]=1; break; fi
			d="$(dirname "$d")"
		done
	done
	# every workspace crate that depends on a changed crate runs its tests too (cargo's reverse-dependency set, tools/light_cargo_rdeps.py)
	if [ ${#manifests[@]} -gt 0 ] && [ -f tools/light_cargo_rdeps.py ]; then
		while IFS= read -r rd; do
			[ -n "$rd" ] && [ -z "${manifests[$rd]:-}" ] || continue
			manifests["$rd"]=1
			echo "== cargo: $rd depends on a changed crate; its tests run too"
		done < <(python3 tools/light_cargo_rdeps.py "${!manifests[@]}" 2>/dev/null)
	fi
	for m in "${!manifests[@]}"; do
		targs="$(light_cargo_target_args "$m")"
		echo "== cargo test --manifest-path $m${targs:+ $targs}"
		# Built outside the worktree (tools/dq_cargo_target.sh): a gate must never leave a debug target in the merge worktree.
		CARGO_TARGET_DIR="$(bash tools/dq_cargo_target.sh "light-$(echo "$m" | tr '/' '-')")" \
			bash tools/dq_machine_slots.sh run cargo --label "light-batch $m" -- env CARGO_INCREMENTAL=0 cargo test --manifest-path "$m" $targs || bad "cargo test $m"
	done
fi

all_changed="$(printf '%s\n' "${changed[@]}" "${deleted[@]}")"
# The ratchets read the tree and the lints: they run when a .dm file or a lint input changed, not for every file under tools/ci
# (a self-test script or a tool edit changes no lint verdict). A tool's own self-test inside check_ratchets runs only when its files changed.
if grep -q -E '\.dm$|^tools/analyze/|^tools/ci/(lint_scopes\.toml|check_[^/]*|[^/]*baseline[^/]*|[^/]*\.txt)$' <<<"$all_changed"; then
	echo "== ratchets (a .dm file or a lint input changed)"
	DQ_RATCHETS_SELFTESTS=changed bash tools/ci/check_ratchets.sh || bad "check_ratchets.sh"
fi

# Self-tests of the tools a lane changed (never the whole tools/ci/test_*.sh set): a changed tools/ci/test_X.sh runs itself; a changed tool runs the
# test that covers it (tools/dq_X.sh -> tools/ci/test_X.sh when it exists, plus the explicit map below). test_train.sh runs only when the train or the
# merge drivers change. Each self-test is capped (DQ_LIGHT_SELFTEST_CAP_SEC, default 300 s) so a slow one fails loudly instead of holding the precheck.
declare -A selftests=()
add_selftest() { [ -f "tools/ci/$1" ] && selftests["$1"]=1; }
for f in "${changed[@]}"; do
	case "$f" in
		tools/ci/test_*.sh) add_selftest "$(basename "$f")" ;;
		tools/dq_train.sh|tools/dq_train_estimate.js|tools/dq_merge_batch.sh|tools/dq_merge_gates.sh|tools/dq_gate_retry.sh|tools/dq_gate_verdicts.sh|tools/dq_declared_tests.sh|tools/train/*) add_selftest test_train.sh; add_selftest test_train_decisions.sh ;;
		tools/dq_light_paths.sh|tools/dq_land_batch.sh) add_selftest test_light_checks.sh ;;
		tools/dq_light_checks.sh) add_selftest test_light_checks.sh; add_selftest test_train_decisions.sh ;;
		tools/dq_stale_includes.sh|tools/dq_merge_master.sh|tools/light_cargo_rdeps.py) add_selftest test_train_decisions.sh ;;
		tools/ci/lint_scopes_merge_driver.sh|tools/dq_git_safe.sh) add_selftest test_train_decisions.sh ;;
		tools/dq_*.sh) add_selftest "test_$(basename "$f" .sh | sed 's/^dq_//').sh" ;;
	esac
done
cap="${DQ_LIGHT_SELFTEST_CAP_SEC:-300}"
for t in "${!selftests[@]}"; do
	echo "== self-test tools/ci/$t (cap ${cap}s)"
	t0=$(date +%s)
	# test_train.sh: only its quick subset (enqueue, light) is on the critical path; the full file runs by hand
	tt_only=""; [ "$t" != test_train.sh ] || tt_only="quick"
	TEST_TRAIN_ONLY="$tt_only" timeout -k 10 "$cap" bash "tools/ci/$t" >"${TMPDIR:-/tmp}/light-selftest-$$.log" 2>&1; rc=$?
	echo "   $t rc=$rc in $(( $(date +%s) - t0 ))s"
	if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
		# a cap is not a verdict: on a loaded machine a healthy self-test can run past it. The cases that finished are shown; nothing is failed, the author ran the test.
		echo "light check WARNING: $t hit its ${cap}s cap and was stopped (inconclusive, not a failure); the cases that finished:" >&2
		grep -E '^(PASS|FAIL)' "${TMPDIR:-/tmp}/light-selftest-$$.log" >&2
		grep -q '^FAIL' "${TMPDIR:-/tmp}/light-selftest-$$.log" && bad "self-test $t (a case failed before the cap)"
	elif [ "$rc" -ne 0 ]; then
		tail -n 25 "${TMPDIR:-/tmp}/light-selftest-$$.log" >&2
		bad "self-test $t"
	fi
	rm -f "${TMPDIR:-/tmp}/light-selftest-$$.log"
done
[ "$fail" -eq 0 ] && echo "== light checks passed" || exit 1
