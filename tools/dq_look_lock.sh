#!/usr/bin/env bash
# The machine-wide cap on look-pin runs (at most DQ_SLOTS_LOOK_STATE_PIN, default 2, at once across every worktree; the merge
# worktree goes first; 0 turns the cap off). It is one class of tools/dq_machine_slots.sh, which holds the protocol, the queue, the
# dead-holder reclaim and the status/stats commands; this file keeps the two functions tools/dq_focused_test.sh calls.
#
#   look_lock_acquire   waits for a slot (prints that it is waiting, who holds the slots and its place in the queue)
#   look_lock_release   gives the slot back (the caller's EXIT trap runs it; a dead holder's slot is reclaimed by the next waiter)
#
# DQ_LOOK_PIN_SLOTS is accepted as the old name of DQ_SLOTS_LOOK_STATE_PIN. `bash tools/dq_machine_slots.sh status look_state_pin`
# shows who holds the slots.

# shellcheck source=tools/dq_machine_slots.sh
. "$(dirname "${BASH_SOURCE[0]}")/dq_machine_slots.sh"

look_lock_acquire() {
	slots_acquire look_state_pin "${DQ_LOOK_LOCK_LABEL:-look pins}"
}

look_lock_release() {
	slots_release
}
