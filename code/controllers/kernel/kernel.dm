/// The kernel (doc/rewrite/kernel.md sec 1.2, 3.1): one host loop step per tick, in fixed phases. The host loop
/// (loop.dm) is the kernel's own: it replaced the MC Loop, and there is no subsystem queue left behind it. What the MC
/// queue used to run is either a host service the kernel fires in phase K or G (tgui transport, dbcore, profiler,
/// garbage) or a system's work items (the input inbox, air, lighting, ticker, ...).
///
///   K  the input inbox, then the host services (tgui transport, dbcore, sqlite, assets, atoms, overlays, profiler), capped and measured
///   S  simulation sync: what Rust needs from DM, pushed right before the native step (never shed)
///   N  native: native_frame(elapsed, budget), the one Rust frame
///   U  urgent requests, from a reserved slice (kernel_urgent())
///   D  deadlines (the OM scheduler's deadline wheel) and deadline-phase work items
///   P  the borrow pass, then each lane by share: queued wakes, rings, work items
///   R  leftovers, lane order
///   G  garbage (a host service), whatever is left, with a floor per second
///
/// SSbehaviours no longer fires: its work (the scheduler pass, the pipeline audit, the bench counter) is here.
/// The scheduler is the engine; the kernel owns the tick.

/datum/controller/kernel
	name = "Kernel"
	/// world.time of the last kernel_tick() (the failsafe heartbeat), and how many ran.
	var/last_tick = 0
	var/ticks = 0
	/// The live OM scheduler, or null before SSbehaviours initialized it.
	var/datum/om/scheduler/sched
	/// world.time phase G last got its floor slice (KERNEL_GARBAGE_FLOOR percent of a tick, once a second).
	var/last_g_floor = 0
	/// world.time of the last native frame (deciseconds elapsed feed native_frame()).
	var/last_native = 0

	// ---- work items
	/// Every registered item, in registration order; by owner type; by key.
	var/list/work_all = list()
	var/list/work_by_owner = list()
	var/list/work_by_key = list()
	/// phase -> items in dependency order, rebuilt when the graph changes.
	var/list/phase_items
	/// Phase P's items by lane (LANE_* -> items in dependency order), rebuilt with phase_items.
	var/list/phase_lane_items
	var/work_dirty = TRUE
	/// Phase P items that ran out of their lane's share this tick with work left (a yielded fire(), an open sweep):
	/// phase R gives them what is left of the tick, as the scheduler's leftovers pass does for its rings.
	var/list/p_carry
	/// The earliest world.time any item of a phase list may be due (index: phase, or KERNEL_PHASE_COUNT + lane for phase
	/// P's lane lists), recorded by the last walk of that list: work_run_phase() skips the walk before it. 0: walk.
	/// Reset by rebuild_work_graph() and by any wake (work_due_reset()).
	var/list/phase_due
	/// world/New sets it: the live work (cadence and sequence sweeps) may register now, and kernel() does it once.
	var/registration_open = FALSE
	var/live_registered = FALSE

	// ---- the test clock (code/tests/driver/kernel_clock.dm; all null/FALSE live)
	/// The injected kernel clock, deciseconds, while a test owns it (kernel_test_begin()); null live.
	var/test_now
	/// TRUE while a test slot or phase runs: the phase lists below are the test-owned items' (test_enter()).
	var/test_stepping = FALSE
	/// A test graph's phase lists, due dates and dirt, and the live graph's while a test step runs (test_enter(), test_leave()).
	var/list/test_items
	var/list/test_lane_items
	var/list/test_due
	var/test_dirty = TRUE
	var/list/live_items
	var/list/live_lane_items
	var/list/live_due
	var/list/live_errors
	var/live_dirty = TRUE
	/// The loop's init stage this tick: during boot the carry is off (run_leftover_phase()), so the leftovers of a tick
	/// go to the initializing subsystems sleeping in CHECK_TICK, not to a presentation backlog.
	var/tick_init_stage = INITSTAGE_MAX
	/// kernel_latency(), held so the per-item gate is a var read. Taken on first use: the live kernel can be built during
	/// global init, before kernel_latency()'s static is.
	var/datum/kernel_latency/latency_state
	/// Problems the last graph validation found (a missing target, a cycle, an edge into a later phase).
	var/list/work_errors = list()
	/// Capability types some item names in `members`: their holders join the membership store in caps_init().
	var/list/cap_wanted = list()
	/// Membership key -> the items that sweep it (so a member leaving can drop its execution token).
	var/list/work_by_members = list()
	/// Cadence type -> its sweep item (datums/om/periodic.dm): periodic work is membership of a cadence.
	var/list/cadence_items = list()

	// ---- urgent requests (urgent.dm)
	var/list/urgent_queue = list()
	var/urgent_requested = 0
	var/urgent_deduped = 0
	var/urgent_run = 0
	var/urgent_breaches = 0
	var/urgent_lateness_ds = 0
	var/urgent_dropped = 0

	// ---- accounting
	/// Per phase (index = KERNEL_PHASE_*): ms last tick, total ms, and the tick usage the K phase took over its cap.
	var/list/phase_ms_last
	var/list/phase_ms_total
	var/k_over_cap = 0
	var/phase_faults = 0
	var/last_tick_ms = 0
	/// This tick's milliseconds inside the OM scheduler's own pass pieces (pass_begin/deadlines/borrow/lanes/leftovers/
	/// pass_end), without the native frame and the work items that share phases N..R. It is what SSbehaviours' run_pass
	/// measured before the kernel, so the life benchmark compares like for like (SSbehaviours.bench_ms).
	var/sched_ms_tick = 0
	/// Milliseconds of the whole N..R span since boot (scheduler, native frame and those phases' work items).
	var/pass_ms_total = 0
	/// Caught faults (phases, work items, urgent runs), newest last, bounded. Tests that fault on purpose set expect_errors.
	var/list/fault_log
	var/expect_errors = FALSE

