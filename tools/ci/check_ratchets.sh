#!/usr/bin/env bash
# Ratcheted rewrite lints (doc/rewrite/roadmap.md, Guardrails). Each fails on a site not held in its
# fingerprint baseline (tools/ci/*_baseline.txt, printed as file:line); a justified keep is an inline
# `// ALLOW(<lint>): <reason>`. doc/rewrite/object_model_core.md sec 16 ("One way to do X") maps each
# banned alternative to the lint that counts it.
#
# One process runs them all: the analyze engine (tools/analyze, README there) loads the tree once,
# runs every lint in parallel, caches per file, then checks that every ALLOW annotation was used and
# gave a real reason. This script is the CI wrapper: it builds the engine when stale, runs it, and
# runs the two generator checks (Python, a few seconds) beside it.
#
#   bash tools/ci/check_ratchets.sh                      # every lint
#   bash tools/ci/check_ratchets.sh --lint scheduler     # extra arguments go to `analyze check`
#   tools/build/build.sh analyze                         # the same engine through the build tool
set -uo pipefail
# Below normal priority, for this script and everything it starts (cargo and rustc, the analyzer, git): the machine is also the user's desktop.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../dq_below_normal.sh"
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
failed=()

# DQ_ANALYZE_COLD=1 (the merge gates set it) runs gen and the lints with no cache they did not just fill: an empty private cache directory, no
# shared cache seed, no gen store. The result then depends on the tree alone, whatever the worktree's data/analyze-cache, the machine-wide
# E:/dq-cache/analyze-cache or the gen store hold. Costs a cold run (about a minute) instead of a warm one.
cold_cache=""
if [ "${DQ_ANALYZE_COLD:-0}" = "1" ]; then
	cold_cache="$(mktemp -d)"
	export DQ_ANALYZE_CACHE="$cold_cache" DQ_ANALYZE_SHARED_CACHE=off DQ_GEN_STORE=off
	trap '[ -n "$cold_cache" ] && rm -rf "$cold_cache"' EXIT
	echo "check_ratchets: cold mode (private analyze cache, no shared cache, no gen store)"
fi

# The Verdigris bindings are generated, not committed; the lints read them.
bash tools/ci/gen_verdigris_bindings.sh >/dev/null || exit 1

bin="$(bash tools/ci/analyze.sh)" || {
	echo "Ratchet lints failed: the analyze engine could not be built (is cargo installed?)"
	exit 1
}

# DQ_RATCHETS_SELFTESTS=changed (the merge gates set it): the self-tests of a tool (the disk budget, the test-scratch rule, the capability
# varmap generator's selftest) run only when that tool's own files changed since origin/master; they test the tool, not the tree. Unset
# or "all" (CI, by hand): every one runs.
# `--changed-only` is the quick local run: it defaults to "changed" too (the disk budget self-test alone is a minute), unless the variable is set.
case " $* " in *" --changed-only "*) : "${DQ_RATCHETS_SELFTESTS:=changed}" ;; esac
selftest_wanted() { # <regex of the tool's files>
	[ "${DQ_RATCHETS_SELFTESTS:-all}" = changed ] || return 0
	local base
	base="$(git merge-base origin/master HEAD 2>/dev/null)" || return 0
	git diff --name-only "$base" HEAD 2>/dev/null | grep -qE "$1" && return 0
	[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | awk '{print $2}' | grep -E "$1")" ]
}

# The generator checks stay Python: start them beside the engine.
gen_dir="$(mktemp -d)"
run_gen() { # <name> <script> <flag>
	( "$PY" "$2" "$3" >"$gen_dir/$1.out" 2>&1; echo $? >"$gen_dir/$1.rc" ) &
}
run_gen gen_capability_varmap_check tools/dx/gen_capability_varmap.py --check
gen_names=(gen_capability_varmap_check gen_dme_check)
if selftest_wanted '^tools/dx/'; then run_gen gen_capability_varmap_selftest tools/dx/gen_capability_varmap.py --selftest; gen_names+=(gen_capability_varmap_selftest)
else echo "check_ratchets: gen_capability_varmap --selftest skipped (tools/dx unchanged)"; fi
# deepquarry.dme is generated and committed: stale (a file added, moved or deleted without the build running), or a macro used before
# its #define in the generated order, fails here with the regenerate command (python3 tools/build/gen_dme.py).
run_gen gen_dme_check tools/build/gen_dme.py --check
if selftest_wanted '^tools/build/(gen_dme\.py|dme_spec\.txt)$'; then run_gen gen_dme_selftest tools/build/gen_dme.py --selftest; gen_names+=(gen_dme_selftest)
else echo "check_ratchets: gen_dme --selftest skipped (the generator is unchanged)"; fi

