#!/usr/bin/env bash
# Machine-wide counting semaphores for the heavy steps every worktree runs: a cap on how many DM compiles, test
# worlds, cargo builds and look-state pins run at once on this machine, so a dozen agents do not turn a 2 minute
# step into a 10 minute one by fighting over 16 cores.
#
#   bash tools/dq_machine_slots.sh run <class> [--label TEXT] -- <command...>   # hold a slot while the command runs
#   bash tools/dq_machine_slots.sh status [class]                                # who holds what, who waits
#   bash tools/dq_machine_slots.sh stats [N]                                     # the last N waits and holds (default 20)
#   bash tools/dq_machine_slots.sh reap                                          # drop dead holders and waiters now
#   bash tools/dq_machine_slots.sh selftest                                      # exercise it in a scratch directory
#   source tools/dq_machine_slots.sh; slots_acquire <class> [label]; ...; slots_release   # in a script (set a trap)
#
# Classes and default counts (an env var overrides each; 0 turns that class off; DQ_SLOTS=0 turns all of it off):
#   dm_compile      DQ_SLOTS_DM_COMPILE=2       a DreamMaker compile (tools/build/lib/byond.ts DreamMaker())
#   test_world      DQ_SLOTS_TEST_WORLD=3       one DreamDaemon unit-test world (tools/build/build.ts runIsolatedTestWorld())
#   cargo           DQ_SLOTS_CARGO=1            a cargo build (analyze, verdigris, dmb-check)
#   look_state_pin  DQ_SLOTS_LOOK_STATE_PIN=2   a focused run holding dq_look_state_pin / dq_look_tree_pin
#                                               (DQ_LOOK_PIN_SLOTS is accepted as the old name)
# Lock order when a run needs several: look_state_pin, then test_world; dm_compile and cargo are never held while waiting
# for another class. A class not listed gets DQ_SLOTS_<CLASS> or 1.
#
# State lives under DQ_SLOTS_DIR (default E:/dq-cache/slots, else ~/.cache/dq/slots), one directory per class:
#   slot.N/owner        a held slot (an atomic mkdir). key=value lines: pid, winpid, kind (bash|node), worktree, label,
#                       started. The file's mtime is the holder's heartbeat, touched every 15 s while it holds the slot.
#   queue/P-T-PID       a waiter. P is 0 for the merge worktree (DQ_MERGE_WT, default E:/projects/dq-wt/merge-base) and 1
#                       for everyone else, T the arrival time, so the merge worktree jumps the queue and the rest go in
#                       arrival order. A waiter takes a slot only when it is first. Its mtime is refreshed on every poll.
#   events.tsv          one line per release: time, class, slot, worktree, label, waited seconds, held seconds.
# A holder or waiter is dead when its pid is gone (a bash pid is checked with kill -0, a node pid through its Windows
# pid), or when its heartbeat is older than DQ_SLOTS_STALE_SEC (default 600; this covers pid reuse and a frozen holder
# and the one case a pid cannot be checked cheaply). A dead slot is removed by the next waiter, so a crashed run never
# blocks the queue. The same protocol is implemented in tools/build/lib/machine_slots.ts for the build tool; keep the
# two in sync (the selftest and tools/build/lib/machine_slots.test.ts check they agree).
#
# Waiting prints the class, your place in the queue and who holds the slots every 30 s. DQ_SLOT_PRIORITY=0 forces the
# front of the queue for a caller that is not the merge worktree.

slots_dir() {
	if [ -n "${DQ_SLOTS_DIR:-}" ]; then
		echo "$DQ_SLOTS_DIR"
	elif [ -d /e/dq-cache ] || [ -d "E:/dq-cache" ]; then
		echo "E:/dq-cache/slots"
	else
		echo "${HOME:-/tmp}/.cache/dq/slots"
	fi
}

