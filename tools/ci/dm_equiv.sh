#!/bin/bash
# Compile the production dme and the unit-test dme with DreamMaker and with the native compiler and compare the two worlds of each
# with dmb-equiv.
#
#   bash tools/ci/dm_equiv.sh [-- extra dmb-equiv flags]
#
# Exit 0 only when both pairs are equivalent (no unexplained difference). The reports list every difference (`--all`); table orders
# are not counted (`--ignore-order`: the user ruled on 2026-10-21 that proc, type and variable table numbering is not behaviour, and
# the runtime dumps of typesof/vars/proc lists were byte-identical; the order the global initializers run in IS compared, as
# `proc.global_init_order`). Debug lines are not compared (`--ignore-debug`): neither production build carries any. See
# tools/dmb/crates/dmb-equiv/EQUIVALENCE.md.
#
#   DQ_EQUIV_DIR    where the worlds and reports go (default data/dm_equiv: <flavor>/{dm,native} and <flavor>.report.txt)
#   DQ_EQUIV_FLAVORS  space-separated subset of "production test" (default both); `production` compiles the shipping world
#                   (what `build.sh dm` ships: no CIBUILDING), `test` the unit-test world (-DCIBUILDING -DCITESTING).
set -u
cd "$(dirname "$0")/../.."
out="${DQ_EQUIV_DIR:-data/dm_equiv}"
flavors="${DQ_EQUIV_FLAVORS:-production test}"
extra=()
if [ "${1:-}" = "--" ]; then shift; extra=("$@"); fi

defines_of() {
  case "$1" in
    production) echo "" ;;
    test) echo "-DCIBUILDING -DCITESTING" ;;
    *) echo "dm_equiv: unknown flavor $1" >&2; exit 2 ;;
  esac
}

compile() { # flavor compiler destination
  local flavor=$1 compiler=$2 dest=$3
  rm -f deepquarry.dmb deepquarry.rsc deepquarry.dmb.compiler
  # shellcheck disable=SC2046
  if ! DQ_COMPILER=$compiler DQ_COMPILER_STRICT=1 tools/build/build.sh dm $(defines_of "$flavor"); then
    echo "dm_equiv: the $compiler compile of the $flavor world failed" >&2
    return 1
  fi
  mkdir -p "$dest"
  cp deepquarry.dmb deepquarry.rsc "$dest/"
}

equiv_target="$(bash tools/dq_cargo_target.sh dmb-equiv)"
if [ ! -x "$equiv_target/release/dmb-equiv" ] && [ ! -x "$equiv_target/release/dmb-equiv.exe" ]; then
  (cd tools/dmb && CARGO_INCREMENTAL=0 CARGO_TARGET_DIR="$equiv_target" cargo build --release -p dmb-equiv) || exit 1
fi
equiv="$equiv_target/release/dmb-equiv"
[ -x "$equiv" ] || equiv="$equiv_target/release/dmb-equiv.exe"

status=0
for flavor in $flavors; do
  compile "$flavor" dreammaker "$out/$flavor/dm" || exit 1
  compile "$flavor" native "$out/$flavor/native" || exit 1
  echo "== $flavor world: DreamMaker against native"
  "$equiv" "$out/$flavor/dm/deepquarry.dmb" "$out/$flavor/native/deepquarry.dmb" \
    --rsc "$out/$flavor/dm/deepquarry.rsc" "$out/$flavor/native/deepquarry.rsc" \
    --ignore-debug --ignore-order --all --context 4 --json "$out/$flavor.report.json" "${extra[@]}" | tee "$out/$flavor.report.txt"
  [ "${PIPESTATUS[0]}" -eq 0 ] || status=1
done
exit $status
