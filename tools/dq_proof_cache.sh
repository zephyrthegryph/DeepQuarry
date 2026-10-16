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
	local tree="$1" ntgui="$2" nan="$3" f t have
	shift 3
	f="$(proof_dir)/$tree.proof"
	[ -f "$f" ] || return 1
	[ "$(sed -n 's/^dm=//p' "$f")" = 1 ] || return 1
	[ "$(sed -n 's/^new_failed=//p' "$f")" = 0 ] || return 1
	[ "$ntgui" -eq 0 ] || [ "$(sed -n 's/^tgui=//p' "$f")" = 1 ] || return 1
	[ "$nan" -eq 0 ] || [ "$(sed -n 's/^analyze_tests=//p' "$f")" = 1 ] || return 1
	have=" $(sed -n 's/^tests=//p' "$f") "
	for t in "$@"; do
		case "$have" in *" $t "*) ;; *) return 1 ;; esac
	done
	echo "$f"
}

# proof_store <tree> <master> <tests> <passed> <failed> <new_failed> <tgui> <analyze_tests> <tests_json>
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
		echo "dm=1"
		echo "tests_json=$copy"
		echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} >"$tmp" && mv -f "$tmp" "$f"
}

# proof_alias <from-tree> <to-tree>: the same proof for a tree that differs only by what the proving run itself recorded (look keys, snapshots)
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
