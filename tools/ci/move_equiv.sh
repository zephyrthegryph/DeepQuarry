#!/bin/bash
# Before/after equivalence for file moves: compile the world before and after a move with DreamMaker and compare the two with
# dmb-equiv, mapping every moved file's old source path to its new one.
#
#   bash tools/ci/move_equiv.sh BEFORE AFTER [-- extra dmb-equiv flags]
#
# BEFORE and AFTER are git revisions (commit, tag, HEAD~3, ...): the parent of the first move commit and the last commit of the
# move series (the pure `git mv` commit, the .dme path commit and the lint_scopes path commit).
#
# NEVER CHECK OUT. `git checkout` (any form), `git switch`, `git reset`, `git restore` and `git stash` are banned (AGENTS.md section 4,
# "Git safety"), in a lane worktree too. This script never changes the worktree's HEAD, index or files: each revision is extracted
# with `git archive <rev> | tar -x` into its own scratch directory under the output directory and built from there.
#
# What it does
#   1. builds dmb-equiv from the worktree (older trees may not have `--path-map`),
#   2. lists the move with `git diff --name-status -M100% BEFORE AFTER`: every pure rename (R100) becomes an `OLD=NEW` path-map line,
#      and every other changed file is printed so a change that is not a move is visible (the .dme and tools/ci/lint_scopes.toml are
#      expected to change),
#   3. extracts both revisions, gives each extract a fresh `git init` (build.ts refuses to build unless its root is the git toplevel)
#      and the worktree's icons/gen (DQ_ICON_SEED), and compiles the production world and the unit-test world (-DCIBUILDING
#      -DCITESTING) of each with DreamMaker (DQ_COMPILER=dreammaker, strict), keeping the compile logs,
#   4. compares each flavour's before/after worlds (dmb-equiv --all, default order policy: type, proc and var-name table order
#      gates; debug streams included) with the map, and compares the compilers' warning and error counts.
#
# Exit 0 only when both worlds are EQUIVALENT and the counts match. The map rewrites only string constants equal to or prefixed by a
# moved file's old path, in the BEFORE world only (tools/dmb/crates/dmb-equiv/EQUIVALENCE.md "Path map"), so any other difference
# is still reported. --ignore-order is never passed.
#
#   DQ_MOVE_EQUIV_DIR      where extracts, worlds, logs and reports go (default data/move_equiv, gitignored)
#   DQ_MOVE_EQUIV_FLAVORS  subset of "production test" (default both)
#   DQ_MOVE_EQUIV_OVERLAY  space-separated paths (default none) copied from the worktree's HEAD over BOTH extracts before building, for
#                          checking a move against a generator fix that the older revisions lack (for example "tools/analyze/src")
#   DQ_MOVE_EQUIV_PLAIN=1  compare without any path map (any two revisions; paths that moved are then reported)
#   DQ_MOVE_EQUIV_KEEP=1   keep the extracted source trees (about 1.4 GB each); by default they are deleted after the compiles
set -u
cd "$(dirname "$0")/../.." || exit 2
root=$(pwd)

if [ $# -lt 2 ]; then
  echo "usage: bash tools/ci/move_equiv.sh BEFORE AFTER [-- extra dmb-equiv flags]" >&2
  exit 2
fi
before_rev=$1
after_rev=$2
shift 2
extra=()
if [ "${1:-}" = "--" ]; then shift; extra=("$@"); fi

out="${DQ_MOVE_EQUIV_DIR:-data/move_equiv}"
flavors="${DQ_MOVE_EQUIV_FLAVORS:-production test}"
overlay="${DQ_MOVE_EQUIV_OVERLAY:-}"

before=$(git rev-parse --verify "$before_rev^{commit}") || exit 2
after=$(git rev-parse --verify "$after_rev^{commit}") || exit 2

mkdir -p "$out"
out=$(cd "$out" && pwd)

# 1. dmb-equiv from the worktree.
bash tools/dq_machine_slots.sh run cargo -- cargo build --release --manifest-path tools/dmb/Cargo.toml -p dmb-equiv || exit 2
equiv_src=tools/dmb/target/release/dmb-equiv
[ -x "$equiv_src" ] || equiv_src=tools/dmb/target/release/dmb-equiv.exe
[ -x "$equiv_src" ] || { echo "move_equiv: no dmb-equiv binary" >&2; exit 2; }
equiv="$out/$(basename "$equiv_src")"
cp "$equiv_src" "$equiv"

# 2. The move, from git.
maps="$out/path_map.txt"
others="$out/non_move_changes.txt"
: > "$maps"
: > "$others"
while IFS=$'\t' read -r status old new; do
  case "$status" in
    R100) echo "$old=$new" >> "$maps" ;;
    "") ;;
    *) printf '%s\t%s\t%s\n' "$status" "$old" "$new" >> "$others" ;;
  esac
