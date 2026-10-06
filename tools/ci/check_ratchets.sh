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
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
failed=()

bin="$(bash tools/ci/analyze.sh)" || {
	echo "Ratchet lints failed: the analyze engine could not be built (is cargo installed?)"
	exit 1
}

# The generator checks stay Python: start them beside the engine.
gen_dir="$(mktemp -d)"
run_gen() { # <name> <script> <flag>
	( "$PY" "$2" "$3" >"$gen_dir/$1.out" 2>&1; echo $? >"$gen_dir/$1.rc" ) &
}
run_gen gen_capability_varmap_check tools/dx/gen_capability_varmap.py --check
run_gen gen_capability_varmap_selftest tools/dx/gen_capability_varmap.py --selftest

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
if ! "$bin" check --ci "$@"; then
	failed+=("analyze check")
fi

wait
for name in gen_capability_varmap_check gen_capability_varmap_selftest; do
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
