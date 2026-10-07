#!/usr/bin/env bash
# Records conversion pins: a generated snapshot of what a person can do with each named type (its interaction
# menu per actor and held tool, the refusals, what a click does, its wires, its op keys). Run it BEFORE converting
# a type; after the conversion, `bash tools/dq_focused_test.sh dq_conversion_pin` shows every row that changed.
# Guide: doc/rewrite/snapshot_pins.md. Test: code/modules/unit_tests/dq_conversion_pins.dm.
#
#   bash tools/dq_pin.sh /obj/machinery/foo [/obj/machinery/bar ...]   # make the empty pin files and record them
#   bash tools/dq_pin.sh --rm /obj/machinery/foo                       # drop a pin (the type is gone or hand-pinned)
#   bash tools/dq_pin.sh --look /obj/machinery/foo [...]                # a look pin instead: icon, icon_state, overlays
#                                                                       # (snapshots/looks/, test dq_look_pin)
#   bash tools/dq_pin.sh --hit /obj/item/foo [...]                     # a hit pin: what an EMP, a blast, a shot, a blob, a throw and an
#                                                                       # emag change on a fresh one (snapshots/hit_pins/, test dq_hit_pin)
#   bash tools/dq_pin.sh --look-tree /obj/item/gun [...]                # the look pin of every subtype, one file per root
#                                                                       # (snapshots/look_trees/, test dq_look_tree_pin)
#
# A pin is one file, code/modules/unit_tests/snapshots/pins/<type with / as .>.txt; an empty file is recorded on
# the next run of dq_conversion_pin instead of failing it. Commit the recorded files with the conversion.
set -euo pipefail
cd "$(dirname "$0")/.."

dir="code/modules/unit_tests/snapshots/pins"
test="dq_conversion_pin"
remove=0
types=()
for arg in "$@"; do
	case "$arg" in
		--rm) remove=1 ;;
		--look) dir="code/modules/unit_tests/snapshots/looks"; test="dq_look_pin" ;;
		--hit) dir="code/modules/unit_tests/snapshots/hit_pins"; test="dq_hit_pin" ;;
		--look-tree) dir="code/modules/unit_tests/snapshots/look_trees"; test="dq_look_tree_pin" ;;
		-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
		/*) types+=("$arg") ;;
		*) echo "not a type path (it starts with /): $arg" >&2; exit 2 ;;
	esac
done
[ ${#types[@]} -gt 0 ] || { echo "usage: $0 [--rm] /type/path [...]" >&2; exit 2; }

mkdir -p "$dir"
for type in "${types[@]}"; do
	file="$dir/$(echo "${type#/}" | tr '/' '.').txt"
	if [ "$remove" -eq 1 ]; then
		rm -f "$file"
		echo "removed $file"
		continue
	fi
	if [ -s "$file" ]; then
		echo "already pinned: $file (delete it, or run with --bless to re-record every pin)"
		continue
	fi
	: >"$file"
	echo "pinning $type -> $file"
done
[ "$remove" -eq 1 ] && exit 0
exec bash tools/dq_focused_test.sh "$test"