done < <(git diff --name-status -M100% "$before" "$after")
echo "move_equiv: $(wc -l < "$maps") moved file(s) in the map ($maps)"
if [ -s "$others" ]; then
  echo "move_equiv: other changed files between $before_rev and $after_rev (expected: deepquarry.dme, tools/ci/lint_scopes.toml):"
  sed 's/^/  /' "$others"
fi
if [ ! -s "$maps" ] && [ "${DQ_MOVE_EQUIV_PLAIN:-}" != "1" ]; then
  echo "move_equiv: no pure renames between the two revisions" >&2
  exit 2
fi

defines_of() {
  case "$1" in
    production) echo "" ;;
    test) echo "-DCIBUILDING -DCITESTING" ;;
    *) echo "move_equiv: unknown flavor $1" >&2; exit 2 ;;
  esac
}

# 3. One extract per revision; the worktree is never touched.
extract() { # side rev
  local side=$1 rev=$2 dir="$out/src/$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  git archive "$rev" | tar -x -C "$dir" || return 1
  if [ -n "$overlay" ]; then
    # shellcheck disable=SC2086
    git archive HEAD $overlay | tar -x -C "$dir" || return 1
  fi
  ( cd "$dir" && git init -q . ) || return 1
}

compile() { # flavor side
  local flavor=$1 side=$2 dir="$out/src/$2" dest="$out/$1/$2"
  mkdir -p "$dest"
  # shellcheck disable=SC2046
  ( cd "$dir" && rm -f deepquarry.dmb deepquarry.rsc deepquarry.dmb.compiler \
      && DQ_ICON_SEED="$root/icons/gen" DQ_COMPILER=dreammaker DQ_COMPILER_STRICT=1 \
         tools/build/build.sh dm $(defines_of "$flavor") ) > "$dest/compile.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "move_equiv: the $side compile of the $flavor world failed (log: $dest/compile.log)" >&2
    return 1
  fi
  cp "$dir/deepquarry.dmb" "$dir/deepquarry.rsc" "$dest/"
}

count_of() { # log pattern
  grep -c -E "$2" "$1" || true
}

extract before "$before" || exit 2
extract after "$after" || exit 2
for flavor in $flavors; do
  compile "$flavor" before || exit 2
  compile "$flavor" after || exit 2
done
if [ "${DQ_MOVE_EQUIV_KEEP:-}" != "1" ]; then rm -rf "$out/src"; fi

# 4. Compare.
mapargs=(--path-map-file "$maps")
if [ "${DQ_MOVE_EQUIV_PLAIN:-}" = "1" ]; then mapargs=(); fi
status=0
for flavor in $flavors; do
  b="$out/$flavor/before"
  a="$out/$flavor/after"
  echo "== $flavor world: before ($before_rev) against after ($after_rev)"
  "$equiv" "$b/deepquarry.dmb" "$a/deepquarry.dmb" --rsc "$b/deepquarry.rsc" "$a/deepquarry.rsc" \
    "${mapargs[@]}" --all --context 4 --json "$out/$flavor.report.json" "${extra[@]}" | tee "$out/$flavor.report.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
  bw=$(count_of "$b/compile.log" 'warning:')
  aw=$(count_of "$a/compile.log" 'warning:')
  be=$(count_of "$b/compile.log" 'error:')
  ae=$(count_of "$a/compile.log" 'error:')
  echo "compiler warnings before/after: $bw/$aw, errors before/after: $be/$ae"
  if [ "$bw" != "$aw" ] || [ "$be" != "$ae" ]; then
    echo "move_equiv: $flavor compile warning or error counts differ" >&2
    status=1
  fi
done
if [ $status -eq 0 ]; then echo "move_equiv: EQUIVALENT (production and test worlds, same warning counts)"; fi
exit $status
