#!/usr/bin/env bash
# Gate verdicts keyed by the exact inputs a gate job reads (sourced by tools/dq_merge_gates.sh; tools/ci/test_train.sh covers it).
#
# A job whose inputs are byte-identical to a tree that already passed it gives the same verdict, so the gate reuses the pass instead of
# running the job again. Only PASSES are stored, and only after the job really ran and passed on this machine; a failure always reruns.
# The key is a hash of every input, never a guess about which change "matters": what is not in the key must not be read by the job.
#
#   dreamchecker   SpacemanDMM's DreamChecker has no incremental mode (a whole-tree parse, 2-7 min). Key (gate_dc_key): the DreamChecker
#                  binary's content hash, the index entries (mode, blob id, path) of every tracked file outside doc/, tools/, tgui/,
#                  html/changelogs/, .github/, SQL/ and *.md (the include closure of deepquarry.dme lives in code/, maps/, interface/,
#                  plus SpacemanDMM.toml, icons, sounds: all kept), plus the content of every untracked or ignored file under code/,
#                  maps/ and interface/ (the generated DM: code/engine/_generated, code/_generated, the verdigris bindings). So a lane that
#                  changes only scripts, docs, tgui or the Rust tools reuses master's DreamChecker pass; any DM change runs it.
#
# Store: DQ_GATE_VERDICTS (default E:/dq-cache/train/verdicts, under the train's disposable state), one file per pass:
# <kind>.<key>.ok with the commit and time. At most DQ_GATE_VERDICTS_KEEP (400) per kind are kept, newest first. DQ_GATE_VERDICTS=off
# disables reuse (every job runs).

gate_verdict_dir() {
	local d="${DQ_GATE_VERDICTS:-}"
	[ "$d" = off ] && return 1
	if [ -z "$d" ]; then
		if [ -d E:/dq-cache ] || [ -d /e/dq-cache ]; then d="E:/dq-cache/train/verdicts"; else d="data/gate-verdicts"; fi
	fi
	mkdir -p "$d" 2>/dev/null || return 1
	echo "$d"
}

gate_dc_binary() { # the DreamChecker the build tool would run (tools/build/build.ts findDreamChecker): DREAMCHECKER_EXE, PATH, ~/SpacemanDMM
	local c
	for c in "${DREAMCHECKER_EXE:-}" "$(command -v dreamchecker 2>/dev/null)" "${USERPROFILE:+$USERPROFILE/SpacemanDMM/dreamchecker.exe}"; do
		[ -n "$c" ] && [ -f "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}

gate_dc_key() { # prints the DreamChecker input key of the checkout in the current directory; exit 1 when it cannot be computed
	local bin bhash tracked extra
	[ -n "${DQ_GATE_DC_KEY_OVERRIDE:-}" ] && { echo "$DQ_GATE_DC_KEY_OVERRIDE"; return 0; } # tools/ci/test_train.sh only
	bin="$(gate_dc_binary)" || return 1
	bhash="$(git hash-object --no-filters -- "$bin" 2>/dev/null)" || return 1
	tracked="$(git ls-files -s -- . ':!doc/' ':!tools/' ':!tgui/' ':!html/changelogs/' ':!.github/' ':!SQL/' ':!*.md' 2>/dev/null | git hash-object --stdin)" || return 1
	# untracked + ignored files where DM lives: their content, path by path (a handful of generated files)
	extra="$(git ls-files -o -z -- code maps interface 2>/dev/null | tr '\0' '\n' | sort | while IFS= read -r f; do [ -f "$f" ] && printf '%s %s\n' "$(git hash-object --no-filters -- "$f")" "$f"; done | git hash-object --stdin)" || return 1
	printf 'dc-v1 %s %s %s' "$bhash" "$tracked" "$extra" | git hash-object --stdin
}

gate_verdict_has() { # <kind> <key>: 0 when a pass is stored (prints its record)
	local d f
	[ -n "${2:-}" ] || return 1
	d="$(gate_verdict_dir)" || return 1
	f="$d/$1.$2.ok"
	[ -f "$f" ] || return 1
	touch "$f" 2>/dev/null
	tr '\n' ' ' <"$f"
	return 0
}

gate_verdict_put() { # <kind> <key> <commit>: record a pass
	local d n
	[ -n "${2:-}" ] || return 0
	d="$(gate_verdict_dir)" || return 0
	printf 'kind=%s\nkey=%s\ncommit=%s\nwhen=%s\nwhere=%s\n' "$1" "$2" "${3:-}" "$(date -u +%FT%TZ)" "$(pwd)" >"$d/$1.$2.ok.tmp" && mv -f "$d/$1.$2.ok.tmp" "$d/$1.$2.ok"
	# bounded: the newest DQ_GATE_VERDICTS_KEEP of this kind stay
	n="${DQ_GATE_VERDICTS_KEEP:-400}"
	ls -t "$d/$1".*.ok 2>/dev/null | tail -n +"$((n + 1))" | while IFS= read -r f; do rm -f -- "$f"; done
	return 0
}
