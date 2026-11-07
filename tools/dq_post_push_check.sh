#!/usr/bin/env bash
# Report-only health of master: boots the newest origin/master after a landing (about 3 minutes, one test-world slot). It never blocks or delays a landing.
#
#   bash tools/dq_post_push_check.sh start     # returns at once; tools/dq_land.sh calls it after every push
#   bash tools/dq_post_push_check.sh status    # the verdict
#
# A burst of pushes checks only the newest master: one runner at a time, which looks again when it finishes. No check starts under DQ_HEALTH_MIN_FREE_GB (16) free RAM.
# State under E:/dq-cache/health (DQ_HEALTH_STATE): verdict.txt (status=pass|FAIL|unknown, sha, last_good, range, log, time), history.tsv, and MASTER_BROKEN.txt, present
# only while master fails, naming the first bad range. dq_land.sh prints it on every landing. An infrastructure failure (no result) is status=unknown, never MASTER_BROKEN.
set -uo pipefail
# Below normal priority, for this script and everything it starts (cargo and rustc, the analyzer, git): the machine is also the user's desktop.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dq_below_normal.sh"
# Everything is in functions and main runs on the last line: bash has read the whole file before the checkout may change under it.
export DQ_NATIVE_NO_DAEMON=1 DMB_DAEMON_AUTOSTART=0
STATE="${DQ_HEALTH_STATE:-E:/dq-cache/health}"
WT="${DQ_HEALTH_WT:-E:/projects/dq-wt/health}"
MIN_GB="${DQ_HEALTH_MIN_FREE_GB:-16}"
LOCK="$STATE/run.lock"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
free_gb() { awk '/^MemAvailable:/ {a=$2} /^MemFree:/ {f=$2} END {print int((a ? a : f) / 1048576)}' /proc/meminfo 2>/dev/null || echo 999; }
field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1; }

take_lock() {
	mkdir -p "$STATE"
	if ! mkdir "$LOCK" 2>/dev/null; then
		local p; p="$(cat "$LOCK/pid" 2>/dev/null)"
		if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then return 1; fi
		[ -z "$p" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin -1 2>/dev/null)" ] && return 1
		rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null
		mkdir "$LOCK" 2>/dev/null || return 1
	fi
	echo "$$" >"$LOCK/pid"
	trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' EXIT
}

ensure_wt() {
	[ -e "$WT/.git" ] && return 0
	git -C "$REPO" worktree add -q --detach "$WT" origin/master
}

# Tracked files a build regenerates (gen_dme.py, gen_mapping_dme.py). A boot that rewrites one (a master whose committed manifest is stale)
# leaves the private worktree dirty and the next `git switch --detach` would abort ("local changes would be overwritten"), wedging the
# checker at status=unknown. Before every switch, settle() puts HEAD's content back in these files and in the index (a hand-staged copy
# too). They are build output in the checker's own worktree, never anyone's work. Any other local change is left alone; the switch reports it.
GENERATED="deepquarry.dme deepquarry.mapping.dme maps/~mapping/variant_stubs.dm"
settle() { # <worktree>
	local f blob
	for f in $GENERATED; do
		blob="$(git -C "$1" rev-parse -q --verify "HEAD:$f" 2>/dev/null)" || continue
		git -C "$1" diff --quiet HEAD -- "$f" 2>/dev/null && continue
		echo "dq_post_push_check: settling regenerated $f to HEAD's content before switching"
		git -C "$1" cat-file blob "$blob" >"$1/$f" || return 1
		git -C "$1" update-index -q --cacheinfo "100644,$blob,$f" || return 1
		git -C "$1" update-index -q --refresh >/dev/null 2>&1
	done
	return 0
}

