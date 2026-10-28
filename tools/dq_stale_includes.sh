#!/usr/bin/env bash
# Sourced by tools/dq_merge_batch.sh and tools/dq_merge_master.sh.
# dq_drop_stale_includes <file> <dir the includes are relative to> <label>: a union-merged include list can bring back an include of a
# file one side deleted (28 October: _unit_tests.dm kept dq_reagents_start_snapshot.dm after tests/cut-pins removed it; gr/bumped-notices,
# merged by hand, kept code/modules/unit_tests/... includes after the tests-wave1 move, and DreamChecker failed on them). Every
# `#include "x"` whose file does not exist is dropped and REPORTED on stderr (never silently), and the file is staged.
# Sets DQ_STALE_DROPPED to the number dropped. Returns 1 only when the file could not be rewritten.
dq_drop_stale_includes() {
	local f="$1" dir="$2" label="$3" inc stale tmp
	DQ_STALE_DROPPED=0
	[ -f "$f" ] || return 0
	stale="$(sed -n 's/^#include "\([^"]*\)".*/\1/p' "$f" | tr -d '\r' | while IFS= read -r inc; do
		case "$inc" in *.dmm|*.dmf|*.dms) continue ;; esac   # maps and skins are resolved elsewhere (FILE_DIR); only code includes
		[ -f "$dir/${inc//\\//}" ] || echo "$inc"
	done)"
	[ -n "$stale" ] || return 0
	tmp="$f.stale.$$"
	cp "$f" "$tmp" || return 1
	while IFS= read -r inc; do
		grep -vF "#include \"$inc\"" "$tmp" >"$tmp.n" && mv -f "$tmp.n" "$tmp"
		DQ_STALE_DROPPED=$((DQ_STALE_DROPPED + 1))
		echo "   STALE INCLUDE dropped from $f: \"$inc\" (the file no longer exists after the merge) [$label]" >&2
	done <<<"$stale"
	mv -f "$tmp" "$f" && git add -- "$f"
}