slots_capacity() { # class -> count (0 = off)
	local cls="$1" up var val
	[ "${DQ_SLOTS:-1}" = "0" ] && { echo 0; return; }
	up="$(printf '%s' "$cls" | tr 'a-z' 'A-Z')"
	var="DQ_SLOTS_$up"
	val="${!var:-}"
	if [ -z "$val" ] && [ "$cls" = "look_state_pin" ]; then val="${DQ_LOOK_PIN_SLOTS:-}"; fi
	if [ -z "$val" ]; then
		case "$cls" in
			dm_compile) val=2 ;;
			test_world) val=3 ;;
			cargo) val=1 ;;
			look_state_pin) val=2 ;;
			*) val=1 ;;
		esac
	fi
	case "$val" in '' | *[!0-9]*) val=1 ;; esac
	echo "$val"
}

_slots_norm() { printf '%s' "$1" | tr 'A-Z\\' 'a-z/' | sed -e 's|^/\([a-z]\)/|\1:/|' -e 's|/*$||'; }

_slots_worktree() {
	if [ -n "${DQ_SLOT_WORKTREE:-}" ]; then echo "$DQ_SLOT_WORKTREE"; return; fi
	git rev-parse --show-toplevel 2>/dev/null || pwd
}

_slots_priority() { # worktree -> 0 (merge worktree, front of the queue) or 1
	if [ -n "${DQ_SLOT_PRIORITY:-}" ]; then echo "$DQ_SLOT_PRIORITY"; return; fi
	if [ "$(_slots_norm "$1")" = "$(_slots_norm "${DQ_MERGE_WT:-E:/projects/dq-wt/merge-base}")" ]; then echo 0; else echo 1; fi
}

_slots_winpid() { cat "/proc/$1/winpid" 2>/dev/null || echo "$1"; }

_slots_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

_slots_mtime() { # file -> epoch seconds (0 when missing)
	local t
	t="$(stat -c %Y "$1" 2>/dev/null)" || t=0
	echo "${t:-0}"
}

# Is the process that wrote this owner/queue file still alive? Dead when its pid is gone or its heartbeat is stale.
_slots_dead() { # file
	local f="$1" kind pid winpid age stale="${DQ_SLOTS_STALE_SEC:-600}"
	[ -f "$f" ] || return 0
	kind="$(_slots_field "$f" kind)"
	pid="$(_slots_field "$f" pid)"
	winpid="$(_slots_field "$f" winpid)"
	age=$(( $(date +%s) - $(_slots_mtime "$f") ))
	if [ "$age" -gt "$stale" ]; then return 0; fi
	if [ "$kind" = "bash" ] && [ -n "$pid" ]; then
		kill -0 "$pid" 2>/dev/null && return 1 || return 0
	fi
	if [ -n "$winpid" ] && command -v tasklist >/dev/null 2>&1; then
		tasklist //FI "PID eq $winpid" //NH 2>/dev/null | grep -qw "$winpid" && return 1 || return 0
	fi
	if [ -n "$pid" ]; then kill -0 "$pid" 2>/dev/null && return 1 || return 0; fi
	return 1
}

SLOTS_HELD=""        # the slot directory this shell holds
SLOTS_HELD_CLASS=""
SLOTS_QUEUE=""       # this shell's queue file
SLOTS_HB_PID=""      # the heartbeat loop
SLOTS_T_QUEUED=0
SLOTS_T_GOT=0

_slots_reap() { # class dir: remove dead holders and waiters
	local d="$1" f
	for f in "$d"/queue/*; do
		[ -f "$f" ] || continue
		_slots_dead "$f" && rm -f "$f"
	done
	for f in "$d"/slot.*; do
		[ -d "$f" ] || continue
		if [ ! -f "$f/owner" ]; then
			# mkdir done, owner not written yet: give the taker a moment, then treat the slot as dead.
			sleep 1
			[ -f "$f/owner" ] || rm -rf "$f"
		elif _slots_dead "$f/owner"; then
			echo "== machine slots: reclaiming a dead slot ($f: $(_slots_field "$f/owner" worktree) pid $(_slots_field "$f/owner" pid) $(_slots_field "$f/owner" label))" >&2
			rm -rf "$f"
		fi
	done
}

_slots_who() { # class dir -> " [slot N: worktree 'label' held 3m] ..."
	local d="$1" f out="" now started
	now="$(date +%s)"
	for f in "$d"/slot.*; do
		[ -f "$f/owner" ] || continue
		started="$(_slots_field "$f/owner" started)"
		out="$out [${f##*/}: $(_slots_field "$f/owner" worktree) '$(_slots_field "$f/owner" label)' pid $(_slots_field "$f/owner" pid), held $(( now - ${started:-$now} ))s]"
	done
	echo "${out:- nobody}"
}

