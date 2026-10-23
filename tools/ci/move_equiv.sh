#!/bin/bash
# Before/after equivalence for file moves: compile the world before and after a move with DreamMaker and compare the two with
# dmb-equiv, mapping every moved file's old source path to its new one.
#
#   bash tools/ci/move_equiv.sh BEFORE AFTER [-- extra dmb-equiv flags]
#
# BEFORE and AFTER are git revisions (commit, tag, HEAD~3, ...): the parent of the first move commit and the last commit of the
# move series (the pure `git mv` commit, the .dme path commit and the lint_scopes path commit). The script
#   1. builds dmb-equiv from the checked-out tree (older trees may not have `--path-map`),
#   2. lists the move with `git diff --name-status -M100% BEFORE AFTER` and turns every pure rename (R100) into an `OLD=NEW` map line,
#      and prints every other changed file so a change that is not a move is visible (the .dme and tools/ci/lint_scopes.toml are
#      expected to change),
#   3. `git switch --detach`es to BEFORE and to AFTER in turn and compiles the production world and the unit-test world
#      (-DCIBUILDING -DCITESTING) with DreamMaker (DQ_COMPILER=dreammaker, strict), keeping the compile logs,
#   4. restores the starting branch (or detached commit),
#   5. compares each flavour's before/after worlds (dmb-equiv --all, default order policy, debug streams included) with the map
#      and compares the number of compiler warnings and errors of the two compiles.
#
# Exit 0 only when both worlds are EQUIVALENT and the warning counts match. The map rewrites only string constants equal to or
# prefixed by a moved file's old path, in the BEFORE world only (tools/dmb/crates/dmb-equiv/EQUIVALENCE.md "Path map"), so any
# other difference is still reported. The working tree must be clean (it is switched between the two revisions); run it in a lane
# worktree, never in the main checkout.
#
#   DQ_MOVE_EQUIV_DIR      where worlds, logs and reports go (default data/move_equiv, gitignored)
#   DQ_MOVE_EQUIV_FLAVORS  subset of "production test" (default both)
set -u
# The script runs from a copy outside the tree: bash reads a script as it goes, and the tree is switched between revisions where
# this file may differ or not exist.
if [ -z "${DQ_MOVE_EQUIV_ROOT:-}" ]; then
  root=$(cd "$(dirname "$0")/../.." && pwd) || exit 2
  copy="$root/data/move_equiv.run.sh"
  mkdir -p "$root/data" && cp "$0" "$copy" || exit 2
  DQ_MOVE_EQUIV_ROOT=$root exec bash "$copy" "$@"
fi
cd "$DQ_MOVE_EQUIV_ROOT" || exit 2

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

before=$(git rev-parse --verify "$before_rev^{commit}") || exit 2
after=$(git rev-parse --verify "$after_rev^{commit}") || exit 2
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "move_equiv: the working tree has tracked changes; commit them first (the script switches revisions)" >&2
  exit 2
fi
start_branch=$(git symbolic-ref --short -q HEAD || true)
start_commit=$(git rev-parse HEAD)

mkdir -p "$out"
out=$(cd "$out" && pwd)

# 1. dmb-equiv from the starting tree.
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
if [ ! -s "$maps" ]; then
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

restore() {
  if [ -n "$start_branch" ]; then git switch -q "$start_branch"; else git switch -q --detach "$start_commit"; fi
}
trap restore EXIT

compile() { # flavor side rev
  local flavor=$1 side=$2 rev=$3 dest="$out/$1/$2"
  mkdir -p "$dest"
  git switch -q --detach "$rev" || return 1
  rm -f deepquarry.dmb deepquarry.rsc deepquarry.dmb.compiler
  # shellcheck disable=SC2046
  DQ_COMPILER=dreammaker DQ_COMPILER_STRICT=1 tools/build/build.sh dm $(defines_of "$flavor") > "$dest/compile.log" 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "move_equiv: the $side compile of the $flavor world failed (log: $dest/compile.log)" >&2
    return 1
  fi
  cp deepquarry.dmb deepquarry.rsc "$dest/"
}

count_of() { # log pattern
  grep -c -E "$2" "$1" || true
}

for flavor in $flavors; do
  compile "$flavor" before "$before" || exit 2
  compile "$flavor" after "$after" || exit 2
done
restore
trap - EXIT

# 5. Compare.
status=0
for flavor in $flavors; do
  b="$out/$flavor/before"
  a="$out/$flavor/after"
  echo "== $flavor world: before ($before_rev) against after ($after_rev)"
  "$equiv" "$b/deepquarry.dmb" "$a/deepquarry.dmb" --rsc "$b/deepquarry.rsc" "$a/deepquarry.rsc" \
    --path-map-file "$maps" --all --context 4 --json "$out/$flavor.report.json" "${extra[@]}" | tee "$out/$flavor.report.txt"
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
