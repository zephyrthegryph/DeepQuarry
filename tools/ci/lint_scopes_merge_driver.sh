#!/usr/bin/env bash
# Git merge driver for tools/ci/lint_scopes.toml (.gitattributes: merge=dq-lint-scopes).
#
#   lint_scopes_merge_driver.sh BASE OURS THEIRS [PATH]     # git passes %O %A %B %P; the result is written over OURS
#
# Ceilings ("key = N") only go down, and lanes lower ADJACENT ceiling lines all the time; a text merge then conflicts on lines
# that never really disagree (28 October: gr/base-vars-b bounced 3 times, gr/bumped-notices once, on ceilings master lowered next
# to its own). A normal text merge runs first (git merge-file, diff3 style). Each CONFLICT block it leaves is resolved on its own when
# its three sides have the same number of lines: per line, one side's change wins when the other kept the base, and when both changed
# a line that is the same "key = N" ceiling the LOWER value wins. Any other block (text, a different key, a line added or removed on
# one side only inside the block) stays a normal conflict: the driver never guesses. Changes outside conflict blocks merge as git merges them.
set -u
O="$1"; A="$2"; B="$3"
out="$(mktemp)"
git merge-file -p --diff3 -L ours -L base -L theirs "$A" "$O" "$B" >"$out"
rc=$?
if [ "$rc" -eq 0 ]; then mv -f "$out" "$A"; exit 0; fi
[ "$rc" -gt 0 ] || { rm -f "$out"; exec git merge-file -L ours -L base -L theirs "$A" "$O" "$B"; }
res="$(mktemp)"
LC_ALL=C awk '
	function isceil(l) { return l ~ /^[ \t]*[A-Za-z0-9_.-]+[ \t]*=[ \t]*[0-9]+[ \t]*\r?$/ }
	function key(l) { sub(/[ \t]*=.*/, "", l); gsub(/[ \t]/, "", l); return l }
	function num(l) { sub(/^[^=]*=[ \t]*/, "", l); return l + 0 }
	function flush(   i, a, b, o) {
		if (na != nb || na != no) { bad = 1; dump(); return }
		for (i = 1; i <= na; i++) {
			a = A[i]; b = B[i]; o = O[i]
			if (a == b || a == o) { R[i] = b; continue }
			if (b == o) { R[i] = a; continue }
			if (isceil(a) && isceil(b) && isceil(o) && key(a) == key(b) && key(a) == key(o)) {
				R[i] = (num(a) <= num(b)) ? a : b
				printf("lint_scopes merge: %s: both sides changed it; kept the lower (%d vs %d)\n", key(a), num(a), num(b)) > "/dev/stderr"
				continue
			}
			bad = 1; dump(); return
		}
		for (i = 1; i <= na; i++) print R[i]
	}
	function dump(   i) { print "<<<<<<< ours"; for (i = 1; i <= na; i++) print A[i]; print "||||||| base"; for (i = 1; i <= no; i++) print O[i]; print "======="; for (i = 1; i <= nb; i++) print B[i]; print ">>>>>>> theirs" }
	/^<<<<<<< / { st = 1; na = no = nb = 0; next }
	/^\|\|\|\|\|\|\| / && st == 1 { st = 2; next }
	/^=======$/ && st == 2 { st = 3; next }
	/^>>>>>>> / && st == 3 { st = 0; flush(); next }
	st == 1 { A[++na] = $0; next }
	st == 2 { O[++no] = $0; next }
	st == 3 { B[++nb] = $0; next }
	{ print }
	END { exit bad ? 1 : 0 }' "$out" >"$res"
arc=$?
rm -f "$out"
if [ "$arc" -eq 0 ]; then mv -f "$res" "$A"; exit 0; fi
rm -f "$res"
exec git merge-file -L ours -L base -L theirs "$A" "$O" "$B"
