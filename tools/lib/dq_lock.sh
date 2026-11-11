# shellcheck shell=bash
# One lock protocol for the dq_* scripts (sourced; defines functions only, sets no shell options).
#
# A lock is a directory taken with an atomic mkdir. Its holder is recorded beside it, in "<dir>.owner" (key=value lines):
#   pid=<MSYS/Linux pid>  winpid=<Windows pid, when there is one>  start=<the process's start time from /proc/<pid>/stat, an opaque token>
# The owner file sits BESIDE the directory, not in it, so a script that still frees the lock with a bare `rmdir` (an older copy running in
# another worktree) keeps working.
#
# Staleness: a lock is broken only when its recorded holder is dead: its pid is gone, or its pid is alive but its start time differs (the
# pid was reused). A lock with no owner record (an older script took it, or its taker died between the mkdir and the write) is broken once
# the directory is older than the caller's grace. A breaker holds "<dir>.break" while it re-checks and removes, so two waiters never both
# break, and neither removes a lock someone took after the check. A holder whose section is long touches the directory (dq_lock_keepalive),
# so an older script's mtime rule never breaks it either.
#
# The same protocol, with a heartbeat for holders whose identity a reader cannot verify, is used by the machine slots
# (tools/dq_machine_slots.sh, tools/build/lib/machine_slots.ts): see dq_owner_alive.
#
# Functions:
#   dq_proc_start <pid>            sets DQ_START to the process's start token ("" when the platform has no /proc)
#   dq_owner_fields                prints the pid=/winpid=/start= lines for this shell ($$)
#   dq_owner_alive <file>          0 alive, 1 dead, 2 no pid recorded (the caller decides by age)
#   dq_lock_take <dir> <timeout_s> <grace_s>   0 taken, 1 timed out (timeout 0: one try)
#   dq_lock_drop <dir>             frees the lock if this shell holds it
#   dq_lock_keepalive <dir>        starts a background loop that touches the lock every 30 s while this shell lives; sets DQ_LOCK_KA_PID
#   dq_lock_keepalive_stop

dq_proc_start() { # <pid>: field 22 of /proc/<pid>/stat (start time in ticks since boot); the comm field may hold spaces, so cut after ')'
	DQ_START=""
	local s
	[ -r "/proc/$1/stat" ] || return 0
	read -r s <"/proc/$1/stat" 2>/dev/null || return 0
	s="${s##*) }"
	# after "comm) " the fields are 3..: state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime cutime cstime priority nice threads itreal starttime
	set -- $s
	[ "$#" -ge 20 ] && DQ_START="${20}"
	return 0
}

dq_owner_fields() {
	local w=""
	[ -r "/proc/$$/winpid" ] && read -r w <"/proc/$$/winpid" 2>/dev/null
	dq_proc_start "$$"
	printf 'pid=%s\nwinpid=%s\nstart=%s\n' "$$" "${w:-$$}" "$DQ_START"
}

dq_owner_alive() { # <file>
	local k v pid="" start=""
	[ -f "$1" ] || return 2
	while IFS='=' read -r k v; do
		case "$k" in pid) [ -z "$pid" ] && pid="$v" ;; start) [ -z "$start" ] && start="$v" ;; esac
	done <"$1" 2>/dev/null
	[ -n "$pid" ] || return 2
	kill -0 "$pid" 2>/dev/null || return 1
	if [ -n "$start" ]; then
		dq_proc_start "$pid"
		[ -n "$DQ_START" ] && [ "$DQ_START" != "$start" ] && return 1   # the pid was reused by a later process
	fi
	return 0
}

_dq_lock_age() { # <path>: sets DQ_AGE (seconds since mtime; 0 when absent)
	local m
	m="$(stat -c %Y "$1" 2>/dev/null)" || m=""
	if [ -z "$m" ]; then DQ_AGE=0; else DQ_AGE=$(( ${EPOCHSECONDS:-$(date +%s)} - m )); fi
}

_dq_lock_is_stale() { # <dir> <grace_s>
	local rc
	dq_owner_alive "$1.owner"; rc=$?
	case "$rc" in
		0) return 1 ;;
		1) return 0 ;;
	esac
	_dq_lock_age "$1"
	[ "$DQ_AGE" -gt "$2" ]
}

_dq_lock_break() { # <dir> <grace_s>: removes a stale lock under <dir>.break; the break lock itself is stale after 10 s
	if ! mkdir "$1.break" 2>/dev/null; then
		_dq_lock_age "$1.break"; [ "$DQ_AGE" -gt 10 ] && rmdir "$1.break" 2>/dev/null
		return 0
	fi
	if [ -d "$1" ] && _dq_lock_is_stale "$1" "$2"; then
		echo "dq_lock: breaking a stale lock $1 ($(tr '\n' ' ' <"$1.owner" 2>/dev/null || echo 'no owner record'))" >&2
		rm -f "$1.owner"; rmdir "$1" 2>/dev/null
	fi
	rmdir "$1.break" 2>/dev/null
	return 0
}

dq_lock_take() { # <dir> <timeout_s> <grace_s>
	local dir="$1" timeout="${2:-60}" grace="${3:-120}" n=0 max
	max=$(( timeout * 10 ))
	while ! mkdir "$dir" 2>/dev/null; do
		[ -d "$dir" ] && _dq_lock_is_stale "$dir" "$grace" && { _dq_lock_break "$dir" "$grace"; continue; }
		n=$((n + 1)); [ "$n" -le "$max" ] || return 1
		sleep 0.1
	done
	dq_owner_fields >"$dir.owner"
	return 0
}

dq_lock_drop() { # <dir>
	local k v pid=""
	if [ -f "$1.owner" ]; then
		while IFS='=' read -r k v; do [ "$k" = pid ] && { pid="$v"; break; }; done <"$1.owner" 2>/dev/null
		[ -n "$pid" ] && [ "$pid" != "$$" ] && return 0   # someone else's lock (ours was broken and retaken): leave it
		rm -f "$1.owner"
	fi
	rmdir "$1" 2>/dev/null
	return 0
}

dq_lock_keepalive() { # <dir>
	local parent="$$"
	( while kill -0 "$parent" 2>/dev/null && [ -d "$1" ]; do touch "$1" 2>/dev/null; sleep 30; done ) >/dev/null 2>&1 &
	DQ_LOCK_KA_PID=$!
}
dq_lock_keepalive_stop() { [ -n "${DQ_LOCK_KA_PID:-}" ] && kill "$DQ_LOCK_KA_PID" 2>/dev/null; DQ_LOCK_KA_PID=""; return 0; }
