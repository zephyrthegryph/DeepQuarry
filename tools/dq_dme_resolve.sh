#!/usr/bin/env bash
# deepquarry.dme merge repair for the batch train (sourced by tools/dq_merge_batch.sh; tools/ci/test_merge_batch.sh covers it).
#
# The manifest merges by union (.gitattributes), which never stops a merge but can bring back an include one side deleted (a file
# moved on master while a lane appended a line next to it: the conflicting hunk is kept from both sides). And a merge without the
# union driver stops on the manifest alone. Neither is a reason to bounce a lane: the include SET merges cleanly (an addition from
# either side kept, a removal from either side kept), and the result is checked against the files on disk.
#
#   dme_merge3 BASE OURS THEIRS OUT     the three-way merge of the include set (THE function to swap: the tools/generated-dme lane's
#                                       generator, `python3 tools/build/gen_dme.py --merge BASE OURS THEIRS`, does the same and orders
#                                       the result by its spec; replace this body with that call when it lands)
#   dme_missing FILE [ROOT]             prints every #include of FILE whose file does not exist under ROOT (default .)
#   dme_resolve_conflict                in a stopped merge whose ONLY conflict is deepquarry.dme: merge the set, verify, commit. 0 = resolved
#   dme_repair_after_merge              after a clean merge commit (HEAD = the merge): drop includes of missing files that one side deleted
#                                       (the union's resurrected lines) and amend; 0 = nothing to do or repaired, 1 = still missing files
DME_FILE="${DQ_DME_FILE:-deepquarry.dme}"

dme_merge3() { # BASE OURS THEIRS OUT: the set merge; OURS' order, THEIRS' additions placed after their nearest kept predecessor
	awk -v base="$1" -v ours="$2" -v theirs="$3" '
		function norm(s) { sub(/\r$/, "", s); return s }
		BEGIN {
			while ((getline l < base) > 0) inb[norm(l)] = 1
			nt = 0; while ((getline l < theirs) > 0) { l = norm(l); t[++nt] = l; int_[l] = 1 }
			no = 0; while ((getline l < ours) > 0) { l = norm(l); o[++no] = l; ino[l] = 1 }
			# keep ours, minus what theirs deleted (in base, not in theirs)
			n = 0
			for (i = 1; i <= no; i++) if (!(inb[o[i]] && !int_[o[i]])) { r[++n] = o[i]; inr[o[i]] = 1 }
			# theirs additions (not in base, not already kept): after the nearest preceding theirs line that is in the result
			for (j = 1; j <= nt; j++) {
				l = t[j]
				if (inb[l] || inr[l]) continue
				pos = 0
				for (k = j - 1; k >= 1 && !pos; k--) if (inr[t[k]]) for (m = 1; m <= n; m++) if (r[m] == t[k]) { pos = m; break }
				for (m = n; m > pos; m--) r[m + 1] = r[m]
				r[pos + 1] = l; n++; inr[l] = 1
			}
			for (i = 1; i <= n; i++) print r[i]
		}' >"$4"
}

dme_includes() { # FILE: the included paths, forward slashes
	sed -n 's/^[[:space:]]*#include[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | tr -d '\r' | tr '\\' '/'
}

dme_missing() { # FILE [ROOT]
	local root="${2:-.}" p
	dme_includes "$1" | while IFS= read -r p; do [ -e "$root/$p" ] || echo "$p"; done
}

dme_resolve_conflict() {
	local u tmp miss
	u="$(git diff --name-only --diff-filter=U 2>/dev/null)"
	[ "$u" = "$DME_FILE" ] || return 1
	tmp="$(mktemp -d)" || return 1
	git show ":1:$DME_FILE" >"$tmp/base" 2>/dev/null || : >"$tmp/base"
	git show ":2:$DME_FILE" >"$tmp/ours" 2>/dev/null || { rm -rf "$tmp"; return 1; }
	git show ":3:$DME_FILE" >"$tmp/theirs" 2>/dev/null || { rm -rf "$tmp"; return 1; }
	dme_merge3 "$tmp/base" "$tmp/ours" "$tmp/theirs" "$DME_FILE" || { rm -rf "$tmp"; return 1; }
	rm -rf "$tmp"
	miss="$(dme_missing "$DME_FILE")"
	if [ -n "$miss" ]; then
		echo "dme: the merged include set names files that are not on disk; not resolved:" >&2
		echo "$miss" | head -n 10 | sed 's/^/   /' >&2
		return 1
	fi
	git add -- "$DME_FILE" && git commit -q --no-edit >/dev/null 2>&1 || return 1
	echo "dme: resolved a $DME_FILE-only conflict by merging the include sets (verified against the files on disk)"
	return 0
}

dme_repair_after_merge() {
	local miss p tmp drop=0 left=""
	[ -f "$DME_FILE" ] || return 0
	git rev-parse -q --verify HEAD^2 >/dev/null 2>&1 || return 0
	miss="$(dme_missing "$DME_FILE")"
	[ -n "$miss" ] || return 0
	tmp="$(mktemp -d)" || return 1
	git show "HEAD^1:$DME_FILE" 2>/dev/null | dme_includes /dev/stdin >"$tmp/ours"
	git show "HEAD^2:$DME_FILE" 2>/dev/null | dme_includes /dev/stdin >"$tmp/theirs"
	git show "$(git merge-base HEAD^1 HEAD^2 2>/dev/null):$DME_FILE" 2>/dev/null | dme_includes /dev/stdin >"$tmp/base"
	: >"$tmp/drop"
	while IFS= read -r p; do
		# a line one side deleted (in base, missing on a side) for a file that is gone: the union brought it back
		if grep -qxF -- "$p" "$tmp/base" && { ! grep -qxF -- "$p" "$tmp/ours" || ! grep -qxF -- "$p" "$tmp/theirs"; }; then
			echo "$p" >>"$tmp/drop"; drop=1
		else
			left="$left $p"
		fi
	done <<<"$miss"
	if [ "$drop" -eq 1 ]; then
		awk -v dropf="$tmp/drop" 'BEGIN { while ((getline l < dropf) > 0) d[l] = 1 }
			{ p = $0; if (match(p, /^[[:space:]]*#include[[:space:]]*"[^"]*"/)) { q = p; sub(/^[[:space:]]*#include[[:space:]]*"/, "", q); sub(/".*/, "", q); gsub(/\\/, "/", q); if (q in d) next } print }' \
			"$DME_FILE" >"$tmp/new" && cat "$tmp/new" >"$DME_FILE"
		git add -- "$DME_FILE" && git commit -q --amend --no-edit >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
		echo "dme: dropped $(wc -l <"$tmp/drop" | tr -d ' ') include(s) of deleted files that the union merge brought back: $(tr '\n' ' ' <"$tmp/drop")"
	fi
	rm -rf "$tmp"
	if [ -n "$left" ]; then echo "dme: includes of missing files that no side deleted (the compile will name them):$left" >&2; return 1; fi
	return 0
}
