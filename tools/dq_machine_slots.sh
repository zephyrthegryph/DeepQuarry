#!/usr/bin/env bash
# Machine-wide counting semaphores for the heavy steps every worktree runs: a cap on how many DM compiles, test
# worlds, cargo builds run at once on this machine, so a dozen agents do not turn a 2 minute
# step into a 10 minute one by fighting over 16 cores.
#
#   bash tools/dq_machine_slots.sh run <class> [--label TEXT] -- <command...>   # hold a slot while the command runs
#   bash tools/dq_machine_slots.sh status [class]                                # who holds what, who waits
#   bash tools/dq_machine_slots.sh waiting <worktree>                            # the queue entries a worktree has (class, seconds)
#   bash tools/dq_machine_slots.sh holding <worktree>                            # the slots a worktree holds right now
#   bash tools/dq_machine_slots.sh stats [N]                                     # the last N waits and holds (default 20)
#   bash tools/dq_machine_slots.sh reap                                          # drop dead holders and waiters now
#   bash tools/dq_machine_slots.sh selftest                                      # exercise it in a scratch directory
#   source tools/dq_machine_slots.sh; slots_acquire <class> [label]; ...; slots_release   # in a script (set a trap)
#
# Classes and default counts (an env var overrides each; 0 turns that class off; DQ_SLOTS=0 turns all of it off):
#   dm_compile      DQ_SLOTS_DM_COMPILE=1       a DreamMaker compile (tools/build/lib/byond.ts DreamMaker())
#   test_world      DQ_SLOTS_TEST_WORLD=2       one DreamDaemon unit-test world (tools/build/build.ts runIsolatedTestWorld()). A full-suite dm-test
#                                               (DQ_SLOTS_SUITE=1) may hold all of the capacity; every other caller holds at most
#                                               DQ_SLOTS_TEST_WORLD_FOCUSED (2). Setting DQ_SLOTS_TEST_WORLD itself is one limit for everyone.
#   cargo           DQ_SLOTS_CARGO=1            a cargo build (analyze, verdigris, dmbc)
# dm_compile and cargo are never held while waiting for another class. A class not listed gets DQ_SLOTS_<CLASS> or 1.
#
# State lives under DQ_SLOTS_DIR (default E:/dq-cache/slots, else ~/.cache/dq/slots), one directory per class:
#   slot.N/owner        a held slot (an atomic mkdir). key=value lines: pid, winpid, kind (bash|node), worktree, label,
#                       started. The file's mtime is the holder's heartbeat, touched every 15 s while it holds the slot.
#   queue/P-T-PID       a waiter. P is 0 for a compiler lane (or DQ_SLOT_PRIORITY=0) and 1 for everyone else, T the
#                       arrival time, so priority 0 jumps the queue and the rest go in arrival order. A waiter takes a slot only when it is first. Its mtime is refreshed on every poll.
#   events.tsv          one line per release: time, class, slot, worktree, label, waited seconds, held seconds.
#   <worktree>/data/slot-waits.log  the same line for that worktree's own releases, kept to its last 2000 lines.
# A holder or waiter is dead when its pid is gone (a bash pid is checked with kill -0, a node pid through its Windows
# pid), or when its heartbeat is older than DQ_SLOTS_STALE_SEC (default 600; this covers pid reuse and a frozen holder
# and the one case a pid cannot be checked cheaply). A dead slot is removed by the next waiter, so a crashed run never
# blocks the queue. The same protocol is implemented in tools/build/lib/machine_slots.ts for the build tool; keep the
# two in sync (the selftest and tools/build/lib/machine_slots.test.ts check they agree).
#
# Lane classes (tools/dq_lane_pool.sh): a compiler lane (worktree pool-c1/pool-c2, or DQ_LANE_CLASS=compiler) has first claim on every class
# above: priority 0, so it goes to the front of each queue and takes the next slot that frees up; and it
# may hold ONE slot beyond the cargo cap (DQ_SLOTS_COMPILER_EXTRA_CARGO, default 1) so a compiler build never waits for a game lane's
# cargo. A light lane (pool-light, or DQ_LANE_CLASS=light) never compiles DM or runs a test world: dm_compile and test_world refuse
# there with exit 64.
#
# Fair order and the suite cap: a queue is oldest first (priority 0, then arrival time), and a waiter takes a slot only at the head. A
# run that takes several test worlds as a group (a full `dm-test`, a many-world focused run) would otherwise hold both worlds for its
# whole run and starve every other lane's focused run, so a non-priority group takes at most DQ_SLOTS_SUITE_MAX_WORLDS worlds: unset
# means 1 when any other run is queued for a test world at the moment the group asks (else all it wants), a number N always caps it at
# N, 0 turns the cap off. Compiler lanes (priority 0) are exempt. The cap applies to new acquisitions only: a
# group already running keeps what it holds (nothing is preempted), and the shards past the cap take their own slot, in queue order,
# one by one (tools/build/lib/machine_slots.ts acquireSlotGroup; tools/dq_focused_test.sh hands slots on as worlds end).
# `dq_machine_slots.sh waiting <worktree>` lists the queue entries a worktree has (class, seconds waited): tools/dq_lane_pool.sh status
# uses it to show which pool slots sit idle while waiting for a machine slot.
#
# Waiting prints the class, your place in the queue and who holds the slots every 30 s. DQ_SLOT_PRIORITY=0 forces the
# front of the queue for any caller.

