#!/usr/bin/env bash
# Ratcheted rewrite lints (doc/rewrite/roadmap.md, Guardrails). Each fails on a site not held in its
# fingerprint baseline (tools/ci/*_baseline.txt, printed as file:line); a justified keep is an inline
# `// ALLOW(<lint>): <reason>`. doc/rewrite/object_model_core.md sec 16 ("One way to do X") maps each
# banned alternative to the lint that counts it.
#
# The lints run in ONE process: the analyze engine (tools/analyze, README there), which loads the
# tree once, runs every ported lint in parallel and caches per file. This script is its CI wrapper.
# Lints not ported yet still run here as their Python scripts (LEGACY below shrinks to nothing).
set -uo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
failed=()
# Every lint (engine and legacy Python alike) appends the ALLOW annotations that kept a site to this
# file; the unused-ALLOW check at the end reads it once all of them have run.
allow_usage="data/allow_usage.tsv"
mkdir -p data
: > "$allow_usage"
export DQ_ALLOW_USAGE="$allow_usage"

bin="$(bash tools/ci/analyze.sh)" || {
	echo "Ratchet lints failed: the analyze engine could not be built (is cargo installed?)"
	exit 1
}

# The generator checks stay Python (a few seconds each): start them beside the engine.
gen_dir="$(mktemp -d)"
run_gen() { # <name> <script> <flag>
	( "$PY" "$2" "$3" >"$gen_dir/$1.out" 2>&1; echo $? >"$gen_dir/$1.rc" ) &
}
run_gen gen_capability_varmap_check tools/dx/gen_capability_varmap.py --check
run_gen gen_capability_varmap_selftest tools/dx/gen_capability_varmap.py --selftest
run_gen gen_om_notices_check tools/dx/gen_om_notices.py --check

if ! "$bin" check --ci --lint -check_grep "$@"; then
	failed+=("analyze check")
fi

# Lints still on their legacy Python scripts (ported ones run in the engine above).
LEGACY=(
	scheduler_lints.py
	ownership_lint.py
	tracked_lint.py
)
for lint in "${LEGACY[@]}"; do
	echo "::group::$lint"
	if ! "$PY" "tools/ci/$lint"; then
		failed+=("$lint")
	fi
	echo "::endgroup::"
done
echo "::group::tracked_lint.py --selftest"
if ! "$PY" tools/ci/tracked_lint.py --selftest; then
	failed+=("tracked_lint.py --selftest")
fi
echo "::endgroup::"

wait
unset DQ_ALLOW_USAGE
echo "::group::allow_annotations.py --unused"
if ! "$PY" tools/ci/allow_annotations.py --unused "$allow_usage"; then
	failed+=("allow_annotations.py --unused")
fi
echo "::endgroup::"
rm -f "$allow_usage"
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
