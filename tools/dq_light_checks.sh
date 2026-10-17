#!/usr/bin/env bash
# The cheap checks of a light batch, for exactly what changed (no DM compile, no test world):
#
#   bash tools/dq_light_checks.sh <base> <head>     # exit 0 when every check for the changed files passed
#
#   - bash -n on every changed *.sh (and shellcheck -S error when it is installed);
#   - doc links: every relative link in a changed *.md / doc/*.html must resolve to a file in <head>;
#   - cargo test for every Cargo manifest above a changed file under tools/ or verdigris/ (inside a machine cargo slot);
#   - the ratchets (tools/ci/check_ratchets.sh) only when a .dm file changed or the lints themselves (tools/ci, tools/analyze) did;
#   - a changed heavy path (tools/dq_light_paths.sh) is a refusal: a light batch never carries it.
# DQ_LIGHT_CARGO=0 skips cargo (fixture tests). Run from the worktree that holds <head>.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. "$(dirname "${BASH_SOURCE[0]}")/dq_light_paths.sh"
base="${1:?base}"; head="${2:-HEAD}"
fail=0
bad() { echo "light check FAILED: $*" >&2; fail=1; }
mapfile -t changed < <(git diff --name-only --diff-filter=ACMR "$base" "$head")
mapfile -t deleted < <(git diff --name-only --diff-filter=D "$base" "$head")
echo "== light checks: ${#changed[@]} changed file(s), ${#deleted[@]} deleted"

heavy="$(git diff --name-only "$base" "$head" | while IFS= read -r f; do light_heavy_path "$f" && echo "$f"; done)"
[ -z "$heavy" ] || bad "heavy paths in a light batch (use a general lane): $(echo "$heavy" | head -5 | tr '\n' ' ')"

for f in "${changed[@]}"; do
	case "$f" in *.sh) bash -n "$f" 2>&1 || bad "bash -n $f"; command -v shellcheck >/dev/null 2>&1 && { shellcheck -S error "$f" || bad "shellcheck $f"; } ;; esac
done

check_links() { # <file>
	local file="$1" dir t target
	dir="$(dirname "$file")"
	while IFS= read -r t; do
		target="${t%%#*}"; target="${target%%\?*}"
		[ -n "$target" ] || continue
		case "$target" in http:*|https:*|mailto:*|data:*|javascript:*|//*) continue ;; esac
		case "$target" in /*) target="${target#/}" ;; *) target="$dir/$target" ;; esac
		git cat-file -e "$head:$(realpath -m --relative-to=. "$target" 2>/dev/null || echo "$target")" 2>/dev/null || bad "$file links to $t, which does not exist"
	done < <(
		case "$file" in
			*.md) git show "$head:$file" | grep -o -E '\]\([^)[:space:]]+\)' | sed -E 's/^\]\((.*)\)$/\1/' ;;
			*) git show "$head:$file" | grep -o -E '(href|src)="[^"]+"' | sed -E 's/^[a-z]+="(.*)"$/\1/' ;;
		esac
	)
}
for f in "${changed[@]}"; do
	case "$f" in *.md|doc/*.html) check_links "$f" ;; esac
done

if [ "${DQ_LIGHT_CARGO:-1}" = 1 ]; then
	declare -A manifests=()
	for f in "${changed[@]}"; do
		case "$f" in tools/*|verdigris/*) ;; *) continue ;; esac
		d="$(dirname "$f")"
		while [ "$d" != "." ] && [ "$d" != "/" ]; do
			if git cat-file -e "$head:$d/Cargo.toml" 2>/dev/null; then manifests["$d/Cargo.toml"]=1; break; fi
			d="$(dirname "$d")"
		done
	done
	for m in "${!manifests[@]}"; do
		echo "== cargo test --manifest-path $m"
		bash tools/dq_machine_slots.sh run cargo --label "light-batch $m" -- cargo test --manifest-path "$m" || bad "cargo test $m"
	done
fi

if printf '%s\n' "${changed[@]}" "${deleted[@]}" | grep -q -E '\.dm$|^tools/ci/|^tools/analyze/'; then
	echo "== ratchets (a .dm file or the lints changed)"
	bash tools/ci/check_ratchets.sh || bad "check_ratchets.sh"
fi
[ "$fail" -eq 0 ] && echo "== light checks passed" || exit 1