slots_dir() {
	if [ -n "${DQ_SLOTS_DIR:-}" ]; then
		echo "$DQ_SLOTS_DIR"
	elif [ -d /e/dq-cache ] || [ -d "E:/dq-cache" ]; then
		echo "E:/dq-cache/slots"
	else
		echo "${HOME:-/tmp}/.cache/dq/slots"
	fi
}

slots_cpus() { # logical CPUs of this machine (1 when unknown)
	local n
	n="${NUMBER_OF_PROCESSORS:-}"
	[ -n "$n" ] || n="$(nproc 2>/dev/null)"
	case "$n" in '' | *[!0-9]*) n=1 ;; esac
	[ "$n" -ge 1 ] || n=1
	echo "$n"
}

slots_default_test_world() { # 2 until peak RAM per world is measured; a full-suite run (DQ_SLOTS_SUITE=1) may hold all of the capacity, everyone else at most slots_role_cap's 2
	echo "${DQ_SLOTS_TEST_WORLD_DEFAULT:-2}"
}

slots_role_cap() { # class usable max -> what this caller may hold: test_world, with DQ_SLOTS_TEST_WORLD unset, is all of max for a full-suite run (DQ_SLOTS_SUITE=1, the merge reserve included) and at most DQ_SLOTS_TEST_WORLD_FOCUSED (2) for anyone else (the machine is also the user's desktop, 2026-10-19)
	local cls="$1" usable="$2" max="$3" focused="${DQ_SLOTS_TEST_WORLD_FOCUSED:-2}"
	if [ "$cls" != test_world ] || [ -n "${DQ_SLOTS_TEST_WORLD:-}" ]; then echo "$usable"; return; fi
	if [ "${DQ_SLOTS_SUITE:-}" = 1 ]; then echo "$max"; return; fi
	case "$focused" in '' | *[!0-9]*) focused=2 ;; esac
	[ "$focused" -ge 1 ] || focused=2
	if [ "$usable" -lt "$focused" ]; then echo "$usable"; else echo "$focused"; fi
}

slots_capacity() { # class -> count (0 = off)
	local cls="$1" up var val
	[ "${DQ_SLOTS:-1}" = "0" ] && { echo 0; return; }
	up="${cls^^}"
	var="DQ_SLOTS_$up"
	val="${!var:-}"
	if [ -z "$val" ]; then
		case "$cls" in
			dm_compile) val=1 ;;
			test_world) val="$(slots_default_test_world)" ;;
			cargo) val=1 ;;
			*) val=1 ;;
		esac
	fi
	case "$val" in '' | *[!0-9]*) val=1 ;; esac
	echo "$val"
}

# Slots kept free for priority 0 (compiler lanes): a priority 1 caller may hold only the first
# (max - reserve) slots of a class, so a compiler lane never queues behind a full house of lane runs. The reserve is
# DQ_SLOTS_MERGE_RESERVE (default 1 for test_world when the class has at least 3 slots, else 0; any class: DQ_SLOTS_MERGE_RESERVE_<CLASS>).
slots_usable() { # class max prio -> how many slots (counted from 1) this caller may take
	local cls="$1" max="$2" prio="$3" up var res
	[ "$prio" = "0" ] && { echo "$max"; return; }
	up="${cls^^}"
	var="DQ_SLOTS_MERGE_RESERVE_$up"
	res="${!var:-${DQ_SLOTS_MERGE_RESERVE:-}}"
	if [ -z "$res" ]; then
		if [ "$cls" = "test_world" ] && [ "$max" -ge 3 ]; then res=1; else res=0; fi
	fi
	case "$res" in '' | *[!0-9]*) res=0 ;; esac
	[ "$res" -le $((max - 1)) ] || res=$((max - 1))
	echo $((max - res))
}

slots_suite_cap() { # class prio: the most worlds a group of this class may take now (prints nothing for no cap); see "Fair order" above
	local cls="$1" prio="$2" v="${DQ_SLOTS_SUITE_MAX_WORLDS:-}" d q n=0
	[ "$cls" = "test_world" ] || return 0
	[ "$prio" = "0" ] && return 0
	case "$v" in '' | *[!0-9]*) v="" ;; esac
	if [ -n "$v" ]; then [ "$v" -ge 1 ] && echo "$v"; return 0; fi
	d="$(slots_dir)/$cls"
	for q in "$d"/queue/*; do
		[ -f "$q" ] || continue
		_slots_dead "$q" || n=$((n + 1))
	done
	[ "$n" -gt 0 ] && echo 1
	return 0
}

# Written with bash builtins only (lower case, / separators, /e/ to e:/, no trailing /): every exec of tr, sed, basename, head or cat costs a
# few hundred ms on a loaded Windows host, a command substitution of a function does not. _slots_norm_set sets NORM with no fork at all.
_slots_norm_set() {
	NORM="${1,,}"; NORM="${NORM//\\//}"
	[[ "$NORM" =~ ^/([a-z])/(.*)$ ]] && NORM="${BASH_REMATCH[1]}:/${BASH_REMATCH[2]}"
	while [[ "$NORM" == */ ]]; do NORM="${NORM%/}"; done
}
_slots_norm() { _slots_norm_set "$1"; printf '%s' "$NORM"; }

