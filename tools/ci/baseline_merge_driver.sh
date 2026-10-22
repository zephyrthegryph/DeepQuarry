#!/usr/bin/env bash
# Git merge driver for tools/ci/*_baseline.txt (.gitattributes: merge=dq-baseline).
#
#   baseline_merge_driver.sh BASE OURS THEIRS [PATH]     # git passes %O %A %B %P; the result is written over OURS
#
# A baseline only ever shrinks: a lane drops the rows it fixed and lowers the ceilings it improved. So the right merge of two sides
# is the intersection of their rows, and for a ceiling line ("key N") the smaller N (a key one side removed, because it reached 0,
# is removed). Supported format: '#' comment lines, blank lines, tab-separated rows, and ceiling lines "word number".
# Anything else falls back to a normal text merge (git merge-file), which conflicts as before, as does a side that ADDED a row or
# ceiling key (not in the base) or that changed the comment lines differently: the driver never guesses.
#
# Installed per command, not per clone, by tools/dq_git_safe.sh (sourced by every merge tool), so a fresh worktree needs no setup.
set -u
O="$1"; A="$2"; B="$3"

fallback() { exec git merge-file -L ours -L base -L theirs "$A" "$O" "$B"; }

supported() { # every line of every file is a comment, blank, ceiling or tab row
	! LC_ALL=C grep -vE '^(#.*|[[:space:]]*|[A-Za-z0-9_.-]+ [0-9]+|[^	]*	.*)$' "$O" "$A" "$B" >/dev/null 2>&1
}
supported || fallback

cmp -s <(grep -E '^#' "$A") <(grep -E '^#' "$B") || fallback

# Any content line (not comment/blank) of $1 absent from base file $O means that side added something: fallback.
for f in "$A" "$B"; do
	grep -vE '^(#|[[:space:]]*$)' "$f" | LC_ALL=C awk -v base="$O" '
		BEGIN { while ((getline l < base) > 0) { if (l ~ /^#/ || l ~ /^[ \t]*$/) continue; if (l ~ /^[A-Za-z0-9_.-]+ [0-9]+$/) { split(l, p, " "); k["C " p[1]] = 1 } else k["R " l] = 1 } }
		{ if ($0 ~ /^[A-Za-z0-9_.-]+ [0-9]+$/) { split($0, p, " "); if (!(("C " p[1]) in k)) bad = 1 } else if (!(("R " $0) in k)) bad = 1 }
		END { exit bad ? 1 : 0 }' || fallback
done

tmp="$(mktemp)"
LC_ALL=C awk -v theirs="$B" '
	BEGIN { while ((getline l < theirs) > 0) { if (l ~ /^#/ || l ~ /^[ \t]*$/) continue; if (l ~ /^[A-Za-z0-9_.-]+ [0-9]+$/) { split(l, p, " "); c[p[1]] = p[2] + 0 } else r[l] = 1 } }
	/^#/ || /^[ \t]*$/ { print; next }
	/^[A-Za-z0-9_.-]+ [0-9]+$/ { split($0, p, " "); if (p[1] in c) print p[1], (c[p[1]] < p[2] + 0 ? c[p[1]] : p[2]); next }
	($0 in r) { print }
' "$A" >"$tmp" || { rm -f "$tmp"; fallback; }
cat "$tmp" >"$A"; rm -f "$tmp"
exit 0
