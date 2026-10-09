#!/usr/bin/env bash
# Machine-wide cap on look-pin runs: at most DQ_LOOK_PIN_SLOTS (default 2) run at once across every worktree on this machine.
# Sourced by tools/dq_focused_test.sh when a run holds dq_look_state_pin or dq_look_tree_pin.
#
#   look_lock_acquire   waits for a slot (prints that it is waiting, who holds the slots and its place in the queue)
#   look_lock_release   gives the slot back (the caller's EXIT trap runs it; a dead holder's slot is reclaimed by the next waiter)
#
# State lives under DQ_LOOK_LOCK_DIR (default E:/dq-cache/look-pin-locks, else ~/.cache/dq/look-pin-locks):
#   slot.N/owner      a held slot (an atomic mkdir); the owner file names the pid, worktree and start time
#   queue/<p>-<t>-<pid>  a waiter: p is 0 for the merge worktree (E:/projects/dq-wt/merge-base) and 1 for everyone else, t the
#                     arrival time, so the merge worktree goes first and the rest in arrival order
# A waiter takes a slot only when it is first in the queue, so a later arrival never overtakes an earlier one of its own priority.
# A slot or queue entry whose pid is gone is reclaimed. DQ_LOOK_PIN_SLOTS=0 turns the cap off.

look_lock_dir() {
	if [ -n "${DQ_LOOK_LOCK_DIR:-}" ]; then echo "$DQ_LOOK_LOCK_DIR"; return; fi
	if [ -d /e/dq-cache ]; then echo /e/dq-cache/look-pin-locks; return; fi
	echo "${HOME:-/tmp}/.cache/dq/look-pin-locks"
}

LOOK_LOCK_SLOT=""
LOOK_LOCK_QUEUE=""

look_lock_alive() { # pid
	[ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

look_lock_acquire() {
	local max="${DQ_LOOK_PIN_SLOTS:-2}" root top prio now name waited=0 last_msg=0 i holder pid head pos
	[ "$max" -gt 0 ] 2>/dev/null || return 0
	root="$(look_lock_dir)"
	mkdir -p "$root/queue"
	top="${DQ_LOOK_LOCK_WORKTREE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
	prio=1
	case "$(printf '%s' "$top" | tr 'A-Z\\' 'a-z/')" in */dq-wt/merge-base) prio=0 ;; esac
	now="$(date +%s)"
	name="$prio-$(printf '%013d' "$now")-$$"
	printf 'pid=%s\nworktree=%s\nqueued=%s\n' "$$" "$top" "$now" >"$root/queue/$name"
	LOOK_LOCK_QUEUE="$root/queue/$name"
	while true; do
		# Drop the dead: queue entries and slots whose pid no longer exists.
		for f in "$root"/queue/*; do
			[ -f "$f" ] || continue
			pid="${f##*-}"
			look_lock_alive "$pid" || rm -f "$f"
		done
		for ((i = 1; i <= max; i++)); do
			if [ -d "$root/slot.$i" ]; then
				pid="$(sed -n 's/^pid=//p' "$root/slot.$i/owner" 2>/dev/null)"
				if [ -n "$pid" ] && ! look_lock_alive "$pid"; then
					rm -rf "$root/slot.$i"
				elif [ -z "$pid" ] && [ ! -f "$root/slot.$i/owner" ]; then
					# mkdir done, owner file not yet written: give its taker a moment, then treat it as dead.
					sleep 1
					[ -f "$root/slot.$i/owner" ] || rm -rf "$root/slot.$i"
				fi
			fi
		done
		head="$(ls "$root/queue" 2>/dev/null | sort | head -n 1)"
		if [ "$head" = "$name" ]; then
			for ((i = 1; i <= max; i++)); do
				if mkdir "$root/slot.$i" 2>/dev/null; then
					printf 'pid=%s\nworktree=%s\nstarted=%s\npriority=%s\n' "$$" "$top" "$(date +%s)" "$prio" >"$root/slot.$i/owner"
					LOOK_LOCK_SLOT="$root/slot.$i"
					rm -f "$LOOK_LOCK_QUEUE"
					LOOK_LOCK_QUEUE=""
					if [ "$waited" -gt 0 ]; then echo "== look-pin lock: got slot $i after ${waited}s"; else echo "== look-pin lock: slot $i of $max"; fi
					return 0
				fi
			done
		fi
		if [ $((waited - last_msg)) -ge 30 ] || [ "$waited" -eq 0 ]; then
			last_msg="$waited"
			pos="$(ls "$root/queue" 2>/dev/null | sort | grep -n -x -- "$name" | cut -d: -f1)"
			holder=""
			for ((i = 1; i <= max; i++)); do
				if [ -f "$root/slot.$i/owner" ]; then
					holder="$holder [slot $i: $(sed -n 's/^worktree=//p' "$root/slot.$i/owner") pid $(sed -n 's/^pid=//p' "$root/slot.$i/owner")]"
				fi
			done
			echo "== look-pin lock: waiting ${waited}s (place ${pos:-?} in the queue; at most $max look-pin runs at once on this machine; the merge worktree goes first). Held by:${holder:- nobody yet}"
		fi
		sleep 5
		waited=$((waited + 5))
	done
}

look_lock_release() {
	if [ -n "$LOOK_LOCK_SLOT" ]; then rm -rf "$LOOK_LOCK_SLOT"; LOOK_LOCK_SLOT=""; fi
	if [ -n "$LOOK_LOCK_QUEUE" ]; then rm -f "$LOOK_LOCK_QUEUE"; LOOK_LOCK_QUEUE=""; fi
}