SLOTS_WT=""; SLOTS_WT_PWD=""
_slots_worktree_set() { # sets SLOTS_WT; the git start is paid once per directory (a call through $(...) cannot cache, so hot paths call this)
	if [ -n "${DQ_SLOT_WORKTREE:-}" ]; then SLOTS_WT="$DQ_SLOT_WORKTREE"; return 0; fi
	if [ -z "$SLOTS_WT" ] || [ "$SLOTS_WT_PWD" != "$PWD" ]; then
		SLOTS_WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; SLOTS_WT_PWD="$PWD"
	fi
}
_slots_worktree() { _slots_worktree_set; printf '%s\n' "$SLOTS_WT"; }

_slots_is_lane() { # <worktree> <compiler|light>: is this worktree a compiler / light lane slot (or declared one with DQ_LANE_CLASS)?
	[ "${DQ_LANE_CLASS:-}" = "$2" ] && return 0
	_slots_norm_set "$1"
	case "$2:${NORM##*/}" in compiler:pool-c[0-9]*|light:pool-light) return 0 ;; esac
	return 1
}

_slots_priority() { # worktree -> 0 (compiler lane, front of the queue) or 1
	if [ -n "${DQ_SLOT_PRIORITY:-}" ]; then echo "$DQ_SLOT_PRIORITY"; return; fi
	if _slots_is_lane "$1" compiler; then echo 0; else echo 1; fi
}

_slots_extra() { # class worktree -> slots beyond the cap this caller may hold (a compiler lane: one cargo slot)
	[ "$1" = cargo ] && _slots_is_lane "$2" compiler && { echo "${DQ_SLOTS_COMPILER_EXTRA_CARGO:-1}"; return; }
	echo 0
}

_slots_refuse_light() { # class worktree: a light lane never compiles DM or runs a test world
	case "$1" in dm_compile|test_world) ;; *) return 0 ;; esac
	_slots_is_lane "$2" light || return 0
	echo "REFUSED: $2 is a light lane: it never runs a DM compile or a test world ($1). Light lanes are for docs, tooling scripts and Rust/compiler-only changes; lease a general lane (tools/dq_lane_pool.sh lease <branch>) for work that needs the game build." >&2
	exit 64
}

_slots_winpid() { local w; if [ -r "/proc/$1/winpid" ] && read -r w <"/proc/$1/winpid" && [ -n "$w" ]; then echo "$w"; else echo "$1"; fi; }

_slots_field() { # file key: the first value of key (everything after "key=" on its line); no sed | head pipeline
	local k v
	[ -r "$1" ] || return 0
	while IFS='=' read -r k v || [ -n "$k" ]; do
		if [ "$k" = "$2" ]; then printf '%s\n' "$v"; return 0; fi
	done <"$1"
	return 0
}

_slots_num() { # file key default -> the key's value when it is a number, else the default (a file still being written has none)
	local v
	v="$(_slots_field "$1" "$2")"
	case "$v" in '' | *[!0-9]*) echo "$3" ;; *) echo "$v" ;; esac
}

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
	age=$(( EPOCHSECONDS - $(_slots_mtime "$f") ))
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

# A focused run (tools/dq_focused_test.sh) sets DQ_WORLD_REGISTRY: the first slot it holds starts the clock of its wall-clock cap
# (time queued for a slot is not run time). tools/dq_run_guard.js reads the file's mtime.
_slots_mark_running() {
	[ -n "${DQ_WORLD_REGISTRY:-}" ] || return 0
	[ -f "$DQ_WORLD_REGISTRY/.running" ] || { mkdir -p "$DQ_WORLD_REGISTRY" && date +%s >"$DQ_WORLD_REGISTRY/.running"; } 2>/dev/null || true
}

# While a run waits in a queue it holds DQ_WORLD_REGISTRY/.waiting.<pid> (epoch seconds): tools/dq_run_guard.js does not count that time against
# the run's wall-clock cap, so a gate that got its compile slot and then queued an hour behind a full suite for test worlds is not killed
# for the wait (it used to be: .running starts at the FIRST slot, and the test_world wait came after it).
_slots_mark_waiting() {
	[ -n "${DQ_WORLD_REGISTRY:-}" ] || return 0
	{ mkdir -p "$DQ_WORLD_REGISTRY" && date +%s >"$DQ_WORLD_REGISTRY/.waiting.$$"; } 2>/dev/null || true
}
_slots_clear_waiting() {
	[ -n "${DQ_WORLD_REGISTRY:-}" ] || return 0
	rm -f "$DQ_WORLD_REGISTRY/.waiting.$$" 2>/dev/null || true
}

SLOTS_SELF="${BASH_SOURCE[0]}"
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
		elif [ -f "$f/owner" ] && _slots_dead "$f/owner"; then # the owner file can vanish between the two tests (its holder released): a gone file is not a dead holder, and removing the directory would take a slot another waiter just made
			echo "== machine slots: reclaiming a dead slot ($f: $(_slots_field "$f/owner" worktree) pid $(_slots_field "$f/owner" pid) $(_slots_field "$f/owner" label))" >&2
			rm -rf "$f"
		fi
	done
}