# Variant families (code/content/variants/README.md): VARIANT() keys exist, and a converted family gets no new data-only leaf type.
( "$PY" tools/ci/check_variants.py >"$gen_dir/check_variants.out" 2>&1; echo $? >"$gen_dir/check_variants.rc" ) &
gen_names+=(check_variants)
# The mapping dme (StrongDMM) and its stub types follow the variant tables.
( "$PY" tools/build/gen_mapping_dme.py --check >"$gen_dir/check_mapping_dme.out" 2>&1; echo $? >"$gen_dir/check_mapping_dme.rc" ) &
gen_names+=(check_mapping_dme)

# .gitattributes must name files that exist and merge drivers that exist (a move once left the _unit_tests.dm union rule dead).
( bash tools/ci/check_gitattributes.sh >"$gen_dir/gitattributes_check.out" 2>&1; echo $? >"$gen_dir/gitattributes_check.rc" ) &
gen_names+=(gitattributes_check)

# The generated DM (code/engine/_generated/, code/_generated/reads.dm, the tgui .d.ts) is not committed;
# every build writes it, and so does this, before the lints that read it. It fails on what still matters:
# a generator diagnostic (a bad declaration), a test-only type outside the guard, or a generated file
# missing from deepquarry.dme.
gen_out="$("$bin" gen 2>&1)"
gen_rc=$?
grep -v '^fresh ' <<<"$gen_out" || true
if [ "$gen_rc" != "0" ]; then
	failed+=("analyze gen")
fi

# Every lint runs here, check_grep included (it used to be excluded, so a failing check_grep passed this
# script while tools/ci/check_grep.sh and build.sh lint failed).
# The engine prints its own "All ratchet lints passed." when ITS lints pass; that line followed a failing tool self-test in the same output and read as an
# overall pass (31 October). Only this script's last line says it, so the engine's is renamed.
"$bin" check --ci "$@" | sed 's/^All ratchet lints passed\.$/analyze: all lints passed (the tool self-tests below decide the overall result)/'
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
	failed+=("analyze check")
fi

if ! selftest_wanted '^tools/(dq_disk_budget\.sh|ci/disk_budget\.toml|ci/test_disk_budget\.sh)$'; then echo "check_ratchets: test_disk_budget skipped (the disk budget is unchanged)"
elif ! bash "${DQ_RATCHETS_DISK_TEST:-tools/ci/test_disk_budget.sh}"; then   # the variable is the seam tools/ci/test_ratchets_selftest_fail.sh uses
	failed+=("test_disk_budget")
fi

# The quick shell self-tests of the lane tooling (each under 5 s); the slower ones (land, post_push_check, queue_not_counted, dmbc_current,
# move_candidates) are run by hand when their tool changes.
if ! selftest_wanted '^tools/(dq_[a-z_]+\.sh|ci/)'; then echo "check_ratchets: tool self-tests skipped (no tool script changed)"
else
	for _st in baseline_merge_driver cargo_target check_gitattributes focused_nested_names focused_sweep_notice focused_world_status stale_includes_generated vg_bindings_key; do
		if ! bash "tools/ci/test_${_st}.sh" >/dev/null 2>&1; then echo "check_ratchets: tools/ci/test_${_st}.sh FAILED" >&2; failed+=("test_${_st}"); fi
	done
fi
if ! selftest_wanted '^tools/dx/codemods/(type_trait|_guard)\.py$'; then echo "check_ratchets: type_trait selftest skipped (the codemod is unchanged)"
elif ! "$PY" tools/dx/codemods/type_trait.py --selftest; then
	failed+=("type_trait")
fi
if ! selftest_wanted '^tools/ci/dead_code_scan\.py$'; then echo "check_ratchets: dead_code_scan selftest skipped (the scan is unchanged)"
elif ! "$PY" tools/ci/dead_code_scan.py --selftest; then
	failed+=("dead_code_scan")
fi
# The design docs match the code: the gaps ledger's probes, the paths the docs name, the generated census of final_api.html section 19.
if ! "$PY" tools/ci/check_docs_truth.py; then
	failed+=("check_docs_truth")
fi
if ! selftest_wanted '^tools/ci/check_docs_truth\.py$'; then echo "check_ratchets: check_docs_truth selftest skipped (the checker is unchanged)"
elif ! "$PY" tools/ci/check_docs_truth.py --selftest; then
	failed+=("check_docs_truth_selftest")
fi
if ! selftest_wanted '\.rs$|^tools/ci/check_test_scratch\.sh$'; then echo "check_ratchets: check_test_scratch skipped (no Rust file changed)"
elif ! bash tools/ci/check_test_scratch.sh; then
	failed+=("check_test_scratch")
fi

wait
for name in "${gen_names[@]}"; do
	echo "::group::$name"
	cat "$gen_dir/$name.out"
	if [ "$(cat "$gen_dir/$name.rc" 2>/dev/null || echo 1)" != "0" ]; then
		failed+=("$name")
	fi
	echo "::endgroup::"
done
rm -rf "$gen_dir"

if [ ${#failed[@]} -gt 0 ]; then
	echo "Ratchet lints failed: ${failed[*]}"
	exit 1
fi
echo "All ratchet lints passed."
