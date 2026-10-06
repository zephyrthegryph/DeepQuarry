// The test driver's kernel backends (doc/rewrite/final_api.html, section 15 "Test driver"; section 19 "E6, kernel completion").
//
//   test_time(t)    kernel_time_advance(t): the kernel clock moves by t, one slot at a time, and every phase runs for each slot
//                   in the order K, S, N, U, D, P, R, G, with a drain at the start of S, D, P and R. Timers, every() items,
//                   op waits and request timeouts fall due as they would in play.
//   test_phase(P)   kernel_phase_run(P): one phase once, at the current kernel time, moving no clock.
//   test_drain()    kernel_drain_now(): one drain point (change reactions, then the queued refreshes and appearances).
//
// The clock. A server tick cannot move world.time, so a test runs the kernel on an injected clock: kernel_test_begin() makes
// a test scheduler current (entities created from then on belong to it and read its injected time) and gives the kernel an
// injected `test_now`; the phases run through the same phase procs the live tick calls, with `now` passed in. Work items
// the live kernel already owns carry world.time due dates, far from the injected clock, so live items stay out of a test;
// an item no run has seen yet (a fixture system's every()) is armed one interval after the clock it first meets, so
// every(1 SECOND) runs exactly five times in test_time(5 SECONDS) instead of once at once and four more.
//
// Native frames and host services (tgui transport, dbcore, assets...) are not stepped: they pace on real time and the
// real kernel loop owns them. What a test steps is the kernel's own work: the work items of every phase, the OM
// scheduler's passes, urgent requests, and the inbox drain of phase K once it exists.
//
// Compiled under UNIT_TESTS only (and SPACEMAN_DMM).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// `test_now` (controllers/kernel/kernel.dm) is the injected kernel clock: set by kernel_test_begin(), cleared by
/// kernel_test_end().
/datum/controller/kernel
	/// Slots the test clock has stepped since kernel_test_begin() (what a test asserts it did not skip).
	var/test_slots = 0

/// TRUE while a test owns the kernel clock.
/proc/kernel_test_active()
	return !isnull(kernel().test_now)

/// Puts the kernel on an injected clock at 0 and makes a fresh test scheduler current, so that entities created from here
/// on read it (and test_time() advances them). Returns the scheduler. A second call while active returns the same one.
/proc/kernel_test_begin()
	RETURN_TYPE(/datum/om/scheduler)
	var/datum/controller/kernel/K = kernel()
	if(!isnull(K.test_now))
		return om_scheduler()
	var/datum/om/scheduler/sched = om_test_begin()
	K.test_now = 0
	K.test_slots = 0
	// The kernel's own infrastructure systems (the inbox, requests, jobs) and the Life sweep run in the test graph while the test owns the
	// clock; a sequence's sweep runs as in the game run level.
	for(var/datum/work_item/W as anything in K.work_all)
		if(W.owner_type in GLOB.kernel_test_systems)
			W.test_owned = TRUE
			if(istype(W, /datum/work_item/sequence))
				// In the game run level, and unspread: every member runs when the interval comes due (a test's few mobs all get
				// their frame on the same slot instead of one after another across the interval).
				var/datum/work_item/sequence/S = W
				S.test_runlevel = RUNLEVEL_GAME
				S.spread = FALSE
	// Each test meets its fixtures' items fresh: their schedule state from an earlier test is dropped.
	for(var/datum/work_item/W as anything in K.work_all)
		if(W.test_owned)
			W.test_reset()
	K.test_dirty = TRUE
	K.work_dirty = TRUE
	return sched

GLOBAL_LIST_INIT(kernel_test_systems, list(/datum/system/input, /datum/system/requests, /datum/system/kernel_jobs, /datum/sequence/life))

/// Hands the clock back: the live scheduler is current again, and the infrastructure systems' items return to the live graph.
/proc/kernel_test_end()
	var/datum/controller/kernel/K = kernel()
	if(isnull(K.test_now))
		return
	K.test_now = null
	om_test_end()
	for(var/datum/work_item/W as anything in K.work_all)
		if(W.owner_type in GLOB.kernel_test_systems)
			W.test_owned = FALSE
			W.test_reset()
			if(istype(W, /datum/work_item/sequence))
				var/datum/work_item/sequence/S = W
				S.test_runlevel = null
				S.spread = S.def.interval > world.tick_lag
	K.work_dirty = TRUE
	K.test_dirty = TRUE

/// Forgets what an earlier test's clock did to the item.
/datum/work_item/proc/test_reset()
	next_run = 0
	cursor = 0
	yielded = FALSE
	parked = FALSE
	runs = 0
	skips = 0
	faults = 0
	consecutive_faults = 0
	member_runs = 0
	last_at = null
	urgent_pending = null
	sweep_began = 0

/// A sequence's members carry their execution tokens on their states, stamped on the clock that ran them: handing the sweep to (or back
/// from) the test clock starts every member afresh, with one interval, as a dormant sweep resuming does.
/datum/work_item/sequence/test_reset()
	..()
	for(var/datum/member as anything in members_of(members))
		var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
		if(state)
			state.last_at = null
			state.acc = 0
	for(var/datum/member as anything in members_of(def.parked_key))
		var/datum/seq_state/state = SEQ_STATE_OF(member, def.idx)
		if(state)
			state.last_at = null
			state.acc = 0

/// Switches the kernel's phase lists to the test-owned items' (built on first use and when an item registered), until test_leave().
/datum/controller/kernel/proc/test_enter()
	live_items = phase_items
	live_lane_items = phase_lane_items
	live_due = phase_due
	live_errors = work_errors
	live_dirty = work_dirty
	test_stepping = TRUE
	phase_items = test_items
	phase_lane_items = test_lane_items
	phase_due = test_due
	if(test_dirty || !phase_items)
		rebuild_work_graph()
		test_dirty = FALSE