_slots_who() { # class dir -> " [slot N: worktree 'label' held 3m] ..."
	local d="$1" f out="" now started
	now="$EPOCHSECONDS"
	for f in "$d"/slot.*; do
		[ -f "$f/owner" ] || continue
		started="$(_slots_field "$f/owner" started)"
		out="$out [${f##*/}: $(_slots_field "$f/owner" worktree) '$(_slots_field "$f/owner" label)' pid $(_slots_field "$f/owner" pid), held $(( now - ${started:-$now} ))s]"
	done
	echo "${out:- nobody}"
}

# A single-slot waiter goes when it heads the queue, or when everything ahead of it is a group (a multi-world run) that has not yet
# waited out its patience: one focused world must not wait 25 minutes behind a five-world request collecting slots. A group past its
# patience (DQ_SLOTS_GROUP_PATIENCE_SEC, default 120) blocks like any head again and then takes what is free, so groups are delayed,
# never starved.
_slots_single_may_go() { # dir name
	local d="$1" name="$2" q f now="$EPOCHSECONDS" queued grp k v
	for f in "$d"/queue/*; do   # the glob is sorted, as ls | sort was
		[ -e "$f" ] || continue
		q="${f##*/}"
		[ "$q" = "$name" ] && return 0
		grp=0; while IFS='=' read -r k v || [ -n "$k" ]; do [ "$k" = group ] && { grp=1; break; }; done <"$f" 2>/dev/null   # a "group=" line, as grep -q '^group=' found it
		[ "$grp" -eq 1 ] || return 1
		queued="$(_slots_field "$f" queued)"
		[ $(( now - ${queued:-$now} )) -lt "${DQ_SLOTS_GROUP_PATIENCE_SEC:-120}" ] || return 1
	done
	return 1
}

