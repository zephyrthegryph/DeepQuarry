#!/bin/bash
# Compile the production dme with DreamMaker and with the native compiler and compare the two worlds with dmb-equiv.
#
#   bash tools/ci/dm_equiv.sh [-- extra dmb-equiv flags]
#
# Exit 0 only when the worlds are equivalent (no unexplained difference). The report lists every difference
# (`--all`); table orders are not counted (`--ignore-order`: the user ruled on 2026-10-21 that proc, type and variable
# table numbering is not behaviour, and the runtime dumps of typesof/vars/proc lists were byte-identical). Debug lines are
# not compared (`--ignore-debug`): neither production build carries any. See tools/dmb/crates/dmb-equiv/EQUIVALENCE.md.
set -u
cd "$(dirname "$0")/../.."
out="${DQ_EQUIV_DIR:-data/dm_equiv}"
mkdir -p "$out/dm" "$out/native"
extra=()
if [ "${1:-}" = "--" ]; then shift; extra=("$@"); fi

# `build.sh dm` compiles the production world (no CIBUILDING), which is what ships.
for compiler in dreammaker native; do
  dest=$out/$([ "$compiler" = native ] && echo native || echo dm)
  rm -f deepquarry.dmb deepquarry.rsc deepquarry.dmb.compiler
  if ! DQ_COMPILER=$compiler DQ_COMPILER_STRICT=1 tools/build/build.sh dm; then
    echo "dm_equiv: the $compiler compile failed" >&2
    exit 1
  fi
  cp deepquarry.dmb deepquarry.rsc "$dest/"
done

if [ ! -x tools/dmb/target/release/dmb-equiv ] && [ ! -x tools/dmb/target/release/dmb-equiv.exe ]; then
  (cd tools/dmb && cargo build --release -p dmb-equiv) || exit 1
fi
equiv=tools/dmb/target/release/dmb-equiv
[ -x "$equiv" ] || equiv=tools/dmb/target/release/dmb-equiv.exe
"$equiv" "$out/dm/deepquarry.dmb" "$out/native/deepquarry.dmb" \
  --rsc "$out/dm/deepquarry.rsc" "$out/native/deepquarry.rsc" \
  --ignore-debug --ignore-order --all --context 4 --json "$out/report.json" "${extra[@]}" | tee "$out/report.txt"
exit "${PIPESTATUS[0]}"