/datum/controller/kernel/New()
	..()
	phase_ms_last = new /list(KERNEL_PHASE_COUNT)
	work_due_reset()
	phase_ms_total = new /list(KERNEL_PHASE_COUNT)
	for(var/i in 1 to KERNEL_PHASE_COUNT)
		phase_ms_last[i] = 0
		phase_ms_total[i] = 0
	// Capabilities the generated reaction list runs work per member of: their holders join at init (reactions/work.dm).
	for(var/cap in rx_boot_members())
		cap_wanted[cap] = TRUE

/// The kernel (the `Kernel` global; world/Genesis makes it). Its periodic cadences' sweep items (datums/om/periodic.dm) and the
/// sequences' sweep items (kernel/sequence.dm) register on the first call after world/New opened registration. A kernel a test
/// makes with `new` starts empty.
/proc/kernel()
	RETURN_TYPE(/datum/controller/kernel)
	if(!Kernel)
		Kernel = new /datum/controller/kernel
	if(Kernel.registration_open && !Kernel.live_registered)
		Kernel.live_registered = TRUE
		kernel_register_cadences(Kernel)
		kernel_register_sequences(Kernel)
		kernel_register_sched_pieces(Kernel)
	return Kernel

// ---------------------------------------------------------------- the tick

/// phase_note() inlined for the tick's own seven phases (one proc call each per tick saved).
#define KERNEL_PHASE_NOTE(phase, started) var/ms_##started = TICK_USAGE_TO_MS(started); phase_ms_last[phase] = ms_##started; phase_ms_total[phase] += ms_##started