_slots_acquire() {
	local cls="${1:?class}" label="${2:-}" max root d top prio usable now name waited=0 last=0 i pos
	_slots_worktree_set
	_slots_refuse_light "$cls" "$SLOTS_WT"
	max="$(slots_capacity "$cls")"
	[ "$max" -gt 0 ] 2>/dev/null || return 0
	root="$(slots_dir)"
	d="$root/$cls"
	mkdir -p "$d/queue" 2>/dev/null || { echo "== machine slots: cannot create $d; running without a $cls limit" >&2; return 0; }
	top="$SLOTS_WT"
	prio="$(_slots_priority "$top")"
	usable="$(slots_usable "$cls" "$max" "$prio")"
	usable="$(slots_role_cap "$cls" "$usable" "$max")"
	usable=$((usable + $(_slots_extra "$cls" "$top")))
	now="$EPOCHSECONDS"
	printf -v name '%s-%013d-%s' "$prio" "$now" "$$"
	SLOTS_QUEUE="$d/queue/$name"
	printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nqueued=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$now" >"$SLOTS_QUEUE"
	SLOTS_T_QUEUED="$now"
	_slots_mark_waiting
	while true; do
		_slots_reap "$d"
		if _slots_single_may_go "$d" "$name"; then
			for ((i = 1; i <= usable; i++)); do
				if mkdir "$d/slot.$i" 2>/dev/null; then
					printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nstarted=%s\npriority=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$EPOCHSECONDS" "$prio" >"$d/slot.$i/owner"
					_slots_mark_running
					_slots_clear_waiting
					SLOTS_HELD="$d/slot.$i"
					SLOTS_HELD_CLASS="$cls"
					SLOTS_T_GOT="$EPOCHSECONDS"
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
			echo "== machine slots: $cls: waiting ${waited}s, place ${pos:-?} of $(ls "$d/queue" 2>/dev/null | wc -l) in the queue (at most $max at once on this machine; priority 0 goes first). Held by:$(_slots_who "$d")"
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

# One line per release goes to the machine log (events.tsv) and to the releasing worktree's data/slot-waits.log (time, class, slot,
# worktree, label = caller, queued seconds, held seconds), the latter cut to its last 2000 lines so it stays bounded.
_slots_event() { # reads one line on stdin
	local line wt log
	IFS= read -r line || return 0
	printf '%s
' "$line" >>"$(slots_dir)/events.tsv" 2>/dev/null
	_slots_worktree_set; wt="$SLOTS_WT"
	[ -d "$wt" ] || return 0
	mkdir -p "$wt/data" 2>/dev/null || return 0
	log="$wt/data/slot-waits.log"
	printf '%s
' "$line" >>"$log" 2>/dev/null
	if [ "$(wc -l <"$log" 2>/dev/null || echo 0)" -gt 2400 ]; then
		tail -n 2000 "$log" >"$log.tmp.$$" 2>/dev/null && mv -f "$log.tmp.$$" "$log" 2>/dev/null
	fi
	return 0
}

_slots_release() {
	local now owner worktree label started
	now="$EPOCHSECONDS"
	if [ -n "$SLOTS_HB_PID" ]; then kill "$SLOTS_HB_PID" 2>/dev/null; SLOTS_HB_PID=""; fi
	if [ -n "$SLOTS_HELD" ]; then
		owner="$SLOTS_HELD/owner"
		worktree="$(_slots_field "$owner" worktree)"
		label="$(_slots_field "$owner" label)"
		{ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$SLOTS_HELD_CLASS" "${SLOTS_HELD##*.}" "$worktree" "$label" "$((SLOTS_T_GOT - SLOTS_T_QUEUED))" "$((now - SLOTS_T_GOT))"; } | _slots_event
		rm -rf "$SLOTS_HELD"
		SLOTS_HELD=""
	fi
	if [ -n "$SLOTS_QUEUE" ]; then rm -f "$SLOTS_QUEUE"; SLOTS_QUEUE=""; fi
	_slots_clear_waiting
}

slots_release() {
	local rc
	_slots_errexit_off
	_slots_release
	rc=$?
	_slots_errexit_back
	return "$rc"
}

# ---- groups: several slots of one class taken together, for a run that launches several worlds -------------------------------
# A sharded run used to start N worlds that each queued for a slot of their own: the run held some slots while its other worlds
# waited, and two such runs could each hold part of the budget. A group is one queue entry: the head of the queue takes slots as
# they free up and starts nothing until it has all it asked for (at most the class capacity, so it can always be satisfied).
# Only the head of the queue ever holds a partial group, so two groups cannot deadlock each other. The worlds it then launches
# run with DQ_SLOTS_PREHELD=<class> (they do not queue again), and the run hands a slot back as each world exits.
SLOTS_GROUP_DIRS=()   # held slot directories ("" once released)
SLOTS_GROUP_CLASS=""
SLOTS_GROUP_T_QUEUED=0
SLOTS_GROUP_T_GOT=0
SLOTS_GROUP_HB=""

slots_group_size() { # class wanted -> how many slots a group of that wish gets (the wish, clamped to the capacity)
	local max
	max="$(slots_capacity "$1")"
	[ "$max" -gt 0 ] && max="$(slots_role_cap "$1" "$(slots_usable "$1" "$max" "$(_slots_priority "$(_slots_worktree)")")" "$max")"
	local cap
	cap="$(slots_suite_cap "$1" "$(_slots_priority "$(_slots_worktree)")")"
	if [ "$max" -gt 0 ] && [ -n "$cap" ] && [ "$cap" -lt "$max" ]; then max="$cap"; fi
	if [ "$max" -gt 0 ] && [ "$2" -gt "$max" ]; then echo "$max"; else echo "$2"; fi
}

slots_group_acquire() { # class n [label]: waits for n slots at once (n is clamped to the capacity); sets SLOTS_GROUP_DIRS
	local rc
	_slots_errexit_off
	_slots_group_acquire "$@"
	rc=$?
	_slots_errexit_back
	return "$rc"
}

_slots_group_acquire() {
	local cls="${1:?class}" want="${2:?n}" label="${3:-}" max usable root d top prio now name waited=0 last=0 i have=0 pos o
	local owners=() dirs=()
	SLOTS_GROUP_DIRS=()
	SLOTS_GROUP_CLASS="$cls"
	_slots_worktree_set
	_slots_refuse_light "$cls" "$SLOTS_WT"
	max="$(slots_capacity "$cls")"
	[ "$max" -gt 0 ] 2>/dev/null || return 0
	root="$(slots_dir)"
	d="$root/$cls"
	mkdir -p "$d/queue" 2>/dev/null || { echo "== machine slots: cannot create $d; running without a $cls limit" >&2; return 0; }
	top="$SLOTS_WT"
	prio="$(_slots_priority "$top")"
	usable="$(slots_usable "$cls" "$max" "$prio")"
	usable="$(slots_role_cap "$cls" "$usable" "$max")"
	usable=$((usable + $(_slots_extra "$cls" "$top")))
	[ "$want" -le "$usable" ] || want="$usable"
	now="$EPOCHSECONDS"
	printf -v name '%s-%013d-%s' "$prio" "$now" "$$"
	SLOTS_QUEUE="$d/queue/$name"
	printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nqueued=%s\ngroup=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$now" "$want" >"$SLOTS_QUEUE"
	SLOTS_GROUP_T_QUEUED="$now"
	_slots_mark_waiting
	local free take
	while true; do
		_slots_reap "$d"
		# The head takes slots only when it can take all it wants at once, or (past its patience) whatever is free, at least one: it does
		# not sit on a partial group while single worlds wait behind it. A smaller group starts its other worlds as its slots come back.
		free=0
		take=0
		for ((i = 1; i <= usable; i++)); do [ -d "$d/slot.$i" ] || free=$((free + 1)); done
		if [ "$have" -gt 0 ] || [ "$free" -ge "$want" ]; then take="$want"
		elif [ "$waited" -ge "${DQ_SLOTS_GROUP_PATIENCE_SEC:-120}" ] && [ "$free" -ge 1 ]; then take="$free"; fi
		if [ "$take" -gt 0 ] && [ "$(ls "$d/queue" 2>/dev/null | sort | head -n 1)" = "$name" ]; then
			[ "$take" -lt "$want" ] && want="$take"
			for ((i = 1; i <= usable && have < want; i++)); do
				if mkdir "$d/slot.$i" 2>/dev/null; then
					printf 'kind=bash\npid=%s\nwinpid=%s\nworktree=%s\nlabel=%s\nstarted=%s\npriority=%s\n' "$$" "$(_slots_winpid "$$")" "$top" "$label" "$EPOCHSECONDS" "$prio" >"$d/slot.$i/owner"
					_slots_mark_running
					dirs+=("$d/slot.$i")
					owners+=("$d/slot.$i/owner")
					have=$((have + 1))
				fi
			done
			if [ "$have" -ge "$want" ]; then
				SLOTS_GROUP_DIRS=("${dirs[@]}")
				_slots_clear_waiting
				SLOTS_GROUP_T_GOT="$EPOCHSECONDS"
				rm -f "$SLOTS_QUEUE"
				SLOTS_QUEUE=""
				# One heartbeat for the whole group; a released slot's owner file is gone and is skipped.
				(
					while kill -0 "$$" 2>/dev/null; do
						sleep "${DQ_SLOTS_HEARTBEAT_SEC:-15}"
						for o in "${owners[@]}"; do [ -f "$o" ] && touch "$o" 2>/dev/null; done
					done
				) >/dev/null 2>&1 &
				SLOTS_GROUP_HB=$!
				disown "$SLOTS_GROUP_HB" 2>/dev/null || true
				echo "== machine slots: $cls group of $want (of $max) after ${waited}s"
				return 0
			fi
		fi
		if [ "$waited" -eq 0 ] || [ $((waited - last)) -ge 30 ]; then
			last="$waited"
			pos="$(ls "$d/queue" 2>/dev/null | sort | grep -n -x -- "$name" | cut -d: -f1)"
			echo "== machine slots: $cls: waiting ${waited}s for a group of $want, holding $have, place ${pos:-?} of $(ls "$d/queue" 2>/dev/null | wc -l) in the queue (at most $max at once on this machine). Held by:$(_slots_who "$d")"
		fi
		touch "$SLOTS_QUEUE" 2>/dev/null
		sleep "${DQ_SLOTS_POLL_SEC:-3}"
		waited=$((waited + ${DQ_SLOTS_POLL_SEC:-3}))
	done
}

slots_group_release_one() { # hand back one slot of the group; the last one stops the heartbeat
	local i left=0 dir="" now owner
	_slots_errexit_off
	now="$EPOCHSECONDS"
	for i in "${!SLOTS_GROUP_DIRS[@]}"; do
		if [ -n "${SLOTS_GROUP_DIRS[$i]}" ]; then
			if [ -z "$dir" ]; then dir="${SLOTS_GROUP_DIRS[$i]}"; SLOTS_GROUP_DIRS[$i]=""; else left=$((left + 1)); fi
		fi
	done
	if [ -n "$dir" ]; then
		owner="$dir/owner"
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$SLOTS_GROUP_CLASS" "${dir##*.}" "$(_slots_field "$owner" worktree)" "$(_slots_field "$owner" label)" "$((SLOTS_GROUP_T_GOT - SLOTS_GROUP_T_QUEUED))" "$((now - SLOTS_GROUP_T_GOT))" | _slots_event
		rm -rf "$dir"
	fi
	if [ "$left" -eq 0 ] && [ -n "$SLOTS_GROUP_HB" ]; then kill "$SLOTS_GROUP_HB" 2>/dev/null; SLOTS_GROUP_HB=""; fi
	_slots_errexit_back
	return 0
}

slots_group_release() { # hand back all of them (an EXIT trap calls this), and leave the queue
	local i
	for i in "${!SLOTS_GROUP_DIRS[@]}"; do slots_group_release_one; done
	if [ -n "$SLOTS_QUEUE" ]; then rm -f "$SLOTS_QUEUE"; SLOTS_QUEUE=""; fi
	_slots_clear_waiting
	if [ -n "$SLOTS_GROUP_HB" ]; then kill "$SLOTS_GROUP_HB" 2>/dev/null; SLOTS_GROUP_HB=""; fi
	return 0
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
	slots_acquire "$cls" "${label:0:80}" || { rc=$?; slots_release; return "$rc"; }
	"$@"
	rc=$?
	slots_release
	trap - EXIT INT TERM
	return "$rc"
}

slots_status() { # [class]
	local root cls d f any=0 now max
	root="$(slots_dir)"
	now="$EPOCHSECONDS"
	for cls in ${1:-dm_compile test_world cargo}; do
		d="$root/$cls"
		max="$(slots_capacity "$cls")"
		echo "$cls: at most $max at once$( [ "$max" -eq 0 ] && echo ' (limit off)')"
		for f in "$d"/slot.*; do
			[ -f "$f/owner" ] || continue
			any=1
			echo "  ${f##*/}: $(_slots_field "$f/owner" worktree) '$(_slots_field "$f/owner" label)' pid $(_slots_field "$f/owner" pid), held $(( now - $(_slots_num "$f/owner" started "$now") ))s, heartbeat $(( now - $(_slots_mtime "$f/owner") ))s ago$(_slots_dead "$f/owner" && echo ' [DEAD, reclaimed by the next waiter]')"
		done
		for f in "$d"/queue/*; do
			[ -f "$f" ] || continue
			any=1
			echo "  waiting ${f##*/}: $(_slots_field "$f" worktree) '$(_slots_field "$f" label)' pid $(_slots_field "$f" pid), queued $(( now - $(_slots_num "$f" queued "$now") ))s$(_slots_dead "$f" && echo ' [DEAD]')"
		done
	done
	[ "$any" -eq 1 ] || echo "(nothing held, nobody waiting)"
}

slots_waiting() { # worktree: one line per live queue entry of that worktree in dm_compile / test_world: "<class> <seconds waited> <label>"
	local want f cls now
	want="$(_slots_norm "${1:?worktree}")"
	now="$EPOCHSECONDS"
	for cls in dm_compile test_world; do
		for f in "$(slots_dir)/$cls"/queue/*; do
			[ -f "$f" ] || continue
			_slots_dead "$f" && continue
			[ "$(_slots_norm "$(_slots_field "$f" worktree)")" = "$want" ] || continue
			echo "$cls $(( now - $(_slots_num "$f" queued "$now") )) $(_slots_field "$f" label)"
		done
	done
	return 0
}

slots_holding() { # worktree: one line per live slot that worktree holds in any class: "<class> <seconds held> <label>"
	local want f cls now
	want="$(_slots_norm "${1:?worktree}")"
	now="$EPOCHSECONDS"
	for cls in dm_compile test_world cargo; do
		for f in "$(slots_dir)/$cls"/slot.*; do
			[ -f "$f/owner" ] || continue
			_slots_dead "$f/owner" && continue
			[ "$(_slots_norm "$(_slots_field "$f/owner" worktree)")" = "$want" ] || continue
			echo "$cls $(( now - $(_slots_num "$f/owner" started "$now") )) $(_slots_field "$f/owner" label)"
		done
	done
	return 0
}

slots_usage_all() { # every fresh holder and waiter, one line each: "<hold|wait> <worktree, lower case, / separators> <class> <seconds> <label>"
	# Cheap on purpose (the pool's status calls it once, on a host where a fork costs a few hundred ms): one find lists every fresh file, no stat
	# or per-field subprocess; a file counts while its heartbeat/poll touch is younger than DQ_SLOTS_FRESH_SEC (default 90; holders touch every
	# 15 s, waiters every poll).
	local cls f rest kind k v wt label t now sd fresh="${DQ_SLOTS_FRESH_SEC:-90}"
	now="$EPOCHSECONDS"; sd="$(slots_dir)"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		rest="${f#"$sd"/}"; cls="${rest%%/*}"
		wt=""; label=""; t=""
		while IFS='=' read -r k v; do
			case "$k" in worktree) wt="$v" ;; label) label="$v" ;; started | queued) t="$v" ;; esac
		done <"$f"
		case "$f" in */owner) kind=hold ;; *) kind=wait ;; esac
		wt="${wt//\\//}"; wt="${wt,,}"; wt="${wt%/}"
		echo "$kind $wt $cls $(( now - ${t:-$now} )) $label"
	done < <(find "$sd/dm_compile" "$sd/test_world" "$sd/cargo" -maxdepth 3 -type f \( -name owner -path '*/slot.*' -o -path '*/queue/*' \) -newermt "@$(( now - fresh ))" 2>/dev/null)
}

slots_stats() { # [N]
	local f
	f="$(slots_dir)/events.tsv"
	[ -f "$f" ] || { echo "no events yet ($f)"; return 0; }
	echo "time	class	slot	worktree	label	waited_s	held_s"
	tail -n "${1:-20}" "$f"
	awk -F'\t' '{ w[$2] += $6; h[$2] += $7; n[$2]++; if ($6 > m[$2]) m[$2] = $6 } END { for (c in n) printf "%s: %d runs, mean wait %.0fs, max wait %ds, mean hold %.0fs\n", c, n[c], w[c] / n[c], m[c], h[c] / n[c] }' "$f"
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
	# 4. env counts.
	[ "$(DQ_SLOTS_DM_COMPILE=5 slots_capacity dm_compile)" = 5 ] && [ "$(unset DQ_SLOTS_CARGO; slots_capacity cargo)" = 1 ] || { echo "FAIL: capacity env"; ok=0; }
	# 4b. the merge reserve: with 3 test_world slots a lane caller may use 2, a priority 0 caller all 3, and a class below 3 reserves nothing.
	[ "$(DQ_SLOTS_TEST_WORLD=3 DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 2 ] && [ "$(DQ_SLOTS_TEST_WORLD=3 DQ_SLOT_PRIORITY=0 slots_group_size test_world 9)" = 3 ] 		&& [ "$(slots_usable test_world 2 1)" = 2 ] && [ "$(DQ_SLOTS_MERGE_RESERVE=9 slots_usable test_world 3 1)" = 1 ] && [ "$(slots_usable dm_compile 2 1)" = 2 ] 		|| { echo "FAIL: merge reserve"; ok=0; }
	# 5. a group is clamped to the capacity and starts only when it has all its slots; two groups never run each on part of the budget.
	export DQ_SLOTS_TEST_WORLD=3 DQ_SLOTS_MERGE_RESERVE=0
	[ "$(slots_group_size test_world 9)" = 3 ] && [ "$(slots_group_size test_world 2)" = 2 ] || { echo "FAIL: group size clamp"; ok=0; }
	bash -c 'source "$0"; slots_group_acquire test_world 2 g1 >/dev/null; sleep 6; slots_group_release' "$self" & p1=$!
	sleep 2
	bash -c 'source "$0"; slots_group_acquire test_world 2 g2 >"$1"; echo started >>"$1"; slots_group_release' "$self" "$tmp/g2.log" & p2=$!
	sleep 2
	grep -q started "$tmp/g2.log" 2>/dev/null && { echo "FAIL: group g2 started on part of the budget while g1 held 2 of 3"; ok=0; }
	wait "$p1" "$p2"
	grep -q "group of 2" "$tmp/g2.log" && grep -q started "$tmp/g2.log" || { echo "FAIL: group g2 never got its slots"; ok=0; }
	[ -z "$(ls "$tmp/test_world" | grep '^slot')" ] || { echo "FAIL: a group left slots behind"; ok=0; }
	unset DQ_SLOTS_TEST_WORLD DQ_SLOTS_MERGE_RESERVE
	# 5b. roles: the default capacity is 2; with DQ_SLOTS_TEST_WORLD_DEFAULT=4 a focused caller holds 2 of them, a full-suite run (DQ_SLOTS_SUITE=1) all 4, merge reserve or not;
	# setting DQ_SLOTS_TEST_WORLD is one limit for everyone.
	[ "$(slots_capacity test_world)" = 2 ] && [ "$(DQ_SLOTS_TEST_WORLD_DEFAULT=4 slots_capacity test_world)" = 4 ] && [ "$(DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 2 ] 		&& [ "$(DQ_SLOTS_TEST_WORLD_DEFAULT=4 DQ_SLOTS_SUITE=1 DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 4 ] && [ "$(DQ_SLOTS_TEST_WORLD_DEFAULT=4 DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 2 ] 		&& [ "$(DQ_SLOTS_TEST_WORLD_DEFAULT=4 DQ_SLOTS_TEST_WORLD_FOCUSED=3 DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 3 ] && [ "$(DQ_SLOTS_SUITE=1 slots_group_size cargo 9)" = 1 ] 		&& [ "$(DQ_SLOTS_TEST_WORLD=3 DQ_SLOTS_SUITE=1 DQ_SLOT_PRIORITY=1 slots_group_size test_world 9)" = 2 ] 		|| { echo "FAIL: test_world roles (focused 2, suite 4)"; ok=0; }
	# 6. the suite cap: a non-priority group is capped at DQ_SLOTS_SUITE_MAX_WORLDS (default 1 only while another run is queued); priority 0 is exempt.
	export DQ_SLOTS_MERGE_RESERVE=0 DQ_SLOTS_TEST_WORLD=2
	[ "$(DQ_SLOT_PRIORITY=1 slots_group_size test_world 2)" = 2 ] || { echo "FAIL: no cap while nobody waits"; ok=0; }
	[ "$(DQ_SLOTS_SUITE_MAX_WORLDS=1 DQ_SLOT_PRIORITY=1 slots_group_size test_world 2)" = 1 ] && [ "$(DQ_SLOTS_SUITE_MAX_WORLDS=1 DQ_SLOT_PRIORITY=0 slots_group_size test_world 2)" = 2 ] \
		&& [ "$(DQ_SLOTS_SUITE_MAX_WORLDS=0 DQ_SLOT_PRIORITY=1 slots_group_size test_world 2)" = 2 ] || { echo "FAIL: explicit suite cap"; ok=0; }
	mkdir -p "$tmp/test_world/queue"
	printf 'kind=bash\npid=%s\nworktree=/x/other\nlabel=focused\nqueued=%s\n' "$$" "$(date +%s)" >"$tmp/test_world/queue/1-$(printf '%013d' "$(date +%s)")-$$"
	[ "$(DQ_SLOT_PRIORITY=1 slots_group_size test_world 2)" = 1 ] || { echo "FAIL: default suite cap is 1 while another run waits"; ok=0; }
	out="$(slots_waiting /x/other)"
	case "$out" in "test_world "[0-9]*" focused") ;; *) echo "FAIL: waiting should list the queued entry: '$out'"; ok=0 ;; esac
	[ -z "$(slots_waiting /x/nobody)" ] || { echo "FAIL: waiting lists another worktree's entry"; ok=0; }
	rm -rf "$tmp/test_world"
	unset DQ_SLOTS_TEST_WORLD DQ_SLOTS_MERGE_RESERVE
	rm -rf "$tmp"
	# lane classes: a compiler worktree is priority 0 with one extra cargo slot; a light worktree is refused a compile or test world
	[ "$(_slots_priority /x/pool-c2)" = 0 ] && [ "$(_slots_priority /x/pool-3)" = 1 ] && [ "$(_slots_extra cargo /x/pool-c1)" = 1 ] && [ "$(_slots_extra cargo /x/pool-3)" = 0 ] && [ "$(_slots_extra dm_compile /x/pool-c1)" = 0 ] 		|| { echo "FAIL: compiler lane priority / extra cargo slot"; ok=0; }
	( DQ_SLOT_WORKTREE=/x/pool-light bash "$0" run test_world --label light -- true ) >/dev/null 2>&1; [ $? -eq 64 ] || { echo "FAIL: a light lane must be refused a test world (exit 64)"; ok=0; }
	( DQ_SLOT_WORKTREE=/x/pool-light bash "$0" run cargo --label light -- true ) >/dev/null 2>&1 || { echo "FAIL: a light lane may take a cargo slot"; ok=0; }
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
		waiting) slots_waiting "$@" ;;
		holding) slots_holding "$@" ;;
		usage-all) slots_usage_all ;;
		usage) slots_holding "$@" | sed 's/^/hold /'; slots_waiting "$@" | sed 's/^/wait /' ;;   # both in one process: the pool calls this once per leased slot
		reap) for c in dm_compile test_world cargo; do _slots_reap "$(slots_dir)/$c"; done; slots_status ;;
		selftest) slots_selftest; exit $? ;;
		*) sed -n '2,12p' "$0"; [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ] || exit 2 ;;
	esac
fi
