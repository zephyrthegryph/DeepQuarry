#!/usr/bin/env bash
# Git merge driver for tools/ci/lint_scopes.toml (.gitattributes: merge=dq-lint-scopes).
#
#   lint_scopes_merge_driver.sh BASE OURS THEIRS [PATH]     # git passes %O %A %B %P; the result is written over OURS
#
# Ceilings ("key = N") only go down, and lanes lower ADJACENT ceiling lines all the time; a text merge then conflicts on lines
# that never really disagree (28 October: gr/base-vars-b bounced 3 times on ceilings chem landings lowered next to its own).
# First a normal text merge. If it conflicts, and the three versions have the same lines in the same places, each line is
# merged on its own: one side's change wins when the other kept the base, and when both changed a line that is the same
# "key = N" ceiling on both sides the LOWER value wins. Any other disagreement (a different key, text, a line added or removed)
# is a normal conflict, as before: the driver never guesses.
set -u
O="$1"; A="$2"; B="$3"
tmp="$(mktemp)"
cp "$A" "$tmp"
if git merge-file -q -L ours -L base -L theirs "$tmp" "$O" "$B"; then mv -f "$tmp" "$A"; exit 0; fi
rm -f "$tmp"
fallback() { exec git merge-file -L ours -L base -L theirs "$A" "$O" "$B"; }
n="$(wc -l <"$O")"
[ "$(wc -l <"$A")" = "$n" ] && [ "$(wc -l <"$B")" = "$n" ] || fallback
out="$(mktemp)"
if LC_ALL=C awk -v A="$A" -v B="$B" '
	function ceil(l, parts) { return match(l, /^[ \t]*[A-Za-z0-9_.-]+[ \t]*=[ \t]*[0-9]+[ \t]*\r?$/) }
	function key(l) { sub(/[ \t]*=.*/, "", l); gsub(/[ \t]/, "", l); return l }
	function num(l) { sub(/^[^=]*=[ \t]*/, "", l); return l + 0 }
	{ o = $0; getline a < A; getline b < B
	  if (a == b || a == o) { print b; next }
	  if (b == o) { print a; next }
	  if (ceil(a) && ceil(b) && ceil(o) && key(a) == key(b) && key(a) == key(o)) {
		if (num(a) <= num(b)) print a; else print b
		printf("lint_scopes merge: %s: both sides lowered it; kept the lower (%d vs %d)\n", key(a), num(a), num(b)) > "/dev/stderr"
		next }
	  exit 1 }' "$O" >"$out"; then
	mv -f "$out" "$A"; exit 0
fi
rm -f "$out"
fallback
