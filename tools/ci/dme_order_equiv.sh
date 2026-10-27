#!/bin/bash
# Is the generated include order of deepquarry.dme the same world as another order? Compiles both manifests (the production world and
# the unit-test world, native compiler) and compares each pair with dmb-equiv. Every difference it reports is an order dependence that
# needs an explicit rule in tools/build/dme_spec.txt (tools/build/gen_dme.py).
#
#   bash tools/ci/dme_order_equiv.sh [REFERENCE] [-- extra dmb-equiv flags]
#
# REFERENCE is the other manifest: a file path, or `REV:deepquarry.dme` for a revision's (default `HEAD:deepquarry.dme`; the hand-kept
# order was origin/master 54914eb899's). The generated one is `python3 tools/build/gen_dme.py --out ...` over this worktree's files, so
# the two must name the same files (the script stops when they do not: that is a missing or extra file, not an order question).
#
# Table orders are not compared (`--ignore-order`: type, proc and variable numbering follows the include order by construction and is
# not behaviour, the user ruling of 2026-10-21 that tools/ci/dm_equiv.sh applies too). What order can change and dmb-equiv does
# compare: which of two definitions of the same proc on the same type wins (`#rank`, definition precedence), a var default set twice,
# the order the global initializers run in (`proc.global_init_order`), and anything the preprocessor decides (a macro used before its
# #define or after its #undef changes code or fails the compile). The global initializers always move with the include order; when
# that is the only difference, tools/ci/global_init_order.py checks that every moved pair commutes (no initializer reads another's
# global after the move, and no two with effects another could see swap). Debug lines are compared too (`--ignore-debug` is not passed) unless
# you add it after `--`: a moved file keeps its own lines, so a debug difference is a real one.
#
#   DQ_DME_EQUIV_DIR      where the worlds and reports go (default data/dme_order_equiv)
#   DQ_DME_EQUIV_FLAVORS  subset of "production test" (default both)
#
# The worktree's deepquarry.dme is swapped for each compile and regenerated at the end (DQ_DME_GEN=0 keeps the build from
# regenerating it in between). Heavy: four native compiles; run it when an ordering rule changes, not per lane.
set -u
cd "$(dirname "$0")/../.." || exit 2
out="${DQ_DME_EQUIV_DIR:-data/dme_order_equiv}"
flavors="${DQ_DME_EQUIV_FLAVORS:-production test}"
reference="HEAD:deepquarry.dme"
if [ $# -gt 0 ] && [ "$1" != "--" ]; then reference=$1; shift; fi
extra=()
if [ "${1:-}" = "--" ]; then shift; extra=("$@"); fi

mkdir -p "$out"
ref_dme="$out/reference.dme"
gen_dme="$out/generated.dme"
if [ -f "$reference" ]; then
	cp "$reference" "$ref_dme"
else
	git show "$reference" > "$ref_dme" || { echo "dme_order_equiv: cannot read $reference" >&2; exit 2; }
fi
python3 tools/build/gen_dme.py --out "$gen_dme" >/dev/null || exit 2

# The compiled include set: lines inside #ifdef blocks (DOC_SNIPPETS) are not compiled by either build.
includes() { awk '/^#ifdef/{skip=1} /^#endif/{skip=0} !skip && /^#include "/' "$1" | sort; }
if ! diff <(includes "$ref_dme") <(includes "$gen_dme") > "$out/include_set.diff"; then
	echo "dme_order_equiv: the two manifests name different files ($out/include_set.diff):" >&2
	head -20 "$out/include_set.diff" >&2
	exit 2
fi
moved=$(diff <(grep -E '^#include "' "$ref_dme") <(grep -E '^#include "' "$gen_dme") | grep -c '^>' || true)
echo "dme_order_equiv: $(grep -c '^#include "' "$gen_dme") includes, $moved lines out of the reference's order"

equiv_target="$(bash tools/dq_cargo_target.sh dmb-equiv)"
if [ ! -x "$equiv_target/release/dmb-equiv" ] && [ ! -x "$equiv_target/release/dmb-equiv.exe" ]; then
	CARGO_INCREMENTAL=0 CARGO_TARGET_DIR="$equiv_target" bash tools/dq_machine_slots.sh run cargo -- \
		cargo build --release --manifest-path tools/dmb/Cargo.toml -p dmb-equiv || exit 2
fi
equiv="$equiv_target/release/dmb-equiv"
[ -x "$equiv" ] || equiv="$equiv_target/release/dmb-equiv.exe"

defines_of() {
	case "$1" in
		production) echo "" ;;
		test) echo "-DCIBUILDING -DCITESTING" ;;
		*) echo "dme_order_equiv: unknown flavor $1" >&2; exit 2 ;;
	esac
}

restore() { python3 tools/build/gen_dme.py >/dev/null; }
trap restore EXIT

compile() { # flavor side manifest
	local flavor=$1 side=$2 dme=$3 dest="$out/$1/$2"
	mkdir -p "$dest"
	cp "$dme" deepquarry.dme
	rm -f deepquarry.dmb deepquarry.rsc deepquarry.dmb.compiler
	# shellcheck disable=SC2046
	if ! DQ_DME_GEN=0 DQ_COMPILER=native tools/build/build.sh dm $(defines_of "$flavor") > "$dest/compile.log" 2>&1; then
		echo "dme_order_equiv: the $side compile of the $flavor world failed ($dest/compile.log):" >&2
		grep -iE 'error|warning' "$dest/compile.log" | head -20 >&2
		return 1
	fi
	cp deepquarry.dmb deepquarry.rsc "$dest/"
}

status=0
for flavor in $flavors; do
	compile "$flavor" reference "$ref_dme" || { status=1; continue; }
	compile "$flavor" generated "$gen_dme" || { status=1; continue; }
	echo "== $flavor world: reference order against generated order"
	"$equiv" "$out/$flavor/reference/deepquarry.dmb" "$out/$flavor/generated/deepquarry.dmb" \
		--rsc "$out/$flavor/reference/deepquarry.rsc" "$out/$flavor/generated/deepquarry.rsc" \
		--ignore-order --all --context 4 --json "$out/$flavor.report.json" "${extra[@]}" | tee "$out/$flavor.report.txt"
	[ "${PIPESTATUS[0]}" -eq 0 ] && continue
	# The one difference no `before` rule can remove without keeping the whole old order: the global initializers run in include
	# order. When it is the only one left, tools/ci/global_init_order.py decides whether any moved pair can be told apart.
	only_init=$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["categories"]; print(int(set(c) == {"proc.global_init_order"}))' "$out/$flavor.report.json")
	if [ "$only_init" = "1" ] && python3 tools/ci/global_init_order.py "$equiv" "$out/$flavor/reference/deepquarry.dmb" "$out/$flavor/generated/deepquarry.dmb"; then
		echo "== $flavor world: EQUIVALENT (the global initializers that moved commute)"
		continue
	fi
	status=1
done
exit $status
