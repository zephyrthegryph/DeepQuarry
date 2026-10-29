#!/usr/bin/env bash
# Records window-data pins (dq_ui_pins.dm): what a window host shows after scripted state changes.
# Guide: doc/rewrite/snapshot_pins.md.
#
#   bash tools/dq_pin.sh --ui /datum/foo_panel [...]   # make the empty pin file (snapshots/ui_pins/, test dq_ui_data_pin, a /datum/ui_pin driver)
#   bash tools/dq_pin.sh --rm --ui /datum/foo_panel    # drop one
#
# A pin is one file, code/modules/unit_tests/snapshots/ui_pins/<type with / as .>.txt; an empty file is recorded on
# the next run of dq_ui_data_pin instead of failing it.
set -euo pipefail
cd "$(dirname "$0")/.."

dir="code/modules/unit_tests/snapshots/ui_pins"
test="dq_ui_data_pin"
remove=0
types=()
for arg in "$@"; do
	case "$arg" in
		--rm) remove=1 ;;
		--ui) dir="code/modules/unit_tests/snapshots/ui_pins"; test="dq_ui_data_pin" ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
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
