// Test-build-only definitions moved out of the game files (engine/test-guards-out): procs, vars and globals only tests and the
// UNIT_TESTS-guarded hooks in those files use. Included near the end of deepquarry.dme (after every game file, so the macros those
// files define are in scope); compiled only in test builds.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// from code/modules/admin/view_variables/reference_tracking.dm: what the reference searches of a test run cost (filled under REFERENCE_TRACKING,
// read by unit_test.dm); outside that file's #ifdef REFERENCE_TRACKING so every test build and DreamChecker see them
GLOBAL_LIST_EMPTY(dq_refsearch_searched)
GLOBAL_LIST_EMPTY(dq_refsearch_type_counts)
GLOBAL_LIST_EMPTY(dq_refsearch_skipped)
GLOBAL_VAR_INIT(dq_refsearch_spent_ds, 0)

// from code/engine/actions/periodic_dispatch.dm
/datum/work_item/every_dispatch/test_reset()
	..()
	pending = null
	parked = TRUE


// from code/engine/change/staleness.dm
/// The suite is about to run its first test: reads the mode from the world params ("staleness=bounded", set by tools/dq_focused_test.sh for an ordinary
/// focused run; anything else is full) and logs it. Bounded parks the boot backlog (everything that appeared since boot) so the first test's sweep checks
/// what the test created plus a slice of it, not all of it.
/proc/staleness_suite_begin()
	var/mode = world.params?[STALENESS_MODE_PARAMETER]
	GLOB.staleness_periodic = GLOB.staleness_strict && mode == "periodic"
	GLOB.staleness_bounded = GLOB.staleness_strict && (mode == "bounded" || GLOB.staleness_periodic)
	GLOB.staleness_every = max(1, round(text2num(world.params?[STALENESS_EVERY_PARAMETER]) || STALENESS_FULL_EVERY))
	GLOB.staleness_since_full = list()
	log_test("STALENESS: test-end mode [GLOB.staleness_periodic ? "periodic" : (GLOB.staleness_bounded ? "bounded" : "full")], [length(GLOB.stale_all)] entities swept so far[GLOB.staleness_bounded ? "; the boot backlog is parked at the first test, [STALENESS_BOUNDED_BACKLOG] checked per test end" : ""][GLOB.staleness_periodic ? "; a full sweep every [GLOB.staleness_every] tests and after the last test" : ""]")

/// A test is about to run. The first one in a bounded run parks the boot backlog (everything swept before it, including what the round-start
/// settle created after suite start), so its end checks only what it created plus a slice of the backlog.
/proc/staleness_test_begin()
	if(!GLOB.staleness_bounded || GLOB.staleness_parked)
		return
	GLOB.staleness_parked = TRUE
	GLOB.stale_backlog = GLOB.stale_new
	GLOB.stale_new = list()
	var/unseen = 0
	for(var/datum/D as anything in GLOB.refresh_queue)
		if(!GLOB.stale_all[REF(D)])
			GLOB.stale_pretest[REF(D)] = TRUE
			unseen++
	log_test("STALENESS: parked [length(GLOB.stale_backlog)] swept entities as the boot backlog ([length(GLOB.stale_all)] swept in all) at [REALTIMEOFDAY] ds; [unseen] queued entities not swept yet are marked pre-test and join the backlog when first swept")

