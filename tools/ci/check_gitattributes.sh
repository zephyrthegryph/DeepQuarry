#!/usr/bin/env bash
# Every pattern in .gitattributes must name something that exists, and every merge= driver it names must be one the merge tools supply.
# A file move (the 12b wave moved code/tests/unit_tests/_unit_tests.dm) used to leave its `merge=union` line dead without a word: git
# matched nothing, every parallel lane that added a test conflicted, and trains bounced for it. The generated manifest and the
# baselines have the same exposure.
#
#   bash tools/ci/check_gitattributes.sh [path to a .gitattributes]    # default: the repository's own; run from the worktree root
#
# A plain path must be a tracked file; a glob with a slash must match a tracked file. Bare type patterns (no slash: *.dmm, *.htm) are
# skipped: a type may legitimately have no file. The lone `*` rule is skipped. Drivers: merge=union/text/binary are git's own; any other name needs a merge.<name>.driver line in
# tools/dq_git_safe.sh (which every merge tool sources) or in the repository's config.
set -uo pipefail
cd "$(dirname "$0")/../.."
attr="${1:-.gitattributes}"
safe="${DQ_GITATTR_SAFE:-tools/dq_git_safe.sh}"
fail=0
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
	lineno=$((lineno + 1))
	case "$line" in ''|'#'*) continue ;; esac
	# shellcheck disable=SC2086
	set -- $line
	pat="$1"; shift
	case "$pat" in
		*/*)
			case "$pat" in
				*[\*\?\[]*) found="$(git ls-files -- ":(glob)$pat" | head -n 1)" ;;
				*) found="$(git ls-files -- ":(literal)$pat" | head -n 1)" ;;
			esac
			if [ -z "$found" ]; then
				echo "$attr:$lineno: '$pat' matches no tracked file (moved or deleted? update the path, or drop the line)"
				fail=1
			fi ;;
	esac
	for a in "$@"; do
		case "$a" in
			merge=union|merge=text|merge=binary|merge=dmm|merge=dmi) ;;   # git's own, or installed by tools/hooks/install.sh
			merge=*)
				name="${a#merge=}"
				if ! grep -q "merge\.$name\.driver" "$safe" 2>/dev/null && [ -z "$(git config --get "merge.$name.driver" 2>/dev/null)" ]; then
					echo "$attr:$lineno: merge driver '$name' (for '$pat') is defined nowhere: add it to $safe"
					fail=1
				fi ;;
		esac
	done
done <"$attr"
[ "$fail" -eq 0 ] && echo "check_gitattributes: every .gitattributes pattern matches a file and every merge driver exists"
exit "$fail"