_slots_acquire() {
	local cls="${1:?class}" label="${2:-}" max root d top prio now name waited=0 last=0 i pos
	max="$(slots_capacity "$cls")"
	[ "$max" -gt 0 ] 2>/dev/null || return 0
	root="$(slots_dir)"
	d="$root/$cls"
	mkdir -p "$d/queue" 2>/dev/null || { echo "== machine slots: cannot create $d; running without a $cls limit" >&2; return 0; }
	top="$(_slots_worktree)"
	prio="$(_slots_priority "$top")"
	now="$(date +%s)"
	name="$prio-$(printf '%013d' "$now")-$$"
	SLOTS_QUEUE="$d/queue/$name"
	printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nqueued=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$now" >"$SLOTS_QUEUE"
	SLOTS_T_QUEUED="$now"
	while true; do
		_slots_reap "$d"
		if [ "$(ls "$d/queue" 2>/dev/null | sort | head -n 1)" = "$name" ]; then
			for ((i = 1; i <= max; i++)); do
				if mkdir "$d/slot.$i" 2>/dev/null; then
					printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nstarted=%s\npriority=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$(date +%s)" "$prio" >"$d/slot.$i/owner"
					SLOTS_HELD="$d/slot.$i"
					SLOTS_HELD_CLASS="$cls"
					SLOTS_T_GOT="$(date +%s)"
					rm -f "$SLOTS_QUEUE"
					SLOTS_QUEUE=""
					_slots_heartbeat "$d/slot.$i/owner"
					if [ "$waited" -gt 0 ]; then
						echo "== machine slots: $cls slot $i of $max after ${waited}s in the queue"
					else
						echo "== machine slots: $cls slot $i of $max"
					fi
					return 0
				fi
			done
		fi
		if [ "$waited" -eq 0 ] || [ $((waited - last)) -ge 30 ]; then
			last="$waited"
			pos="$(ls "$d/queue" 2>/dev/null | sort | grep -n -x -- "$name" | cut -d: -f1)"
			echo "== machine slots: $cls: waiting ${waited}s, place ${pos:-?} of $(ls "$d/queue" 2>/dev/null | wc -l) in the queue (at most $max at once on this machine; the merge worktree goes first). Held by:$(_slots_who "$d")"
		fi
		touch "$SLOTS_QUEUE" 2>/dev/null
		sleep "${DQ_SLOTS_POLL_SEC:-3}"
		waited=$((waited + ${DQ_SLOTS_POLL_SEC:-3}))
	done
}

# A script that sources this runs under `set -e`; these functions test exit codes freely (grep, kill -0, ls), so they run with it off.
_slots_errexit_off() {
	case $- in *e*) SLOTS_ERREXIT=1; set +e ;; *) SLOTS_ERREXIT=0 ;; esac
}
_slots_errexit_back() {
	if [ "${SLOTS_ERREXIT:-0}" = "1" ]; then set -e; fi
	return 0
}

slots_acquire() { # class [label]: waits for a slot; sets the SLOTS_* globals
	local rc
	_slots_errexit_off
	_slots_acquire "$@"
	rc=$?
	_slots_errexit_back
	return "$rc"
}

_slots_heartbeat() { # owner file: touch it every 15 s while this shell lives
	local owner="$1" parent="$$"
	(
		while kill -0 "$parent" 2>/dev/null; do
			sleep "${DQ_SLOTS_HEARTBEAT_SEC:-15}"
			[ -f "$owner" ] || exit 0
			touch "$owner" 2>/dev/null || exit 0
		done
	) >/dev/null 2>&1 &
	SLOTS_HB_PID=$!
	disown "$SLOTS_HB_PID" 2>/dev/null || true
}