/// The end of a test: queued work settles, then everything that appeared during the test and a slice of the rest is checked, against the test's own
/// result (a report fails it). The expectation flag is the test's own and ends with it. Full mode checks all of the first sweep's backlog; bounded mode
/// (focused runs) checks what the test created plus STALENESS_BOUNDED_BACKLOG of the boot backlog, and the summary line says how much is left.
/proc/staleness_test_end(test, last_test = FALSE)
	if(!GLOB.staleness_strict)
		return
	var/started = REALTIMEOFDAY
	var/checks_before = GLOB.staleness_checks
	var/queued = length(GLOB.refresh_queue)
	var/found
	var/visited = 0
	if(GLOB.staleness_bounded)
		var/flush = queued <= STALENESS_BOUNDED_FLUSH_MAX
		found = staleness_sweep("end of test", settle = flush, backlog_budget = STALENESS_BOUNDED_BACKLOG)
		visited = GLOB.staleness_last_visited
		if(!flush)
			if(length(GLOB.stat_marked))
				stat_drain_point()
	else
		found = staleness_sweep("end of test", settle = TRUE)
		visited = GLOB.staleness_last_visited
	if(GLOB.staleness_periodic)
		found += staleness_periodic_step(test, last_test)
	GLOB.staleness_late_parked_total += GLOB.staleness_late_parked
	log_test("STALENESS: end of [test] late_parked=[GLOB.staleness_late_parked] late_parked_total=[GLOB.staleness_late_parked_total] pretest_unseen=[length(GLOB.stale_pretest)] mode=[GLOB.staleness_bounded ? "bounded" : "full"] entities_checked=[visited] stat_draw_checks=[GLOB.staleness_checks - checks_before] backlog_remaining=[GLOB.staleness_bounded ? length(GLOB.stale_backlog) : 0] swept_total=[length(GLOB.stale_all)] refresh_queued_before=[queued][GLOB.staleness_bounded && queued > STALENESS_BOUNDED_FLUSH_MAX ? " (not flushed)" : ""] found=[found] took_ds=[REALTIMEOFDAY - started]")
	GLOB.staleness_late_parked = 0
	if(found)
		log_world("STALENESS: [found] stale after [test]")
	GLOB.staleness_expected = FALSE

/// Periodic mode: records the test that just ended and, every STALENESS_FULL_EVERY tests and after the last one, checks everything the sweep walks. The
/// bounded sweep at each test end looks at what that test made plus a slice, so a stale cache left in older state surfaces here instead. A report from the
/// full sweep fails the test whose end ran it and names the tests since the last clean full sweep (the range it may belong to); the whole list is logged.
/// Returns the reports the full sweep filed.
/proc/staleness_periodic_step(test, last_test)
	GLOB.staleness_since_full += "[test]"
	if(!last_test && length(GLOB.staleness_since_full) < GLOB.staleness_every)
		return 0
	var/list/range = GLOB.staleness_since_full
	GLOB.staleness_since_full = list()
	GLOB.staleness_full_sweeps++
	var/started = REALTIMEOFDAY
	GLOB.staleness_range_note = "; found by full sweep #[GLOB.staleness_full_sweeps] after [length(range)] tests, so it belongs to one of them (first [range[1]], last [range[length(range)]]; all listed in tests.log)"
	var/found = staleness_sweep_full("periodic full sweep")
	GLOB.staleness_range_note = ""
	if(found)
		log_test("STALENESS: full sweep #[GLOB.staleness_full_sweeps] found [found] stale; the last clean full sweep was before these [length(range)] tests, one of them left it: [jointext(range, ", ")]")
		log_world("STALENESS: full sweep #[GLOB.staleness_full_sweeps] found [found] stale among [length(range)] tests ([range[1]] .. [range[length(range)]])")
	log_test("STALENESS: full sweep #[GLOB.staleness_full_sweeps] after [test] ([length(range)] tests since the last, [last_test ? "the last test" : "every [GLOB.staleness_every]"]) swept_total=[length(GLOB.stale_all)] found=[found] took_ds=[REALTIMEOFDAY - started]")
	return found

/// Checks every entity the sweep walks: the pending new ones, the whole boot backlog and one pass of the cursor over everything.
/proc/staleness_sweep_full(trigger)
	if(!GLOB.staleness_on || GLOB.staleness_depth)
		return 0
	staleness_settle()
	var/before = GLOB.staleness_found
	var/list/served = GLOB.staleness_served
	GLOB.staleness_served = list()
	for(var/ref in served)
		var/datum/D = locate(ref)
		if(isatom(D) && REF(D) == ref)
			staleness_check_draw(D, trigger, served[ref], forced = TRUE)
	var/list/fresh = GLOB.stale_new
	GLOB.stale_new = list()
	for(var/ref in fresh)
		staleness_check_ref(ref, trigger)
	var/list/backlog = GLOB.stale_backlog
	GLOB.stale_backlog = list()
	for(var/ref in backlog)
		staleness_check_ref(ref, trigger)
	staleness_sweep_older(trigger, length(GLOB.stale_all))
	GLOB.staleness_last_visited = length(fresh) + length(backlog) + length(GLOB.stale_all)
	return GLOB.staleness_found - before

