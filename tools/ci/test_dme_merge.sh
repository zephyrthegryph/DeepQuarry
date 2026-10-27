#!/bin/bash
# Does merging a branch that still edits deepquarry.dme by hand give the right manifest? For each lane: merge it into HEAD in memory
# (git merge-tree, with the dq-dme merge driver that tools/dq_git_safe.sh supplies), then compare the merged manifest with a fresh
# regeneration over the merged tree's files (tools/build/gen_dme.py --root on an extract of the merged tree's .dm files).
#
#   bash tools/ci/test_dme_merge.sh [LANE...]     # default: every lane queued on the batch train whose diff touches deepquarry.dme
#
# Never touches the worktree, HEAD or the index. Exit 0 when every lane's merged manifest equals the regeneration; a lane that
# conflicts elsewhere is reported and skipped (that is the lane's own merge, not the manifest's).
set -u
cd "$(dirname "$0")/../.." || exit 2
# shellcheck source=tools/dq_git_safe.sh
source tools/dq_git_safe.sh
out="data/dme_merge_test"
mkdir -p "$out"
lanes=("$@")
if [ ${#lanes[@]} -eq 0 ]; then
	state="${DQ_TRAIN_STATE:-E:/dq-cache/train}"
	for q in "$state"/queue/*; do
		[ -f "$q" ] || continue
		b="$(grep -m1 '^branch=' "$q" 2>/dev/null | cut -d= -f2-)"
		[ -n "$b" ] || b="$(basename "$q" | sed 's/__/\//g')"
		lanes+=("$b")
	done
fi
status=0
checked=0
for lane in "${lanes[@]}"; do
	ref="$(git rev-parse -q --verify "$lane^{commit}" || git rev-parse -q --verify "origin/$lane^{commit}")" || { echo "?? $lane: no such branch"; continue; }
	base="$(git merge-base HEAD "$ref")"
	if git diff --quiet "$base" "$ref" -- deepquarry.dme; then
		continue
	fi
	checked=$((checked + 1))
	if ! tree="$(git merge-tree --write-tree --no-messages HEAD "$ref" | head -1)"; then
		echo "-- $lane: conflicts outside the manifest (skipped)"
		continue
	fi
	dir="$out/$(echo "$lane" | tr '/' '_')"
	rm -rf "$dir"
	mkdir -p "$dir"
	git archive "$tree" -- ':(glob)**/*.dm' ':(glob)**/*.dmf' ':(glob)**/*.dme' tools/build/dme_spec.txt | tar -x -C "$dir" || { echo "!! $lane: extract failed"; status=1; continue; }
	git show "$tree:deepquarry.dme" > "$dir/merged.dme"
	# The generated files are gitignored, so the extract lacks them; the spec's `file` lines include them anyway.
	python3 tools/build/gen_dme.py --root "$dir" --out "$dir/regen.dme" >/dev/null || { echo "!! $lane: regeneration failed"; status=1; continue; }
	if cmp -s "$dir/merged.dme" "$dir/regen.dme"; then
		added=$(git diff "$base" "$ref" -- deepquarry.dme | grep -c '^+#include' || true)
		removed=$(git diff "$base" "$ref" -- deepquarry.dme | grep -c '^-#include' || true)
		echo "ok $lane: merged manifest = regeneration (the lane added $added and removed $removed include line(s) by hand)"
		rm -rf "$dir"
	else
		echo "!! $lane: merged manifest differs from the regeneration ($dir/merged.dme vs $dir/regen.dme):"
		diff "$dir/merged.dme" "$dir/regen.dme" | head -10
		status=1
	fi
done
echo "test_dme_merge: $checked lane(s) edit the manifest"
exit $status
