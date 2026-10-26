#!/usr/bin/env bash
# Git merge driver for tools/ci/*_baseline.txt (.gitattributes: merge=dq-baseline).
#
#   baseline_merge_driver.sh BASE OURS THEIRS [PATH]     # git passes %O %A %B %P; the result is written over OURS
#
# A baseline only ever shrinks: a lane drops the rows it fixed and lowers the ceilings it improved. So the right merge of two sides
# is the intersection of their rows, and for a ceiling line ("key N") the smaller N (a key one side removed, because it reached 0,
# is removed). Supported format: '#' comment lines, blank lines, tab-separated rows, and ceiling lines "word number".
# Anything else falls back to a normal text merge (git merge-file), which conflicts as before, as does a side that changed the comment lines differently: the driver never guesses.
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

# The merge: the rows both sides kept, plus rows either side ADDED (not in the base: a new lint, or a lane that records a new site),
# in ours' order, an added row of theirs placed after the nearest row before it that survives. A row one side dropped stays dropped.
# A ceiling key: the smaller value; a key one side dropped (reached 0) stays dropped; a key only one side has and the base lacks is kept.
tmp="$(mktemp)"
LC_ALL=C awk -v base="$O" -v theirs="$B" '
	function iscomment(l) { return (l ~ /^#/ || l ~ /^[ \t]*$/) }
	function isceil(l) { return (l ~ /^[A-Za-z0-9_.-]+ [0-9]+$/) }
	BEGIN {
		while ((getline l < base) > 0) { if (iscomment(l)) continue; if (isceil(l)) { split(l, p, " "); bc[p[1]] = 1 } else br[l] = 1 }
		while ((getline l < theirs) > 0) {
			if (iscomment(l)) continue
			if (isceil(l)) { split(l, p, " "); tc[p[1]] = p[2] + 0; continue }
			tn++; tl[tn] = l; tr[l] = 1
		}
	}
	{ al[NR] = $0; if (!iscomment($0) && !isceil($0)) ar[$0] = 1 }
	END {
		for (i = 1; i <= NR; i++) { l = al[i]; if (!iscomment(l) && !isceil(l) && ((l in tr) || !(l in br))) keep[l] = 1 }
		for (j = 1; j <= tn; j++) {
			l = tl[j]
			if ((l in br) || (l in ar)) continue
			anchor = ""
			for (k = j - 1; k >= 1; k--) if (tl[k] in keep) { anchor = tl[k]; break }
			if (anchor == "") head[++nh] = l; else { aft[anchor, ++na[anchor]] = l }
			keep[l] = 1
		}
		started = 0
		for (i = 1; i <= NR; i++) {
			l = al[i]
			if (iscomment(l)) { print l; continue }
			if (!started) { started = 1; for (h = 1; h <= nh; h++) print head[h] }
			if (isceil(l)) {
				split(l, p, " ")
				if (p[1] in tc) print p[1], (tc[p[1]] < p[2] + 0 ? tc[p[1]] : p[2])
				else if (!(p[1] in bc)) print l
				seen[p[1]] = 1
				continue
			}
			if (l in keep) { print l; for (m = 1; m <= na[l]; m++) print aft[l, m] }
		}
		if (!started) for (h = 1; h <= nh; h++) print head[h]
		for (key in tc) if (!(key in seen) && !(key in bc)) print key, tc[key]
	}
' "$A" >"$tmp" || { rm -f "$tmp"; fallback; }
cat "$tmp" >"$A"; rm -f "$tmp"
exit 0