// from code/engine/kernel/sequence.dm
/// Tests: the values of the reads of `S` that are vars of `E`, when it falls asleep.
/proc/seq_snapshot_note(datum/E, datum/seq_state/state, datum/seq_step/S)
	// A step earlier in this frame can replan E onto another table; the rest of the frame still walks the old one, and
	// its positions index a table that no longer exists. Those sleeps are void (the new table starts all awake).
	if(S.pos > state.table.n || state.table.steps[S.pos] != S)
		return
	var/list/snap
	for(var/key in S.keys)
		if(!(key in E.vars))
			continue
		if(!snap)
			snap = list()
		snap[key] = seq_snapshot_value(E.vars[key])
	if(!snap)
		return
	if(length(state.snaps) < S.pos)
		if(!state.snaps)
			state.snaps = list()
		state.snaps.len = state.table.n
	state.snaps[S.pos] = snap

/proc/seq_snapshot_value(value)
	if(islist(value))
		return json_encode(value)
	if(isdatum(value))
		return REF(value)
	return value

/// Tests: the reads of `S` that changed since it fell asleep (no publish woke it), or null.
/proc/seq_snapshot_diff(datum/E, datum/seq_state/state, datum/seq_step/S)
	var/list/snap = length(state?.snaps) >= S.pos ? state.snaps[S.pos] : null
	if(!snap)
		return null
	var/list/changed = list()
	for(var/key in snap)
		if(seq_snapshot_value(E.vars[key]) != snap[key])
			changed += key
	return length(changed) ? jointext(changed, ", ") : null

// from code/engine/kernel/sequence_state.dm
/// Tests: position -> (read key -> value) when that step fell asleep, for the audit's diff.
/datum/seq_state/var/list/snaps

// from code/engine/state/shared_cache.dm
/// Test-build CACHED(): a miss as usual, a hit verified against the build-time snapshot.
/datum/shared_cache/proc/guarded(key, ...)
	if(!store)
		resolve_store()
	if(!istext(key) && !ispath(key))
		if(isnum(key))
			CRASH("shared cache [name]: numeric key [key] (use CACHED_INT or a text key)")
		if(!shared_cache_stable_datum(key))
			CRASH("shared cache [name]: key [key] is an object without a stable identity; key by its registry id, type path or SHARED_CACHE_UID() instead")
	else if(istext(key) && findtext(key, "\[0x"))
		CRASH("shared cache [name]: key \"[key]\" embeds a ref, which is recycled when its datum is deleted; use a registry id, type path or SHARED_CACHE_UID()")
	guard_lookups++
	var/value = store[key]
	if(!value)
		return (length(args) > 1) ? miss(arglist(args)) : miss(key)
	verify(key, value)
	return value

/datum/shared_cache/proc/guarded_int(index)
	if(!store)
		resolve_store()
	guard_lookups++
	if(isnum(index) && index >= 1 && index <= length(store) && !isnull(store[index]))
		var/value = store[index]
		verify("[index]", value)
		return value
	return miss_int(index)

/// Runtimes when a caller wrote into a shared list (or a list nested one level inside it),
/// then restores the entry so later callers still see the built value.
/datum/shared_cache/proc/verify(key, value)
	if(!islist(value))
		return
	var/list/snap = snapshots?[key]
	if(!snap || shared_cache_snapshot_matches(value, snap))
		return
	mutations++
	shared_cache_snapshot_restore(value, snap)
	CRASH("shared cache [name]: a caller mutated the shared list for key [key]; Copy() a cached value before writing")