/// One kernel tick. `tick_limit` is the absolute tick usage the kernel's phases must stay under (K and U may pass
/// it by their own rules); `init_stage` is the loop's init stage.
/datum/controller/kernel/proc/tick(tick_limit, init_stage = INITSTAGE_MAX, light = FALSE)
	var/tick_start = TICK_USAGE
	var/saved_limit = Kernel.current_ticklimit
	// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
	last_tick = world.time
	ticks++
	tick_init_stage = init_stage
	if(!sched)
		sched = GLOB.om_live_sched

	phase_begin()
	// The phase lists, rebuilt here when the graph changed, so the phases read them without a call each.
	if(work_dirty || !phase_items)
		rebuild_work_graph()
	var/list/items_by_phase = phase_items
	// Each phase runs inside its own try (not through a call() wrapper, which cost an arglist copy and a dynamic
	// call per phase per tick): a runtime in one phase is reported by phase_fault() and the tick goes on.
	// The tick begins at depth zero: whatever a runtime leaked in the last one is cleared here, and logged.
	act_backstop_reset()
	// K
	var/k_start = TICK_USAGE
	// The phase's work items first (the input inbox drains here, ahead of every host service), then the host services.
	if(length(items_by_phase[KERNEL_PHASE_K]))
		try
			work_run_phase(KERNEL_PHASE_K, tick_limit)
		catch(var/exception/k_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_K, k_e)
	if(TICK_USAGE - k_start > KERNEL_INPUT_CAP)
		k_over_cap++
	KERNEL_PHASE_NOTE(KERNEL_PHASE_K, k_start)

	// S: simulation sync. Whatever is pushed to Rust is pushed now, so input resolved in K reaches this frame's native
	// step. It has no scheduler piece and is never shed: the phase's own items, under the tick's limit.
	var/s_start = TICK_USAGE
	if(length(items_by_phase[KERNEL_PHASE_S]))
		try
			work_run_phase(KERNEL_PHASE_S, tick_limit)
		catch(var/exception/s_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_S, s_e)
	KERNEL_PHASE_NOTE(KERNEL_PHASE_S, s_start)

	if(!light && sched && isnull(sched.manual_time) && sched_runs(init_stage))
		var/sb_start = TICK_USAGE
		sched.pass_begin(tick_limit)
		stat_tick_begin()
		sched_ms_tick = TICK_USAGE_TO_MS(sb_start)
		// N
		var/n_start = TICK_USAGE
		var/elapsed = last_native ? min(world.time - last_native, KERNEL_NATIVE_MAX_CATCHUP * world.tick_lag) : world.tick_lag
		// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
		last_native = world.time
		try
			// The phase's own systems first (the air system's atmos pass), then the one native frame.
			if(length(items_by_phase[KERNEL_PHASE_N]))
				work_run_phase(KERNEL_PHASE_N, tick_limit)
			run_native(elapsed, sched.world_budget)
		catch(var/exception/n_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_N, n_e)
		KERNEL_PHASE_NOTE(KERNEL_PHASE_N, n_start)
		// U
		var/u_start = TICK_USAGE
		if(length(urgent_queue))
			try
				run_urgent(min(tick_limit, TICK_USAGE + sched.pass_avail * KERNEL_URGENT_SHARE))
			catch(var/exception/u_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
				phase_fault(KERNEL_PHASE_U, u_e)
		KERNEL_PHASE_NOTE(KERNEL_PHASE_U, u_start)
		// D
		var/d_start = TICK_USAGE
		try
			run_deadline_phase(tick_limit)
		catch(var/exception/d_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_D, d_e)
		KERNEL_PHASE_NOTE(KERNEL_PHASE_D, d_start)
		// P
		var/p_start = TICK_USAGE
		try
			run_lane_phase(tick_limit)
		catch(var/exception/p_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_P, p_e)
		KERNEL_PHASE_NOTE(KERNEL_PHASE_P, p_start)
		// R
		var/r_start = TICK_USAGE
		try
			run_leftover_phase(tick_limit)
		catch(var/exception/r_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_R, r_e)
		KERNEL_PHASE_NOTE(KERNEL_PHASE_R, r_start)
		// The scheduler pass is N through R: phase K's host services (input, verbs, tgui, ...) are not part of it.
		var/se_start = TICK_USAGE
		sched.pass_end()
		sched_ms_tick += TICK_USAGE_TO_MS(se_start)
		var/pass_ms = TICK_USAGE_TO_MS(sched.pass_start)
		note_behaviours(pass_ms, sched_ms_tick)

	// G: whatever is left, with a floor once a second.
	var/g_start = TICK_USAGE
	var/g_limit = tick_limit
	// ALLOW(sys_world_time_expiry): the kernel clock: compares the scheduler own timestamps, not an entity expiry
	if(world.time - last_g_floor >= KERNEL_GARBAGE_FLOOR_PERIOD)
		g_limit = max(tick_limit, TICK_USAGE + KERNEL_GARBAGE_FLOOR)
		// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
		last_g_floor = world.time
	if(length(items_by_phase[KERNEL_PHASE_G]))
		try
			work_run_phase(KERNEL_PHASE_G, g_limit)
		catch(var/exception/g_e) // ALLOW(silent_catch): phase_fault() reports it through report_fault()
			phase_fault(KERNEL_PHASE_G, g_e)
	KERNEL_PHASE_NOTE(KERNEL_PHASE_G, g_start)

	last_tick_ms = TICK_USAGE_TO_MS(tick_start)
	Kernel.current_ticklimit = saved_limit

#undef KERNEL_PHASE_NOTE

/// TRUE when the scheduler passes run this tick: SSbehaviours (the scheduler's boot) has initialized for the loop's
/// stage, and the runlevel is one it ran in. The rule SSbehaviours' own MC entry had.
/datum/controller/kernel/proc/sched_runs(init_stage)
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	if(!SSbehaviours || !SSbehaviours.initialized || SSbehaviours.init_stage > init_stage || !SSbehaviours.can_fire)
		return FALSE
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	return SSbehaviours.periodic_runlevel_ok()

/// Clears the per-tick phase accounting.
/datum/controller/kernel/proc/phase_begin()
	for(var/i in 1 to KERNEL_PHASE_COUNT)
		phase_ms_last[i] = 0

/// Adds a phase's cost since `started` to the accounting.
/datum/controller/kernel/proc/phase_note(phase, started)
	var/ms = TICK_USAGE_TO_MS(started)
	phase_ms_last[phase] = ms
	phase_ms_total[phase] += ms

/// Records a caught fault, and reports it through dq_report_caught() (the runtime log; a test run counts it) unless
/// errors are expected.
/datum/controller/kernel/proc/report_fault(exception/e, msg)
	LAZYADD(fault_log, msg)
	if(length(fault_log) > 200)
		fault_log.Cut(1, 101)
	if(!expect_errors)
		dq_report_caught(e, "kernel: [msg]")

/// A runtime escaped phase `phase`: it is logged and counted, and the tick goes on.
/datum/controller/kernel/proc/phase_fault(phase, exception/e)
	phase_faults++
	report_fault(e, "kernel phase [phase_letter(phase)] aborted: [e] ([e.file]:[e.line])")

/// The letter of a KERNEL_PHASE_*.
/proc/phase_letter(phase)
	var/list/letters = KERNEL_PHASE_LETTERS
	return letters[phase] || "?"

// ---------------------------------------------------------------- phases

/// N: the native frame. native_frame() (native.dm) runs the native system's frame.
/datum/controller/kernel/proc/run_native(elapsed, budget)
	native_frame(elapsed, budget)

/// D: the deadline wheel (the scheduler's sched_deadlines item runs first), then deadline-phase work items in what is left of the
/// deadline share.
// ALLOW(sys_world_time_write): the kernel clock: a phase default of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_deadline_phase(tick_limit, now = world.time)
	stat_drain_point()
	work_run_phase(KERNEL_PHASE_D, min(tick_limit, sched.pass_start + sched.pass_avail * OM_DEADLINE_SHARE + sched.pass_avail * KERNEL_URGENT_SHARE), 0, now)

/// P: each lane, in order. A lane's items start with the scheduler's pieces: the borrow pass (lane 1 only), then the lane's
/// share of the pass (sched_lane); that lane's other work items follow.
// ALLOW(sys_world_time_write): the kernel clock: a phase default of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_lane_phase(tick_limit, now = world.time)
	stat_drain_point()
	var/datum/kernel_latency/latency = latency_state || (latency_state = kernel_latency())
	for(var/lane in 1 to OM_LANE_COUNT)
		// kernel_admit_lane(), asked only while shedding (it admits everything otherwise).
		if(latency.shedding && !latency.admit(kernel_lane_class(lane), "lane [lane]"))
			continue
		var/lane_limit = min(TICK_USAGE + sched.pass_avail * sched.lane_share[lane], tick_limit)
		work_run_phase(KERNEL_PHASE_P, lane_limit, lane, now)

/// R: leftovers. The scheduler's leftovers (its sched_leftovers item runs first), R's own items, then phase P items that ran out of their lane's share with
/// work left (p_carry), in the order they stopped: a backlog (lighting after a power change, a long fire()) drains with
/// whatever the tick has spare instead of one lane share per tick.
// ALLOW(sys_world_time_write): the kernel clock: a phase default of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_leftover_phase(tick_limit, now = world.time)
	stat_drain_point()
	work_run_phase(KERNEL_PHASE_R, tick_limit, 0, now)
	if(!length(p_carry))
		return
	var/list/carry = p_carry
	p_carry = null
	if(tick_init_stage < INITSTAGE_MAX)
		// Boot: the rest of the tick belongs to the subsystems still initializing (they sleep in CHECK_TICK).
		return
	for(var/datum/work_item/W as anything in carry)
		if(TICK_USAGE >= tick_limit)
			break
		run_item(W, tick_limit, now)

/// The work items of a phase that has no scheduler piece of its own (K, N, G).
/datum/controller/kernel/proc/run_work_phase(phase, tick_limit)
	work_run_phase(phase, tick_limit)

// ---------------------------------------------------------------- SSbehaviours' remaining duties

/// SSbehaviours stopped firing; its profiler and benchmark counters are fed from the kernel's scheduler passes.
/// `pass_ms` is the whole N..R span (native frame and work items included); `sched_ms` only the OM scheduler's pieces.
/datum/controller/kernel/proc/note_behaviours(pass_ms, sched_ms)
	pass_ms_total += pass_ms
	if(!SSbehaviours)
		return
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.bench_ms += sched_ms
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.last_done = sched.pass_done
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.fire_cost = SSbehaviours.fire_cost ? KERNEL_AVERAGE_FAST(SSbehaviours.fire_cost, pass_ms) : pass_ms
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.times_fired++
	// ALLOW(sys_world_time_write, system_boundary): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry; the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.last_fire = world.time

// ---------------------------------------------------------------- telemetry

/// Telemetry for the profiler and the stat panel: the phases, the queue depths, urgent requests and the busiest
/// work items. Per-reaction cost accounting: every item's own metrics, plus the sum by owner type.
/datum/controller/kernel/proc/metrics()
	var/list/phases = list()
	for(var/i in 1 to KERNEL_PHASE_COUNT)
		phases[phase_letter(i)] = alist("ms_last" = phase_ms_last[i], "ms_total" = phase_ms_total[i])
	var/list/by_owner = list()
	for(var/owner in work_by_owner)
		by_owner["[owner]"] = work_cost_of(owner)
	var/list/items = list()
	for(var/datum/work_item/W as anything in work_all)
		items[W.key] = W.metrics()
	return alist("ticks" = ticks, "last_tick_ms" = last_tick_ms, "phases" = phases, "k_over_cap" = k_over_cap, "phase_faults" = phase_faults, \
		"work_items" = length(work_all), "work_errors" = length(work_errors), "by_owner" = by_owner, "work" = items, \
		"urgent" = alist("requested" = urgent_requested, "deduped" = urgent_deduped, "run" = urgent_run, "breaches" = urgent_breaches, \
			"lateness_ds" = urgent_lateness_ds, "pending" = length(urgent_queue), "dropped" = urgent_dropped))

/// The summed cost of every item `owner_type` registered: alist(items, runs, member_runs, total_ms, faults).
/datum/controller/kernel/proc/work_cost_of(owner_type)
	var/items = 0
	var/runs = 0
	var/member_runs = 0
	var/total_ms = 0
	var/faults = 0
	for(var/datum/work_item/W as anything in work_by_owner[owner_type])
		items++
		runs += W.runs
		member_runs += W.member_runs
		total_ms += W.total_ms
		faults += W.faults
	return alist("items" = items, "runs" = runs, "member_runs" = member_runs, "total_ms" = total_ms, "faults" = faults)
