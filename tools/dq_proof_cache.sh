#!/usr/bin/env bash
# Sourced by dq_merge_gates.sh and dq_lane_ready.sh: gate proofs keyed by TREE hash, shared by every worktree of the machine.
#
# A lane proves itself once, on its merge with master (dq_lane_ready.sh). What that run proved is a property of a TREE (the compile, the
# ratchets and the tests all read the tree, not the commit that carries it), so the proof is stored under the tree hash. When the merge
# agent merges the lane and master has not moved since, `git merge --no-ff` produces exactly the lane's tree: the merge is
# fast-forward-equivalent, the proof is found, and the gates neither rebuild nor retest. When master moved, the merged tree is new, no
# proof matches, and the gates prove the combination (smoke set, the lane's tests where its stamp is stale, compile, ratchets).
#
# A proof is a key=value file under DQ_PROOF_DIR (default E:/dq-cache/tree-proofs, else ~/.cache/dq/tree-proofs): tree, master, the test
# selectors that passed, the counts, whether the production compile + DreamChecker, tgui lint and the analyzer's cargo tests ran, and a
# copy of the test-run JSON. Written only by a fully passing run with no NEW failure. DQ_PROOF_REUSE=0 ignores proofs (always prove).

proof_dir() {
	if [ -n "${DQ_PROOF_DIR:-}" ]; then echo "$DQ_PROOF_DIR"
	elif [ -d E:/dq-cache ] || [ -d /e/dq-cache ]; then echo "E:/dq-cache/tree-proofs"
	else echo "$HOME/.cache/dq/tree-proofs"; fi
}

proof_tree() { git rev-parse "${1:-HEAD}^{tree}"; }

# proof_find <tree> <need_tgui 0|1> <need_analyze_tests 0|1> <selector...>: print the proof file when it covers all of them
proof_find() {
	local tree="$1" ntgui="$2" nan="$3" f t have inh g
	shift 3
	f="$(proof_dir)/$tree.proof"
	[ -f "$f" ] || return 1
	[ "$(sed -n 's/^new_failed=//p' "$f")" = 0 ] || return 1
	[ "$ntgui" -eq 0 ] || [ "$(sed -n 's/^tgui=//p' "$f")" = 1 ] || return 1
	[ "$nan" -eq 0 ] || [ "$(sed -n 's/^analyze_tests=//p' "$f")" = 1 ] || return 1
	have=" $(sed -n 's/^tests=//p' "$f") "
	# A lite re-proof (dq_lane_ready.sh --lite) ran only the lane's tests and the tests of what master gained, because master's own tree
	# already carried a passing proof of the rest: that proof's selectors count too, but only while it is itself a clean proof.
	inh="$(sed -n 's/^inherits=//p' "$f")"
	if [ -n "$inh" ] && [ -f "$(proof_dir)/$inh.proof" ]; then
		g="$(proof_dir)/$inh.proof"
		if [ "$(sed -n 's/^new_failed=//p' "$g")" = 0 ]; then have="$have $(sed -n 's/^tests=//p' "$g") "; fi
	fi
	for t in "$@"; do
		case "$have" in *" $t "*) ;; *) return 1 ;; esac
	done
	echo "$f"
}

# proof_store <tree> <master> <tests> <passed> <failed> <new_failed> <tgui> <analyze_tests> <tests_json> [inherits-tree]
proof_store() {
	local dir f tmp copy=""
	dir="$(proof_dir)"
	mkdir -p "$dir" 2>/dev/null || return 0
	f="$dir/$1.proof"
	if [ -n "${9:-}" ] && [ -f "$9" ]; then copy="$dir/$1.tests.json"; cp "$9" "$copy" 2>/dev/null || copy=""; fi
	tmp="$f.$$.tmp"
	{
		echo "tree=$1"
		echo "master=$2"
		echo "tests=$3"
		echo "passed=$4"
		echo "failed=$5"
		echo "new_failed=$6"
		echo "tgui=$7"
		echo "analyze_tests=$8"
		echo "dm=${DQ_PROOF_DM:-1}" # 0: a lane proof (tools/dq_merge_gates.sh --no-dm); the production compile was not run for this tree
		echo "tests_json=$copy"
		[ -z "${10:-}" ] || echo "inherits=${10}"
		echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} >"$tmp" && mv -f "$tmp" "$f"
}