# One boot of <sha>. Prints pass, FAIL or unknown; the log is $STATE/last.log.
boot() {
	local sha="$1" out
	if [ -n "${DQ_HEALTH_CMD:-}" ]; then
		$DQ_HEALTH_CMD "$sha" >"$STATE/last.log" 2>&1
	else
		( cd "$WT" && settle "$WT" && git switch -q --detach "$sha" && bash tools/dq_focused_test.sh --force --boot ) >"$STATE/last.log" 2>&1
	fi
	out="$(sed -n 's/^FOCUSED RESULT: //p' "$STATE/last.log" | tail -n 1)"
	case "$out" in
		*"[exit "*|*"not clean"*) echo FAIL ;; # rc != 0 with 0 failed: the boot gate, watchdog or a crash
		*" passed, 0 failed"*) echo pass ;;
		*" failed"*) case "$out" in *"no results"*) echo unknown ;; *) echo FAIL ;; esac ;;
		*) echo unknown ;;
	esac
}

record() { # <status> <sha>
	local status="$1" sha="$2" good range log
	good="$(field "$STATE/verdict.txt" last_good)"
	log="$STATE/log-${sha:0:12}.log"; cp -f "$STATE/last.log" "$log" 2>/dev/null
	range=""
	[ "$status" = pass ] && good="$sha"
	if [ "$status" = FAIL ]; then range="${good:-unknown}..$sha"; fi
	printf 'status=%s\nsha=%s\nlast_good=%s\nrange=%s\nlog=%s\ntime=%s\n' "$status" "$sha" "$good" "$range" "$log" "$(now)" >"$STATE/verdict.tmp" && mv -f "$STATE/verdict.tmp" "$STATE/verdict.txt"
	printf '%s\t%s\t%s\t%s\n' "$(now)" "$status" "$sha" "$range" >>"$STATE/history.tsv"
	case "$status" in
		FAIL) printf 'MASTER DOES NOT BOOT at %s (first bad range %s), checked %s.\nLog: %s\n%s\n' "$sha" "$range" "$(now)" "$log" "$(grep -m3 -E 'FAILED|error|Boot was not clean' "$log" | cut -c1-200)" >"$STATE/MASTER_BROKEN.txt" ;;
		pass) rm -f "$STATE/MASTER_BROKEN.txt" ;;
	esac
}

run() {
	take_lock || exit 0
	while :; do
		git -C "$REPO" fetch -q origin || exit 0
		local sha; sha="$(git -C "$REPO" rev-parse origin/master)"
		[ "$sha" != "$(field "$STATE/verdict.txt" sha)" ] || exit 0
		local waited=0
		while [ "$(free_gb)" -lt "$MIN_GB" ]; do
			waited=$((waited + 1)); [ "$waited" -le "${DQ_HEALTH_RAM_WAITS:-60}" ] || exit 0 # the next landing starts it again
			sleep "${DQ_HEALTH_POLL:-60}"
		done
		sha="$(git -C "$REPO" fetch -q origin; git -C "$REPO" rev-parse origin/master)" # the newest, after any wait
		[ -n "${DQ_HEALTH_CMD:-}" ] || ensure_wt || exit 0
		record "$(boot "$sha")" "$sha"
	done
}

main() {
	REPO="${DQ_HEALTH_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
	# the health worktree outlives the lane that started the runner: a released or removed lane must not end its loop
	[ -n "${DQ_HEALTH_REPO:-}" ] || [ ! -e "$WT/.git" ] || REPO="$WT"
	case "${1:-status}" in
		start)
			mkdir -p "$STATE"
			( nohup bash "$0" run >>"$STATE/runner.log" 2>&1 </dev/null & ) >/dev/null 2>&1
			;;
		run) run ;;
		settle) settle "${2:?settle <worktree>}" ;; # the self-test calls it
		status)
			[ ! -f "$STATE/MASTER_BROKEN.txt" ] || cat "$STATE/MASTER_BROKEN.txt"
			cat "$STATE/verdict.txt" 2>/dev/null || echo "no check has run yet"
			;;
		*) sed -n '2,10p' "$0"; exit 2 ;;
	esac
}
main "$@"
