#!/usr/bin/env bash
# Sourced by the light-lane tooling (dq_land_batch.sh, dq_light_checks.sh, dq_push_stamp.sh, dq_push_master.sh).
# A light lane is for small work that needs no game build: docs, lane/tooling scripts and Rust/compiler-only changes. It may not touch
# anything the game build, a test world or the map/icon pipeline reads. This is the one list of those paths.
light_heavy_path() { # <path>: 0 when a light lane may not touch it
	case "$1" in
		*.dm|*.dme|*.dmm|*.dmf|*.dmi|*.dmb|*.rsc|maps/*|icons/*|code/*|interface/*|sound/*|deepquarry.dme) return 0 ;;
		# DM embeds or reads these two; the rest of tgui/ no DM gate reads (a world runs without a built bundle), and the lints that read
		# interfaces/ and .jsx are run by dq_light_checks.sh
		tgui/public/*|tgui/packages/tgfont/static/*) return 0 ;;
	esac
	return 1
}
# A gate's verdict does not read these: a heavy gate running while one of them lands on master still proves its lanes (dq_push_master.sh
# DQ_PUSH_NEUTRAL_OK, dq_train.sh light_side). A list of what is known not to matter, not of what is not known to: the compiler, the
# build, the analyzer, verdigris, the lints and their baselines, and anything a world reads are all left out.
light_gate_neutral() { # <path>
	light_heavy_path "$1" && return 1
	light_gate_lint_read "$1" && return 1
	case "$1" in
		doc/*|html/changelogs/*|*.md|tools/ci/test_*.sh|tools/train/*|tools/hooks/*|tgui/*) return 0 ;;
		tools/*/*) return 1 ;;
		tools/dq_*.sh|tools/dq_*.js|tools/dq_*.py) return 0 ;;
	esac
	return 1
}
# What the compile and the tests do not read, though a lint may: the same list plus the light part of tgui/. A push across one of these keeps the compile's proof;
# light_gate_lint_read says when it must run the ratchets again.
light_gate_compile_neutral() { # <path>
	light_gate_neutral "$1" && return 0
	light_heavy_path "$1" && return 1
	case "$1" in tgui/*) return 0 ;; esac
	return 1
}
light_gate_lint_read() { # <path>: ui_actions and check_grep read these (the ratchet rule of dq_light_checks.sh)
	case "$1" in tgui/packages/tgui/interfaces/*|tgui/*.jsx) return 0 ;; esac
	return 1
}
light_gate_unneutral_in() { # <base> <tip>: print every path changed since their merge base that a gate may read
	local base f
	base="$(git merge-base "$1" "$2" 2>/dev/null)" || { echo "(no merge base of $1 and $2)"; return 0; }
	git diff --name-only "$base" "$2" 2>/dev/null | while IFS= read -r f; do "${3:-light_gate_neutral}" "$f" || echo "$f"; done
}
light_heavy_in() { # <base> <tip>: print every heavy path changed between them (the changes of <tip> since the merge base)
	local base f
	base="$(git merge-base "$1" "$2" 2>/dev/null)" || base="$1"
	git diff --name-only "$base" "$2" 2>/dev/null | while IFS= read -r f; do light_heavy_path "$f" && echo "$f"; done
}
