#!/usr/bin/env bash
# Self-test of tools/dq_lane_pool.sh in scratch repositories (no network, no DM, no daemon). The fixture remote is a local bare repository and the
# pool runs with DQ_LANE_POOL_NO_FETCH=1 (a fetch per pool call was most of the run time); the test pushes to the remote itself.
#
#   bash tools/ci/test_lane_pool.sh      # prints PASS/FAIL per case, exit 1 on any failure
#
# Cases: lease creates pool-1 and a branch on origin/master; a second lane gets pool-2; a third is refused (exit 3, "POOL FULL");
# leasing a held branch returns its slot; release refuses a dirty tree; release keeps icons/gen, data/analyze-cache and node_modules,
# deletes build outputs, detaches at origin/master and keeps an unmerged branch; a finished (merged) lane is reclaimed by the next
# lease; a dirty free slot is skipped, not cleaned; waiters queue, sort by class and cancel; stuck leases are reported; the suite cap.
#
# Speed: a process start costs a few hundred ms on a loaded Windows host, so the cases are split into independent sections, each with its own
# scratch repository, pool and state, and the sections run in parallel (their output is printed in order). Inside a section, assertions use bash
# builtins ([[ ]], read) instead of grep/$(...) wherever they check text or a ref the test can read itself, and a case that waits for a
# background waiter polls for the state it needs instead of sleeping a fixed time.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" 2>/dev/null' EXIT