# proof_alias <from-tree> <to-tree>: the same proof for a tree that differs only by what the proving run itself recorded (snapshots)
proof_alias() {
	local dir src
	dir="$(proof_dir)"
	src="$dir/$1.proof"
	[ -f "$src" ] && [ "$1" != "$2" ] || return 0
	sed "s/^tree=.*/tree=$2/" "$src" >"$dir/$2.proof.$$.tmp" && mv -f "$dir/$2.proof.$$.tmp" "$dir/$2.proof"
	[ -f "$dir/$1.tests.json" ] && cp "$dir/$1.tests.json" "$dir/$2.tests.json"
	sed -i "s#^tests_json=.*#tests_json=$dir/$2.tests.json#" "$dir/$2.proof" 2>/dev/null
	return 0
}

# proof_prune: keep the newest DQ_PROOF_KEEP (default 200) proofs
proof_prune() {
	local dir keep="${DQ_PROOF_KEEP:-200}"
	dir="$(proof_dir)"
	[ -d "$dir" ] || return 0
	ls -t "$dir"/*.proof 2>/dev/null | tail -n +"$((keep + 1))" | while read -r f; do rm -f "$f" "${f%.proof}.tests.json"; done
}

# proof_smoke_tests: the selectors every gate run includes (tools/ci/smoke_tests.txt and tools/ci/gameplay_tests.txt), one per line.
proof_smoke_tests() {
	local f line
	for f in tools/ci/smoke_tests.txt tools/ci/gameplay_tests.txt; do
		[ -f "$f" ] || continue
		while IFS= read -r line || [ -n "$line" ]; do
			line="${line%%#*}"
			line="${line//$''/}"
			read -r line <<<"$line" # trims the blanks with no fork (xargs per line cost seconds on Windows)
			[ -n "$line" ] && printf '%s
' "$line"
		done <"$f"
	done
	return 0
}

# proof_merge_tree <base-ref> <lane-ref>: the tree `git merge --no-ff <lane-ref>` would produce on <base-ref>, without touching any
# worktree or ref (git merge-tree). Fails (and prints nothing) when the merge conflicts.
proof_merge_tree() {
	local out
	out="$(git merge-tree --write-tree "$1" "$2" 2>/dev/null)" || return 1
	printf '%s\n' "${out%%$'\n'*}"
}

# proof_covers_merge <base-ref> <lane-ref>: exit 0 when the tree that merging <lane-ref> into <base-ref> produces already has a proof that
# covers the gate's usual list (smoke + gameplay, which a lane-ready proof contains), tgui lint and the analyzer tests where the diff needs
# them. Prints the tree on success. This is the cheap question "can this lane land without a gate run?"; dq_merge_gates.sh asks the same
# thing of the real merge and is the authority.
proof_covers_merge() {
	local tree
	tree="$(proof_merge_tree "$1" "$2")" || return 1
	proof_covers_tree "$1" "$tree" || return 1
	printf '%s
' "$tree"
}

# proof_covers_tree <base-ref> <tree> [extra selectors...]: the check above for a tree already in hand (the gates ask it of HEAD's tree).
# Silent; exit 0 when a proof covers the usual list plus the extra selectors, and tgui lint / analyzer tests where the diff against <base-ref> needs them.
proof_covers_tree() {
	local base="$1" tree="$2" tgui=0 an=0 tests=()
	shift 2
	git diff --quiet "$base" "$tree" -- tgui/ ':!tgui/packages/tgui/interfaces/generated' || tgui=1
	git diff --quiet "$base" "$tree" -- tools/analyze/ || an=1
	mapfile -t tests < <(proof_smoke_tests)
	proof_find "$tree" "$tgui" "$an" "${tests[@]}" "$@" >/dev/null
}

# proof_alias_baseline_shrink <tree-before> <tree-after>: the gates shrink ratchet baselines into the merge commit AFTER the tests ran, so the proof is
# stored under the shrunk tree while dq_land asks for the tree the plain merge makes (the unshrunk one) and would prove the lane again. A shrink
# only drops fixed sites from tools/ci/*_baseline.txt (analyze baseline --update never adds one), so when those files are the whole difference the
# proof of the shrunk tree also stands for the unshrunk one. Any other difference: no alias.
proof_alias_baseline_shrink() {
	local before="$1" after="$2" other
	[ -n "$before" ] && [ "$before" != "$after" ] || return 0
	other="$(git diff --name-only "$before" "$after" 2>/dev/null | grep -v -E '^tools/ci/[^/]*_baseline\.txt$' || true)"
	[ -z "$other" ] || return 0
	proof_alias "$after" "$before"
}
