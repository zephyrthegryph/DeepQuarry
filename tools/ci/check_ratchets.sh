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
run_gen gen_om_notices_check tools/dx/gen_om_notices.py --check

# check_grep has its own entry point (tools/ci/check_grep.sh); it is excluded here as it always was.
if ! "$bin" check --ci --lint -check_grep "$@"; then
	failed+=("analyze check")
fi

wait
for name in gen_capability_varmap_check gen_capability_varmap_selftest gen_om_notices_check; do
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