/// Verifies every stored list (the unit-test sweep at the end of a run).
/datum/shared_cache/proc/verify_all()
	. = 0
	for(var/key in snapshots)
		var/list/L = (flags & SC_INT_KEYS) ? store[text2num(key)] : store[key]
		if(islist(L) && !shared_cache_snapshot_matches(L, snapshots[key]))
			.++

/// A snapshot of L: list(copy of L, list(nested list, its copy, ...)) for lists that are
/// elements or assoc values of L (one level deep).
/proc/shared_cache_snapshot(list/L)
	var/list/nested
	for(var/k in L)
		if(islist(k))
			var/list/sub_key = k
			LAZYADD(nested, list(sub_key, sub_key.Copy()))
		if(isnum(k))
			continue
		var/v = L[k]
		if(islist(v))
			var/list/sub_value = v
			LAZYADD(nested, list(sub_value, sub_value.Copy()))
	return list(L.Copy(), nested)

/proc/shared_cache_snapshot_matches(list/L, list/snap)
	if(!(L ~= snap[1]))
		return FALSE
	var/list/nested = snap[2]
	for(var/i in 1 to length(nested) step 2)
		var/list/sub = nested[i]
		if(!(sub ~= nested[i + 1]))
			return FALSE
	return TRUE

/proc/shared_cache_snapshot_restore(list/L, list/snap)
	shared_cache_list_restore(L, snap[1])
	var/list/nested = snap[2]
	for(var/i in 1 to length(nested) step 2)
		shared_cache_list_restore(nested[i], nested[i + 1])

/proc/shared_cache_list_restore(list/L, list/copy)
	L.Cut()
	for(var/i in 1 to length(copy))
		var/k = copy[i]
		L += list(k)
		if(!isnum(k) && !isnull(copy[k]))
			L[k] = copy[k]

// from code/engine/state/shared_cache.dm
/// key -> copy of the value as built, for the mutation guard.
/datum/shared_cache/var/list/snapshots
/// Mutations caught (tests assert zero).
/datum/shared_cache/var/mutations = 0

// from code/engine/time/native_wakes.dm
/// Tests: owner -> wakes delivered + 1 (world_wake_trace()).
/datum/time_scheduler/var/list/world_traced

// from code/engine/time/scheduler.dm
/// Tests: when a list, every dispatched change is logged here as list(entity, bits).
/datum/time_scheduler/var/list/test_raises

// from code/engine/time/scheduler.dm
/// Test harness: lane -> TRUE makes run_lane() runtime for that lane (lane-isolation tests).
/datum/time_scheduler/var/list/harness_lane_fault