# ---- helpers shared by the sections (each section runs in its own subshell, so its counters and environment are its own) ------------------
fail=0
ok() { echo "PASS: $1 [${SECONDS}s]"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
waitfor() { # <seconds> <condition>: polls the condition (every 0.3 s) until it holds or the time is up; the caller asserts the outcome
	local n=$(( $1 * 3 ))
	while [ "$n" -gt 0 ]; do eval "$2" && return 0; sleep 0.3; n=$((n - 1)); done
	return 1
}
fx() { # <section> <pool size>: a scratch origin + repo + pool for one section; sets b, g(), pool() and the DQ_LANE_POOL_* environment
	b="$tmp/$1"; mkdir -p "$b"
	git init -q --bare -b master "$b/origin.git"
	git clone -q "$b/origin.git" "$b/repo" 2>/dev/null
	[ -d "$b/repo/.git" ] || { echo "FAIL: fixture repository for section $1 was not created"; exit 1; }   # never fall through to the enclosing checkout
	mkdir -p "$b/repo/tools"
	printf '[user]\n\temail = t@t\n\tname = t\n' >>"$b/repo/.git/config"
	cp "$here/tools/dq_lane_pool.sh" "$here/tools/dq_git_safe.sh" "$b/repo/tools/"
	printf 'deepquarry.dmb\ndeepquarry.rsc\n/data/**/*\n/data\nicons/gen/\nnode_modules\n' >"$b/repo/.gitignore"
	echo a >"$b/repo/a.txt"; echo m >"$b/repo/deepquarry.dme"
	git -C "$b/repo" add -A && git -C "$b/repo" commit -q -m init && git -C "$b/repo" push -q origin master 2>/dev/null
	export DQ_LANE_POOL_DIR="$b/pool" DQ_LANE_POOL_STATE="$b/state" DQ_LANE_POOL_SIZE="$2" DQ_LANE_POOL_REPO="$b/repo" DQ_DMBC_DAEMON_DIR="$b/none"
	export DQ_LANE_POOL_NO_UPDATE=1
	export DQ_LANE_POOL_NO_FETCH=1   # tests only: no git fetch per pool call, origin is the local bare repository above
	export DQ_LANE_POOL_PROCS_CMD="echo no processes"   # never spawn powershell (seconds per call) in the fixtures
}
g() { git -C "$b/repo" "$@"; }
poolx() { bash "$b/repo/tools/dq_lane_pool.sh" "$@"; }   # a real process, as the lanes run it: waiters (their ticket carries the process id) and the entry-point check
pool() { # the same script, run in a forked subshell instead of a new bash (a bash start costs 0.1 to 0.5 s on this host): exit, traps and the environment stay the subshell's
	if [ "${DQ_TEST_POOL_EXEC:-}" = 1 ]; then bash "$b/repo/tools/dq_lane_pool.sh" "$@"; else ( . "$b/repo/tools/dq_lane_pool.sh" "$@" ); fi
}
master_sha() { read -r MS <"$b/origin.git/refs/heads/master"; }   # origin's master tip, read from the loose ref the test itself pushed
wt_head() { # <worktree>: sets WB (branch, empty when detached) and WS (the commit HEAD points at), reading the files git keeps
	local k v gd="$1/.git" h r
	if [ -f "$gd" ]; then read -r k v <"$gd"; gd="$v"; fi
	read -r h <"$gd/HEAD"
	if [[ "$h" == "ref: "* ]]; then
		r="${h#ref: }"; WB="${r#refs/heads/}"
		if [ -f "$gd/$r" ]; then read -r WS <"$gd/$r"; elif [ -f "${gd%/worktrees/*}/$r" ]; then read -r WS <"${gd%/worktrees/*}/$r"; else WS="$(git -C "$1" rev-parse HEAD)"; fi
	else WB=""; WS="$h"; fi
}

# ---- section 1: leasing ---------------------------------------------------------------------------------------------------------------
sec_lease() {
	fx lease 2
	master_sha
	p1="$(pool lease lane/a 2>/dev/null)"; wt_head "$p1"
	check "lease 1 creates pool-1 on a new branch at origin/master" '[ "$p1" = "$b/pool/pool-1" ] && [ "$WB" = lane/a ] && [ "$WS" = "$MS" ]'
	p2="$(pool lease lane/b 2>/dev/null)"
	check "lease 2 uses pool-2" '[ "$p2" = "$b/pool/pool-2" ]'
	out="$(pool lease lane/c 2>&1)"; rc=$?
	check "third lane refused with exit 3 and a clear message" '[ "$rc" -eq 3 ] && [[ "$out" == *"POOL FULL"* ]] && [[ "$out" == *"lane/a"* ]]'
	check "no third worktree was created" '[ ! -e "$b/pool/pool-3" ]'
	again="$(pool lease lane/a 2>/dev/null)"
	check "leasing a held branch returns its slot" '[ "$again" = "$p1" ]'
	out="$(poolx status 2>&1)"
	check "the script runs as a program: status lists both leases" '[[ "$out" == "lane pool:"* ]] && [[ "$out" == *"pool-1  LEASED  lane/a"* ]] && [[ "$out" == *"pool-2  LEASED  lane/b"* ]]'
}

# ---- section 2: release ---------------------------------------------------------------------------------------------------------------
sec_release() {
	fx release 2
	p1="$(pool lease lane/a 2>/dev/null)"
	pool lease lane/b >/dev/null 2>&1   # a second, untouched lease: the status count below must see exactly this one
	mkdir -p "$p1/icons/gen" "$p1/data/analyze-cache" "$p1/data/logs" "$p1/node_modules"
	echo i >"$p1/icons/gen/x.dmi"; echo c >"$p1/data/analyze-cache/c"; echo l >"$p1/data/logs/l"; echo b >"$p1/deepquarry.dmb"; echo r >"$p1/deepquarry.rsc"
	echo dirty >>"$p1/a.txt"
	out="$(pool release lane/a 2>&1)"; rc=$?
	check "release refuses a dirty tree" '[ "$rc" -ne 0 ] && [[ "$out" == *"not clean"* ]]'
	echo a >"$p1/a.txt"
	echo work >"$p1/work.txt"; git -C "$p1" add work.txt; git -C "$p1" commit -q -m work
	pool release lane/a >/dev/null 2>&1
	master_sha; wt_head "$p1"
	check "release detaches at origin/master" '[ -z "$WB" ] && [ "$WS" = "$MS" ]'
	check "release keeps icons/gen, data/analyze-cache and node_modules" '[ -f "$p1/icons/gen/x.dmi" ] && [ -f "$p1/data/analyze-cache/c" ] && [ -d "$p1/node_modules" ]'
	check "release deletes build outputs" '[ ! -e "$p1/deepquarry.dmb" ] && [ ! -e "$p1/deepquarry.rsc" ] && [ ! -e "$p1/data/logs" ]'
	check "release keeps an unmerged branch" 'g show-ref -q --verify refs/heads/lane/a'
	st="$(pool status)"; n=0; while IFS= read -r line; do [[ "$line" == *LEASED* ]] && n=$((n + 1)); done <<<"$st"
	check "the slot is free again" '[ "$n" -eq 1 ]'
}

# ---- section 3: reclaiming finished lanes, dirty free slots ---------------------------------------------------------------------------
sec_reclaim() {
	fx reclaim 2
	pool lease lane/a >/dev/null 2>&1
	p2="$(pool lease lane/b 2>/dev/null)"
	pool release lane/a >/dev/null 2>&1
	p1="$b/pool/pool-1"
	git -C "$p2" commit -q --allow-empty -m "lane work"
	g push -q origin "lane/b:master" 2>/dev/null; g fetch -q origin
	held="$(DQ_LANE_POOL_RECLAIM_IDLE_MIN=180 pool lease lane/x 2>&1)"; wt_head "$p2"
	check "a merged lane still working (recently touched) keeps its slot" '[[ "$held" != *reclaimed* ]] && [ "$WB" = lane/b ]'
	pool release lane/x >/dev/null 2>&1
	p3="$(DQ_LANE_POOL_RECLAIM_IDLE_MIN=0 pool lease lane/c 2>/dev/null)"; wt_head "$p3"
	check "a merged lane's slot is reclaimed for a new lease" '[ -n "$p3" ] && [ "$WB" = lane/c ]'
	check "the merged branch was deleted" '! g show-ref -q --verify refs/heads/lane/b'
	pool release lane/c >/dev/null 2>&1
	echo junk >"$p1/untracked.txt"
	p4="$(pool lease lane/d 2>/dev/null)"
	check "a dirty free slot is skipped" '[ "$p4" != "$p1" ] && [ -f "$p1/untracked.txt" ]'
}

# ---- section 4: waiting for a slot ----------------------------------------------------------------------------------------------------
sec_waiter() {
	fx waiter 2
	pool lease lane/d >/dev/null 2>&1
	pool lease lane/e >/dev/null 2>&1
	DQ_LANE_POOL_WAIT_POLL=1 poolx lease lane/f --wait --timeout 2 >"$b/wait.out" 2>"$b/wait.err" &
	waiter=$!
	waitfor 60 'st="$(pool status)"; [[ "$st" == *"queue 1: lane/f"* ]]'
	check "a waiter queues instead of failing on a full pool" 'kill -0 "$waiter" 2>/dev/null && [[ "$st" == *"queue 1: lane/f"* ]]'
	pool release lane/e >/dev/null 2>&1
	wait "$waiter"; wrc=$?
	read -r wout <"$b/wait.out"; wt_head "$wout"
	check "the waiter gets the freed slot and exits 0" '[ "$wrc" -eq 0 ] && [ -n "$wout" ] && [ "$WB" = lane/f ]'
	st="$(pool status)"
	check "the queue is empty afterwards" '[[ "$st" != *"queue "* ]]'
}

# ---- section 5: lane classes (compiler: reserved pool-c1/c2, ahead of general; light: one shared slot, own queue) ----------------------
sec_classes() {
	fx classes 1
	export DQ_LANE_POOL_COMPILER=2
	g1="$(pool lease lane/g1 2>/dev/null)"
	check "a general lane takes pool-1" '[ "$g1" = "$b/pool/pool-1" ]'
	out="$(pool lease lane/g2 2>&1)"; rc=$?
	check "general lanes never take the reserved compiler slots" '[ "$rc" -eq 3 ] && [ ! -e "$b/pool/pool-c1" ]'
	c1="$(pool lease tools/dmb-fix 2>/dev/null)"
	check "a tools/dmb* branch is a compiler lane on pool-c1" '[ "$c1" = "$b/pool/pool-c1" ]'
	c2="$(pool lease lane/zz --class compiler 2>/dev/null)"
	check "--class compiler takes pool-c2" '[ "$c2" = "$b/pool/pool-c2" ]'
	c3="$(pool lease tools/dmb-third 2>&1)"; rc=$?
	check "a third compiler lane finds the general slot held too: pool full" '[ "$rc" -eq 3 ]'
	pool release lane/g1 >/dev/null 2>&1
	c3="$(pool lease tools/dmb-third 2>/dev/null)"
	check "a compiler lane overflows into a free general slot" '[ "$c3" = "$b/pool/pool-1" ]'
	l1="$(pool lease docs/one --class light 2>/dev/null)"
	check "a light lane takes the one shared pool-light" '[ "$l1" = "$b/pool/pool-light" ]'
	out="$(pool lease docs/two --class light 2>&1)"; rc=$?
	check "a second light lane waits (pool full) instead of taking a game slot" '[ "$rc" -eq 3 ] && [[ "$out" == *light* ]]'
	pool release docs/one >/dev/null 2>&1
	check "the light slot is free after release" '[ -n "$(pool lease docs/two --class light 2>/dev/null)" ]'
	pool release docs/two >/dev/null 2>&1
	DQ_LANE_POOL_WAIT_POLL=1 poolx lease lane/gw --wait --timeout 2 >"$b/gw.out" 2>/dev/null &
	gw=$!
	waitfor 60 'st="$(pool status)"; [[ "$st" == *"queue 1: lane/gw"* ]]'
	DQ_LANE_POOL_WAIT_POLL=1 poolx lease tools/dmb-late --class compiler --wait --timeout 2 >"$b/late.out" 2>/dev/null &
	late=$!
	waitfor 60 'st="$(pool status)"; [[ "$st" == *"queue 2: "* ]]'
	first=""; while IFS= read -r line; do [[ "$line" == *"queue "[0-9]* ]] && { first="$line"; break; }; done <<<"$st"
	check "a compiler waiter sorts ahead of a general waiter" '[[ "$first" == *dmb-late* ]]'
	kill "$gw" "$late" 2>/dev/null; wait 2>/dev/null

	# status never waits for `du` (a built worktree takes a minute on Windows): a slow du is refreshed in the background
	mkdir -p "$b/slowbin"; printf '#!/bin/sh
sleep 25
echo 1024 "$2"
' >"$b/slowbin/du"; chmod +x "$b/slowbin/du"
	rm -rf "$b/state/sizes"
	t0=$EPOCHSECONDS; PATH="$b/slowbin:$PATH" pool status >/dev/null 2>&1; t1=$EPOCHSECONDS
	check "status returns promptly even when du is slow" '[ $((t1 - t0)) -lt 12 ]'
}

# ---- section 6: stuck leases ----------------------------------------------------------------------------------------------------------
sec_stuck() {
	fx stuck 2
	cp "$here/tools/dq_machine_slots.sh" "$b/repo/tools/"
	export DQ_SLOTS_DIR="$b/slots2" DQ_LANE_POOL_PROCS_CMD="echo nothing relevant"
	export DQ_LANE_POOL_STUCK_MIN=30 DQ_LANE_POOL_RECLAIM_IDLE_MIN=60
	sa="$(pool lease stuck/a 2>"$b/sa.err")"; sb="$(pool lease stuck/b 2>>"$b/sa.err")"; cat "$b/sa.err" >&2
	echo unsaved >>"$sa/a.txt"
	old() { # <slot dir> <slot name>: make every sign of activity two hours old
		local gd="$1/.git" k v; read -r k v <"$gd"; gd="$v"
		touch -d "2 hours ago" "$DQ_LANE_POOL_STATE/pool-$2.lease" "$gd/HEAD" "$gd/logs/HEAD" "$1/a.txt"
	}
	pool status >/dev/null 2>&1
	old "$sa" 1; old "$sb" 2
	out="$(pool stuck 2>&1)"; rc=$?
	check "stuck lists a dirty and a clean idle lease and exits 1" '[ "$rc" -eq 1 ] && [[ "$out" =~ STUCK\ pool-1\ stuck/a.*dirty=1.*report-only ]] && [[ "$out" =~ STUCK\ pool-2\ stuck/b.*dirty=0.*reclaimable ]]'
	notice="$(cat "$DQ_LANE_POOL_STATE/notices/pool-1.stuck" 2>/dev/null)"
	check "a notice file is written for a stuck lease" '[ -f "$DQ_LANE_POOL_STATE/notices/pool-1.stuck" ] && [[ "$notice" == *dirty=1* ]]'
	pool status >"$b/status.out" 2>&1; st="$(<"$b/status.out")"
	check "status flags STUCK with the idle time" '[[ "$st" =~ pool-1\ \ LEASED.*STUCK:\ no\ live\ process,\ idle\ 2h.*DIRTY ]] || { echo "$st" >&2; false; }'
	pool lease stuck/c >"$b/c.out" 2>"$b/c.err"; crc=$?
	cout="$(<"$b/c.out")"; cerr="$(<"$b/c.err")"; unsaved="$(<"$sa/a.txt")"; pa="$(pool path stuck/a)"
	check "the clean stuck lease is reclaimed, the dirty one is never wiped" '[ "$crc" -eq 0 ] && [[ "$cerr" == *"reclaimed pool-2 (stuck"* ]] && [ "$cout" = "$sb" ] && [[ "$unsaved" == *unsaved* ]] && [ "$pa" = "$sa" ]'
	DQ_LANE_POOL_PROCS_CMD="echo node run $sa/x" pool stuck >/dev/null 2>&1; lrc=$?
	check "a live process using the worktree makes it not stuck" '[ "$lrc" -eq 0 ]'
	check "the notice goes away once the lease is not stuck" '[ ! -f "$DQ_LANE_POOL_STATE/notices/pool-1.stuck" ]'
}

# ---- section 7: queued lease and cancel -----------------------------------------------------------------------------------------------
sec_cancel() {
	fx cancel 2
	pool lease stuck/a >/dev/null 2>&1
	pool lease stuck/c >/dev/null 2>&1
	DQ_LANE_POOL_WAIT_POLL=1 poolx lease stuck/w --wait --timeout 3 >"$b/w.out" 2>"$b/w.err" &
	cw=$!
	waitfor 60 'st="$(pool status 2>&1)"; [[ "$st" == *"queue 1: stuck/w"* ]]'
	check "a queued lease shows in status" 'kill -0 "$cw" 2>/dev/null && [[ "$st" == *"queue 1: stuck/w"* ]]'
	pool cancel stuck/w >/dev/null 2>&1
	wait "$cw"; cwrc=$?
	werr="$(<"$b/w.err")"; st="$(pool status 2>&1)"
	check "cancel makes the waiter exit 4 with a cancelled message, nothing killed" '[ "$cwrc" -eq 4 ] && [[ "$werr" == *cancelled* ]] && [[ "$st" != *stuck/w* ]]'
	out="$(pool cancel stuck/nobody 2>&1)"; nrc=$?
	check "cancel of an unknown branch is an error" '[ "$nrc" -ne 0 ] && [[ "$out" == *"no queued lease"* ]]'
}

# ---- section 8: the machine-slot suite cap (no repository needed) ---------------------------------------------------------------------
sec_cap() {
	b="$tmp/cap"; mkdir -p "$b"
	capsize() { ( export DQ_SLOTS_DIR="$b/slots3" DQ_SLOTS_TEST_WORLD=2 DQ_SLOTS_MERGE_RESERVE=0 DQ_SLOT_WORKTREE=/x/pool-9 DQ_SLOT_PRIORITY="${PRIO:-1}"; . "$here/tools/dq_machine_slots.sh"; slots_group_size test_world 2 ); }
	check "suite cap: no cap while nobody waits" '[ "$(capsize)" = 2 ]'
	mkdir -p "$b/slots3/test_world/queue"
	printf 'kind=bash\npid=%s\nworktree=/x/other\nlabel=f\nqueued=%s\n' "$$" "$EPOCHSECONDS" >"$b/slots3/test_world/queue/1-0000000000001-$$"
	check "suite cap: 1 world while another run waits, priority 0 exempt" '[ "$(capsize)" = 1 ] && [ "$(PRIO=0 capsize)" = 2 ]'
	check "suite cap: DQ_SLOTS_SUITE_MAX_WORLDS=2 always allows 2, =1 always caps" '[ "$(DQ_SLOTS_SUITE_MAX_WORLDS=2 capsize)" = 2 ] && [ "$(DQ_SLOTS_SUITE_MAX_WORLDS=1 capsize)" = 1 ]'
}

# ---- run the sections in parallel; print their output in order ------------------------------------------------------------------------
sections=(${DQ_TEST_SECTIONS:-lease release reclaim waiter classes stuck cancel cap})   # DQ_TEST_SECTIONS="classes stuck": run only those (profiling)
pids=()
for s in "${sections[@]}"; do
	( fail=0; "sec_$s"; exit "$fail" ) >"$tmp/out.$s" 2>"$tmp/err.$s" &
	pids+=("$!")
done
total=0
for i in "${!sections[@]}"; do
	wait "${pids[$i]}" || total=1
	cat "$tmp/out.${sections[$i]}"
	[ -s "$tmp/err.${sections[$i]}" ] && cat "$tmp/err.${sections[$i]}" >&2
done
[ "$total" -eq 0 ] && echo "test_lane_pool: all passed" || echo "test_lane_pool: FAILED"
exit "$total"
