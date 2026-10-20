#!/usr/bin/env bash
# Sourced by the light-lane tooling (dq_land_batch.sh, dq_light_checks.sh, dq_push_stamp.sh, dq_push_master.sh).
# A light lane is for small work that needs no game build: docs, lane/tooling scripts and Rust/compiler-only changes. It may not touch
# anything the game build, a test world or the map/icon pipeline reads. This is the one list of those paths.
light_heavy_path() { # <path>: 0 when a light lane may not touch it
	case "$1" in
		*.dm|*.dme|*.dmm|*.dmf|*.dmi|*.dmb|*.rsc|maps/*|icons/*|code/*|interface/*|sound/*|tgui/*|deepquarry.dme) return 0 ;;
	esac
	return 1
}
light_heavy_in() { # <base> <tip>: print every heavy path changed between them (the changes of <tip> since the merge base)
	local base f
	base="$(git merge-base "$1" "$2" 2>/dev/null)" || base="$1"
	git diff --name-only "$base" "$2" 2>/dev/null | while IFS= read -r f; do light_heavy_path "$f" && echo "$f"; done
}