// from code/engine/time/world_watches.dm
/// Tests: start counting world wakes delivered to `owner`.
/proc/world_wake_trace(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	LAZYINITLIST(sched.world_traced)
	if(!sched.world_traced[owner])
		sched.world_traced[owner] = 1

/proc/world_wake_traced(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	return (sched.world_traced && sched.world_traced[owner]) ? sched.world_traced[owner] - 1 : 0

/proc/world_wake_untrace(datum/owner)
	var/datum/time_scheduler/sched = GLOB.om_live_sched
	if(sched.world_traced)
		sched.world_traced -= owner
		if(!length(sched.world_traced))
			sched.world_traced = null

// from code/engine/declare/type_lists.dm
/// The first time a second, different instance of a type asks for a list, rebuild it on that
/// instance and compare: a per-type list that reads instance state fails the run.
/proc/type_list_purity_check(datum/D, proc_ref, list/cached, post)
	// A table built during global init (a GLOB datum's New() writing an owned var reads its type's
	// declared entries) runs before these globals exist: that type is checked on a later instance.
	if(!islist(GLOB.type_list_purity))
		return
	var/key = "[D.type]|[proc_ref]"
	var/seen = GLOB.type_list_purity[key]
	if(seen == TRUE)
		return
	var/my_ref = ref(D)
	if(isnull(seen))
		GLOB.type_list_purity[key] = my_ref
		return
	if(seen == my_ref)
		return
	GLOB.type_list_purity[key] = TRUE
	var/list/again = build_type_list(D, proc_ref, post)
	if(!type_list_same(cached, again, 0))
		var/msg = TYPE_LIST_IMPURE(D.type, proc_ref)
		GLOB.type_list_impure += msg
		if(!GLOB.type_list_expect_impure)
			stack_trace(msg)

// from code/modules/admin/view_variables/reference_tracking.dm
/// Test builds: every automatic reference search (GC hard lookup, collapse
/// diagnostics) runs with FIND_REF_NO_CHECK_TICK and can freeze the world for
/// tens of seconds. Unbounded, a caller that keeps re-offering the same
/// object hangs the suite, so each object is searched once, each type at most
/// DQ_REFSEARCH_PER_TYPE times (once: a second search of the same leaking type repeats the first one's answer at ~5-40 s each), and all searches together get
/// DQ_REFSEARCH_BUDGET_DS of real time. Running out fails the run with a report
/// instead of hanging it.
#define DQ_REFSEARCH_PER_TYPE 1
#define DQ_REFSEARCH_BUDGET_DS (5 MINUTES)

/proc/dq_refsearch_allowed(datum/D)
	var/key = ref(D)
	if(GLOB.dq_refsearch_searched[key])
		log_reftracker("Skipping repeat search for references to [D.type] [key]: already searched once this run.")
		return FALSE
	if(GLOB.dq_refsearch_type_counts[D.type] >= DQ_REFSEARCH_PER_TYPE)
		GLOB.dq_refsearch_skipped[D.type]++
		log_reftracker("Skipping search for references to [D.type] [key]: type already searched [DQ_REFSEARCH_PER_TYPE] times.")
		return FALSE
	if(GLOB.dq_refsearch_spent_ds >= DQ_REFSEARCH_BUDGET_DS)
		GLOB.dq_refsearch_skipped[D.type]++
		var/message = "REF SEARCH budget exhausted ([GLOB.dq_refsearch_spent_ds / 10]s spent searching): skipped search for [D.type] [key]. Something keeps offering undeletable objects for reference searches; see the ## REF SEARCH lines in runtime.log."
		log_reftracker(message)
		log_test(message)
		GLOB.failed_any_test = TRUE
		return FALSE
	GLOB.dq_refsearch_searched[key] = TRUE
	GLOB.dq_refsearch_type_counts[D.type]++
	return TRUE

#undef DQ_REFSEARCH_PER_TYPE
#undef DQ_REFSEARCH_BUDGET_DS

// from code/engine/refs/ownership.dm
/// Test builds: the owner's type when it stamped this entity, so an orphan report names the real
/// owner even after its weak key was recycled by an unrelated datum.
/datum/var/tmp/own_holder_type

// from code/engine/refs/shared.dm
/// "type ref" -> hash of the instance's vars at boot.
GLOBAL_LIST_EMPTY(def_freeze_snapshot)

// from code/_helpers/logging/_logging.dm
/proc/log_test(text)
	WRITE_LOG(GLOB.test_log, text)
	SEND_TEXT(world.log, text)

// from code/engine/refs/shared.dm
/// Boot (test builds): digest every registered instance.
/proc/def_freeze_snapshot()
	GLOB.def_freeze_snapshot = list()
	for(var/datum/D as anything in def_freeze_instances())
		GLOB.def_freeze_snapshot["[D.type] [ref(D)]"] = def_freeze_digest(D)

/// Test end: every registered instance whose vars changed since boot, as report lines.
/proc/def_freeze_verify()
	. = list()
	for(var/datum/D as anything in def_freeze_instances())
		var/key = "[D.type] [ref(D)]"
		var/list/old = GLOB.def_freeze_snapshot[key]
		if(!islist(old))
			continue
		var/list/now = def_freeze_digest(D)
		var/list/changed = list()
		for(var/name in now)
			if(old[name] != now[name])
				changed += name
		if(length(changed))
			. += "DEF FROZEN: [D.type] ([ref(D)]) was written after boot: [jointext(changed, ", ")]"

#endif