_slots_release() {
	local now owner worktree label started
	now="$(date +%s)"
	if [ -n "$SLOTS_HB_PID" ]; then kill "$SLOTS_HB_PID" 2>/dev/null; SLOTS_HB_PID=""; fi
	if [ -n "$SLOTS_HELD" ]; then
		owner="$SLOTS_HELD/owner"
		worktree="$(_slots_field "$owner" worktree)"
		label="$(_slots_field "$owner" label)"
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$SLOTS_HELD_CLASS" "${SLOTS_HELD##*.}" "$worktree" "$label" "$((SLOTS_T_GOT - SLOTS_T_QUEUED))" "$((now - SLOTS_T_GOT))" >>"$(slots_dir)/events.tsv" 2>/dev/null
		rm -rf "$SLOTS_HELD"
		SLOTS_HELD=""
	fi
	if [ -n "$SLOTS_QUEUE" ]; then rm -f "$SLOTS_QUEUE"; SLOTS_QUEUE=""; fi
}

slots_release() {
	local rc
	_slots_errexit_off
	_slots_release
	rc=$?
	_slots_errexit_back
	return "$rc"
}

slots_run() { # class [--label TEXT] -- command...
	local cls="${1:?class}" label="" rc
	shift
	if [ "${1:-}" = "--label" ]; then label="${2:-}"; shift 2; fi
	[ "${1:-}" = "--" ] && shift
	[ $# -gt 0 ] || { echo "usage: dq_machine_slots.sh run <class> [--label TEXT] -- <command...>" >&2; return 2; }
	[ -n "$label" ] || label="$*"
	trap 'slots_release' EXIT
	trap 'slots_release; exit 130' INT
	trap 'slots_release; exit 143' TERM
	slots_acquire "$cls" "${label:0:80}"
	"$@"
	rc=$?
	slots_release
	trap - EXIT INT TERM
	return "$rc"
}

slots_status() { # [class]
	local root cls d f any=0 now max
	root="$(slots_dir)"
	now="$(date +%s)"
	for cls in ${1:-dm_compile test_world cargo look_state_pin}; do
		d="$root/$cls"
		max="$(slots_capacity "$cls")"
		echo "$cls: at most $max at once$( [ "$max" -eq 0 ] && echo ' (limit off)')"
		for f in "$d"/slot.*; do
			[ -f "$f/owner" ] || continue
			any=1
			echo "  ${f##*/}: $(_slots_field "$f/owner" worktree) '$(_slots_field "$f/owner" label)' pid $(_slots_field "$f/owner" pid), held $(( now - $(_slots_field "$f/owner" started) ))s, heartbeat $(( now - $(_slots_mtime "$f/owner") ))s ago$(_slots_dead "$f/owner" && echo ' [DEAD, reclaimed by the next waiter]')"
		done
		for f in "$d"/queue/*; do
			[ -f "$f" ] || continue
			any=1
			echo "  waiting ${f##*/}: $(_slots_field "$f" worktree) '$(_slots_field "$f" label)' pid $(_slots_field "$f" pid), queued $(( now - $(_slots_field "$f" queued) ))s$(_slots_dead "$f" && echo ' [DEAD]')"
		done
	done
	[ "$any" -eq 1 ] || echo "(nothing held, nobody waiting)"
}

slots_stats() { # [N]
	local f
	f="$(slots_dir)/events.tsv"
	[ -f "$f" ] || { echo "no events yet ($f)"; return 0; }
	echo "time	class	slot	worktree	label	waited_s	held_s"
	tail -n "${1:-20}" "$f"
	awk -F'\t' '{ w[$2] += $6; h[$2] += $7; n[$2]++ } END { for (c in n) printf "%s: %d runs, mean wait %.0fs, mean hold %.0fs\n", c, n[c], w[c] / n[c], h[c] / n[c] }' "$f"
}

# Exercises the protocol in a scratch directory: capacity, queue order, priority, crash recovery, the stats log.
slots_selftest() {
	local tmp out ok=1 p1 p2 p3
	tmp="$(mktemp -d)"
	export DQ_SLOTS_DIR="$tmp" DQ_SLOTS_POLL_SEC=1 DQ_SLOTS_HEARTBEAT_SEC=1 DQ_SLOTS_CARGO=1 DQ_SLOT_WORKTREE=/x/selftest
	echo "selftest in $tmp"
	# 1. capacity 1: three 3 s runs finish in order, one at a time.
	( bash "$0" run cargo --label a -- bash -c 'echo a-start; sleep 3; echo a-end' >"$tmp/a.log" 2>&1 ) & p1=$!
	sleep 1
	( bash "$0" run cargo --label b -- bash -c 'echo b-start; sleep 3; echo b-end' >"$tmp/b.log" 2>&1 ) & p2=$!
	sleep 1
	( DQ_SLOT_PRIORITY=0 bash "$0" run cargo --label c-priority -- bash -c 'echo c-start; sleep 1; echo c-end' >"$tmp/c.log" 2>&1 ) & p3=$!
	sleep 1
	out="$(bash "$0" status cargo)"
	echo "$out"
	echo "$out" | grep -q "'a'" && echo "$out" | grep -q "waiting" || { echo "FAIL: status should show a holder and waiters"; ok=0; }
	wait "$p1" "$p2" "$p3"
	# c arrived last but has priority 0: it must start before b (a holds the only slot until its 3 s end).
	local order
	order="$(awk -F'\t' '{ print $5 }' "$tmp/events.tsv" | tr '\n' ' ')"
	echo "release order: $order"
	[ "$order" = "a c-priority b " ] || { echo "FAIL: expected 'a c-priority b ', got '$order'"; ok=0; }
	# 2. a crashed holder (kill -9) is reclaimed by the next waiter.
	local self="$0" wp
	bash -c 'source "$0"; slots_acquire cargo doomed >/dev/null; exec sleep 60' "$self" >"$tmp/d.log" 2>&1 &
	sleep 3
	wp="$(sed -n 's/^pid=//p' "$tmp/cargo/slot.1/owner" 2>/dev/null)"
	[ -n "$wp" ] || { echo "FAIL: the doomed holder never got the slot"; ok=0; }
	kill -9 "$wp" 2>/dev/null
	sleep 1
	out="$(bash "$self" run cargo --label after-crash -- echo reclaimed 2>&1)"
	echo "$out" | grep -q "reclaimed" && echo "$out" | grep -q "reclaiming a dead slot" || { echo "FAIL: the crashed holder's slot was not reclaimed: $out"; ok=0; }
	# 3. a class with 0 slots is off.
	DQ_SLOTS_CARGO=0 bash "$0" run cargo -- echo unlimited | grep -q unlimited || { echo "FAIL: DQ_SLOTS_CARGO=0 should run without a limit"; ok=0; }
	# 4. env counts and the old pin-speed name.
	[ "$(DQ_SLOTS_DM_COMPILE=5 slots_capacity dm_compile)" = 5 ] && [ "$(DQ_LOOK_PIN_SLOTS=4 slots_capacity look_state_pin)" = 4 ] && [ "$(unset DQ_SLOTS_CARGO; slots_capacity cargo)" = 1 ] || { echo "FAIL: capacity env"; ok=0; }
	rm -rf "$tmp"
	if [ "$ok" -eq 1 ]; then echo "selftest: ok"; return 0; fi
	echo "selftest: FAILED"
	return 1
}

# Run as a command, not when sourced (a sourced file can `return`; a script cannot).
if ! (return 0 2>/dev/null); then
	cmd="${1:-}"
	[ $# -gt 0 ] && shift
	case "$cmd" in
		run) slots_run "$@"; exit $? ;;
		status) slots_status "$@" ;;
		stats) slots_stats "$@" ;;
		reap) for c in dm_compile test_world cargo look_state_pin; do _slots_reap "$(slots_dir)/$c"; done; slots_status ;;
		selftest) slots_selftest; exit $? ;;
		*) sed -n '2,12p' "$0"; [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || exit 2 ;;
	esac
fi
