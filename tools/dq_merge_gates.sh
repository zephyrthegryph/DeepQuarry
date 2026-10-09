#!/usr/bin/env bash
# The minimal pre-test gates of a merge batch, run once, on the merged HEAD:
#
#   bash tools/dq_merge_gates.sh [--no-boot] [--tgui]
#
#   1. gen              tools/build/build.sh gen                       (analyze gen: generated DM and TGUI types)
#   2. test build+boot  tools/dq_focused_test.sh --boot                (compiles the unit-test .dmb, boots it, boot gate)
#   3. ratchets         tools/ci/check_ratchets.sh                     (analyze check --ci, gen checks)
#   4. tgui lint        tools/build/build.sh tgui-lint                 (only when the batch touches tgui/, or with --tgui)
#
# What it leaves out on purpose, because tools/dq_push_master.sh runs it on the final HEAD and fails closed:
# the production build.sh dm (DreamMaker without UNIT_TESTS), DreamChecker, build.sh analyze, and the second merge of
# origin/master. build.sh lint is DreamChecker + analyze + tgui lint, so it added nothing but a repeat. A merge agent
# runs this once after merging; do not rerun gen/lint/ratchets by hand before the tests.
#
# Step 2 leaves the compiled test .dmb in the compile-hash cache, so the focused batch that follows reuses it (no
# second compile). On success the script writes data/merge-gates/<sha>.ok; dq_push_master.sh skips its own ratchets
# run when that stamp names the exact HEAD and the tree is unchanged (analyze, dm and DreamChecker still run there).
# Timings land in data/merge-gates/<sha>.timings. Exit status: 0 all gates passed, 1 a gate failed (first failure stops).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DQ_ANALYZE_PROFILE=release # the same analyzer the push gate uses, so the stamp means the same thing

boot=1
tgui=0
for arg in "$@"; do
	case "$arg" in
		--no-boot) boot=0 ;;
		--tgui) tgui=1 ;;
		-h|--help) sed -n '2,19p' "$0"; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

git update-index -q --refresh >/dev/null 2>&1
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dq_merge_gates: REFUSED: uncommitted changes to tracked files; commit the merge first (the stamp names an exact HEAD)" >&2
	exit 1
fi
sha="$(git rev-parse HEAD)"
mkdir -p data/merge-gates
timings="data/merge-gates/${sha:0:12}.timings"
rm -f "data/merge-gates/${sha:0:12}.ok" "data/merge-gates/${sha:0:12}.ratchets.ok"
: >"$timings"

if [ "$tgui" -eq 0 ] && git rev-parse -q --verify origin/master >/dev/null; then
	if ! git diff --quiet "$(git merge-base origin/master HEAD)" HEAD -- tgui/ ':!tgui/packages/tgui/interfaces/generated'; then tgui=1; fi
fi

gate() { # <name> <command...>
	local name="$1" t0 rc
	shift
	echo "== gate: $name"
	t0=$(date +%s)
	"$@"
	rc=$?
	echo "$name $(( $(date +%s) - t0 ))s rc=$rc" | tee -a "$timings"
	if [ "$rc" -ne 0 ]; then
		echo "dq_merge_gates: FAILED at '$name' (exit $rc); fix it, recommit, rerun" >&2
		exit 1
	fi
}

gate gen tools/build/build.sh gen
if [ "$boot" -eq 1 ]; then gate test-build-boot bash tools/dq_focused_test.sh --boot; fi
gate ratchets bash tools/ci/check_ratchets.sh
if [ "$tgui" -eq 1 ]; then gate tgui-lint tools/build/build.sh tgui-lint; fi

git update-index -q --refresh >/dev/null 2>&1
if [ "$(git rev-parse HEAD)" != "$sha" ] || ! git diff --quiet || ! git diff --cached --quiet; then
	echo "dq_merge_gates: the tree changed during the gates; not stamping" >&2
	exit 1
fi
echo "$sha" >"data/merge-gates/${sha:0:12}.ratchets.ok"
{ echo "sha=$sha"; echo "boot=$boot"; echo "tgui=$tgui"; } >"data/merge-gates/${sha:0:12}.ok"
echo "dq_merge_gates: all gates passed on ${sha:0:12} (timings: $timings)"