/// Puts the live phase lists back; the test graph keeps its own.
/datum/controller/kernel/proc/test_leave()
	test_items = phase_items
	test_lane_items = phase_lane_items
	test_due = phase_due
	test_stepping = FALSE
	phase_items = live_items
	phase_lane_items = live_lane_items
	phase_due = live_due
	work_errors = live_errors
	work_dirty = live_dirty || work_dirty

/// Arms the items no run has seen: due one interval after `now`. A woken or running item keeps its own due date.
/datum/controller/kernel/proc/test_arm(now)
	for(var/datum/work_item/W as anything in work_all)
		if(!W.test_owned)
			continue
		if(W.next_run || W.runs || W.cursor || W.yielded || W.parked || W.event || W.last_at)
			continue
		W.next_run = now + W.interval
	work_due_reset()

/// The scheduler the injected clock moves: the current test scheduler, started on first use.
/datum/controller/kernel/proc/test_sched()
	var/datum/om/scheduler/S = om_scheduler()
	if(isnull(S.manual_time))
		S = kernel_test_begin()
	return S

/// Runs `phase` once at `now`. The scheduler's pass must be open for N..R (kernel_phase_run opens it).
/datum/controller/kernel/proc/test_run_phase(phase, now)
	switch(phase)
		if(KERNEL_PHASE_K)
			work_run_phase(KERNEL_PHASE_K, WORK_TEST_LIMIT, 0, now)
		if(KERNEL_PHASE_S)
			kernel_drain_now()
			work_run_phase(KERNEL_PHASE_S, WORK_TEST_LIMIT, 0, now)
		if(KERNEL_PHASE_N)
			work_run_phase(KERNEL_PHASE_N, WORK_TEST_LIMIT, 0, now)
		if(KERNEL_PHASE_U)
			run_urgent(WORK_TEST_LIMIT, now)
		if(KERNEL_PHASE_D)
			kernel_drain_now()
			run_deadline_phase(WORK_TEST_LIMIT, now)
		if(KERNEL_PHASE_P)
			kernel_drain_now()
			run_lane_phase(WORK_TEST_LIMIT, now)
		if(KERNEL_PHASE_R)
			kernel_drain_now()
			run_leftover_phase(WORK_TEST_LIMIT, now)
		if(KERNEL_PHASE_G)
			work_run_phase(KERNEL_PHASE_G, WORK_TEST_LIMIT, 0, now)
		else
			CRASH("kernel test: [phase] is not a kernel phase")

/// Runs the scheduler-backed phases of one slot under a pass: the OM scheduler's own pieces sit inside N..R.
/datum/controller/kernel/proc/test_slot(now)
	var/datum/om/scheduler/S = test_sched()
	var/datum/om/scheduler/saved = sched
	sched = S // ALLOW(ownership): the test clock lends the kernel its scheduler for one slot and puts the live one back
	S.manual_time = now
	test_slots++
	test_enter()
	test_run_phase(KERNEL_PHASE_K, now)
	test_run_phase(KERNEL_PHASE_S, now)
	S.pass_begin(WORK_TEST_LIMIT)
	stat_tick_begin()
	for(var/phase in KERNEL_PHASE_N to KERNEL_PHASE_R)
		test_run_phase(phase, now)
	S.pass_end()
	test_run_phase(KERNEL_PHASE_G, now)
	test_leave()
	sched = saved // ALLOW(ownership): the live scheduler goes back

// ---- the forms the driver calls ----

/// Advances the kernel clock by `t` deciseconds, a slot at a time (OM_SLOT_DS), running every phase and every drain that falls due.
/proc/kernel_time_advance(t)
	var/datum/controller/kernel/K = kernel()
	var/datum/om/scheduler/S = K.test_sched()
	if(isnull(K.test_now))
		K.test_now = S.manual_time || 0
	K.test_arm(K.test_now)
	var/target = K.test_now + t
	while(K.test_now < target)
		K.test_now = min(K.test_now + OM_SLOT_DS, target)
		K.test_slot(K.test_now)
		vg_heat_net_advance(OM_SLOT_DS / (1 SECONDS)) // the test clock does not pace the native world: the heat network's edges advance with it

/// Runs one kernel phase once at the current kernel time and moves no clock, so a timer that is not yet due stays pending.
/proc/kernel_phase_run(phase)
	var/datum/controller/kernel/K = kernel()
	var/datum/om/scheduler/S = K.test_sched()
	if(isnull(K.test_now))
		K.test_now = S.manual_time || 0
	K.test_arm(K.test_now)
	var/datum/om/scheduler/saved = K.sched
	K.sched = S // ALLOW(ownership): the test clock lends the kernel its scheduler for one phase and puts the live one back
	S.manual_time = K.test_now
	var/scheduled = phase >= KERNEL_PHASE_N && phase <= KERNEL_PHASE_R
	K.test_enter()
	if(scheduled)
		S.pass_begin(WORK_TEST_LIMIT)
	K.test_run_phase(phase, K.test_now)
	if(scheduled)
		S.pass_end()
	K.test_leave()
	K.sched = saved // ALLOW(ownership): the live scheduler goes back

/// Runs one marked drain now: the change reactions, then the queued refreshes and appearances (E3 replaces the body with its
/// budgeted marked drain; this is the drain point the kernel's phases call).
/proc/kernel_drain_now()
	stat_drain_point()
	appearance_flush()

#endif
