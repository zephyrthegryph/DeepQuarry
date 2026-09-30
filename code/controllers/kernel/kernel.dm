/// The kernel (doc/rewrite/kernel.md sec 1.2, 3.1): one host loop step per tick, in fixed phases. The host loop
/// (loop.dm) is the kernel's own: it replaced the MC Loop, and there is no subsystem queue left behind it. What the MC
/// queue used to run is either a host service the kernel fires in phase K or G (input, verb_manager, speech_controller,
/// tgui transport, dbcore, profiler, garbage) or a system's work items (air, lighting, ticker, ...).
///
///   K  host services (input, verb_manager, tgui transport, dbcore, sqlite, assets, atoms, overlays, profiler), capped and measured
///   N  native: native_frame(elapsed, budget), the one Rust frame
///   U  urgent requests, from a reserved slice (request_urgent())
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
	/// Subsystems the kernel runs itself, in phase order (resolved on first tick).
	var/list/hosted_k
	var/list/hosted_g
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
	var/work_dirty = TRUE
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
	/// Caught faults (phases, work items, urgent runs), newest last, bounded. Tests that fault on purpose set expect_errors.
	var/list/fault_log
	var/expect_errors = FALSE

/datum/controller/kernel/New()
	..()
	phase_ms_last = new /list(KERNEL_PHASE_COUNT)
	phase_ms_total = new /list(KERNEL_PHASE_COUNT)
	for(var/i in 1 to KERNEL_PHASE_COUNT)
		phase_ms_last[i] = 0
		phase_ms_total[i] = 0
	// Capabilities the generated reaction list runs work per member of: their holders join at init (reactions/work.dm).
	for(var/cap in rx_boot_members())
		cap_wanted[cap] = TRUE

/// The kernel.
/proc/kernel()
	RETURN_TYPE(/datum/controller/kernel)
	var/static/datum/controller/kernel/K = kernel_create_live()
	return K

/// The live kernel, with the periodic cadences' sweep items (datums/om/periodic.dm) registered. A kernel a test makes
/// with `new` starts empty.
/proc/kernel_create_live()
	var/datum/controller/kernel/K = new
	kernel_register_cadences(K)
	return K

// ---------------------------------------------------------------- the tick

/// One kernel tick. `tick_limit` is the absolute tick usage the kernel's phases must stay under (K and U may pass
/// it by their own rules); `init_stage` is the MC loop's stage: a hosted subsystem of a later stage does not run yet.
/datum/controller/kernel/proc/tick(tick_limit, init_stage = INITSTAGE_MAX, light = FALSE)
	var/tick_start = TICK_USAGE
	var/saved_limit = Master.current_ticklimit
	// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
	last_tick = world.time
	ticks++
	if(!sched)
		sched = GLOB.om_live_sched
	if(!hosted_k)
		hosted_k = hosts_of(KERNEL_PHASE_K)
		hosted_g = hosts_of(KERNEL_PHASE_G)

	phase_begin()
	// K
	var/k_start = TICK_USAGE
	run_hosted_phase(hosted_k, tick_limit, init_stage)
	guarded(KERNEL_PHASE_K, TYPE_PROC_REF(/datum/controller/kernel, run_work_phase), KERNEL_PHASE_K, tick_limit)
	if(TICK_USAGE - k_start > KERNEL_INPUT_CAP)
		k_over_cap++
	phase_note(KERNEL_PHASE_K, k_start)

	if(!light && sched && isnull(sched.manual_time) && sched_runs(init_stage))
		sched.pass_begin(tick_limit)
		// N
		var/n_start = TICK_USAGE
		var/elapsed = last_native ? min(world.time - last_native, KERNEL_NATIVE_MAX_CATCHUP * world.tick_lag) : world.tick_lag
		// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
		last_native = world.time
		guarded(KERNEL_PHASE_N, TYPE_PROC_REF(/datum/controller/kernel, run_native), elapsed, sched.world_budget)
		guarded(KERNEL_PHASE_N, TYPE_PROC_REF(/datum/controller/kernel, run_work_phase), KERNEL_PHASE_N, tick_limit)
		phase_note(KERNEL_PHASE_N, n_start)
		// U
		var/u_start = TICK_USAGE
		guarded(KERNEL_PHASE_U, TYPE_PROC_REF(/datum/controller/kernel, run_urgent), min(tick_limit, TICK_USAGE + sched.pass_avail * KERNEL_URGENT_SHARE))
		phase_note(KERNEL_PHASE_U, u_start)
		// D
		var/d_start = TICK_USAGE
		guarded(KERNEL_PHASE_D, TYPE_PROC_REF(/datum/controller/kernel, run_deadline_phase), tick_limit)
		phase_note(KERNEL_PHASE_D, d_start)
		// P
		var/p_start = TICK_USAGE
		guarded(KERNEL_PHASE_P, TYPE_PROC_REF(/datum/controller/kernel, run_lane_phase), tick_limit)
		phase_note(KERNEL_PHASE_P, p_start)
		// R
		var/r_start = TICK_USAGE
		guarded(KERNEL_PHASE_R, TYPE_PROC_REF(/datum/controller/kernel, run_leftover_phase), tick_limit)
		phase_note(KERNEL_PHASE_R, r_start)
		var/pass_ms = TICK_USAGE_TO_MS(tick_start)
		sched.pass_end()
		note_behaviours(pass_ms)
		run_audits()

	// G: whatever is left, with a floor once a second.
	var/g_start = TICK_USAGE
	var/g_limit = tick_limit
	// ALLOW(sys_world_time_expiry): the kernel clock: compares the scheduler own timestamps, not an entity expiry
	if(world.time - last_g_floor >= KERNEL_GARBAGE_FLOOR_PERIOD)
		g_limit = max(tick_limit, TICK_USAGE + KERNEL_GARBAGE_FLOOR)
		// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
		last_g_floor = world.time
	run_hosted_phase(hosted_g, g_limit, init_stage)
	guarded(KERNEL_PHASE_G, TYPE_PROC_REF(/datum/controller/kernel, run_work_phase), KERNEL_PHASE_G, g_limit)
	phase_note(KERNEL_PHASE_G, g_start)

	last_tick_ms = TICK_USAGE_TO_MS(tick_start)
	Master.current_ticklimit = saved_limit

/// TRUE when the scheduler passes run this tick: SSbehaviours (the scheduler's boot) has initialized for the loop's
/// stage, and the runlevel is one it ran in. The rule SSbehaviours' own MC entry had.
/datum/controller/kernel/proc/sched_runs(init_stage)
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	if(!SSbehaviours || SSbehaviours.init_stage > init_stage || !SSbehaviours.can_fire)
		return FALSE
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	return !!(SSbehaviours.runlevels & Master.current_runlevel)

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

/// Runs one phase proc behind a guard: a runtime in a phase is logged and counted, and the tick goes on.
/datum/controller/kernel/proc/guarded(phase, proc_ref, ...)
	try
		call(src, proc_ref)(arglist(args.Copy(3)))
	catch(var/exception/e)
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

/// D: the deadline wheel, then deadline-phase work items in what is left of the deadline share.
/datum/controller/kernel/proc/run_deadline_phase(tick_limit)
	sched.pass_deadlines(tick_limit)
	work_run_phase(KERNEL_PHASE_D, min(tick_limit, sched.pass_start + sched.pass_avail * OM_DEADLINE_SHARE + sched.pass_avail * KERNEL_URGENT_SHARE))

/// P: the borrow pass, then each lane: the scheduler's share of it, then that lane's work items.
/datum/controller/kernel/proc/run_lane_phase(tick_limit)
	sched.pass_borrow(tick_limit)
	for(var/lane in 1 to OM_LANE_COUNT)
		sched.pass_lane(lane, tick_limit)
		if(!kernel_admit_lane(lane))
			continue
		var/lane_limit = min(TICK_USAGE + sched.pass_avail * sched.lane_share[lane], tick_limit)
		work_run_phase(KERNEL_PHASE_P, lane_limit, lane)

/// R: leftovers.
/datum/controller/kernel/proc/run_leftover_phase(tick_limit)
	sched.pass_leftovers(tick_limit)
	work_run_phase(KERNEL_PHASE_R, tick_limit)

/// The work items of a phase that has no scheduler piece of its own (K, N, G).
/datum/controller/kernel/proc/run_work_phase(phase, tick_limit)
	work_run_phase(phase, tick_limit)

// ---------------------------------------------------------------- hosted subsystems

/// Fires each host service that is due, in list order: its own runlevels, its own timing, a paused run resumed.
/// A ticker (input, verb_manager) gets the whole phase limit; a service on a longer wait (tgui, dbcore, profiler,
/// garbage) gets KERNEL_HOST_SLICE of a tick at most, so a slow host cannot starve the phases after it.
/datum/controller/kernel/proc/run_hosted_phase(list/subsystems, tick_limit, init_stage)
	for(var/datum/controller/subsystem/SS as anything in subsystems)
		if(!SS || !SS.can_fire || SS.init_stage > init_stage)
			continue
		if(!(SS.runlevels & (1 << (Master.current_runlevel - 1))))
			continue
		var/paused = (SS.state == SS_PAUSED)
		// ALLOW(sys_world_time_expiry): the kernel clock: compares the scheduler own timestamps, not an entity expiry
		if(!paused && SS.next_fire > world.time)
			continue
		if(TICK_USAGE >= tick_limit && SS.state != SS_PAUSED && !(SS.flags & SS_TICKER))
			continue
		var/limit = tick_limit
		if(!(SS.flags & SS_TICKER))
			limit = min(tick_limit, TICK_USAGE + KERNEL_HOST_SLICE)
		run_hosted(SS, limit, paused)

/datum/controller/kernel/proc/run_hosted(datum/controller/subsystem/SS, tick_limit, paused)
	Master.current_ticklimit = tick_limit
	SS.queued_time = world.time // ALLOW(sys_world_time_write): kernel-hosted subsystem timing
	if(!paused)
		SS.current_run_slices = 0
	SS.current_run_slices++
	SS.state = SS_RUNNING
	var/used = TICK_USAGE
	var/state = SS_IDLE
	try
		state = SS.ignite(paused)
	catch(var/exception/e) // ALLOW(silent_catch): report_fault() reports it through dq_report_caught() unless a test expects faults
		phase_faults++
		report_fault(e, "host service [SS.name] runtime: [e] ([e.file]:[e.line])")
	used = max(TICK_USAGE - used, 0)
	LAZYSET(Master.perf_tick_breakdown, SS.name, (LAZYACCESS(Master.perf_tick_breakdown, SS.name) || 0) + used)
	if(used > Master.perf_tick_top_usage)
		Master.perf_tick_top_usage = used
		Master.perf_tick_top_name = SS.name
	if(Master.use_rolling_usage)
		SS.prune_rolling_usage()
		SS.rolling_usage += list(DS2TICKS(world.time), used)
	if(state == SS_RUNNING)
		state = SS_IDLE
	SS.state = state
	if(state == SS_PAUSED)
		// A paused run resumes on the kernel's next pass.
		SS.paused_ticks++
		SS.paused_tick_usage += used
		return
	used += SS.paused_tick_usage
	SS.ticks = MC_AVERAGE(SS.ticks, SS.paused_ticks)
	SS.tick_usage = SS.tick_usage ? MC_AVERAGE_FAST(SS.tick_usage, used) : used
	SS.cost = SS.cost ? MC_AVERAGE_FAST(SS.cost, TICK_DELTA_TO_MS(used)) : TICK_DELTA_TO_MS(used)
	SS.active_cost_last = TICK_DELTA_TO_MS(used)
	SS.paused_ticks = 0
	SS.paused_tick_usage = 0
	// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
	SS.last_fire = world.time
	SS.times_fired++
	SS.update_nextfire()
	SS.queued_time = 0
	SS.tick_overrun = max(0, MC_AVG_FAST_UP_SLOW_DOWN(SS.tick_overrun, used - max(tick_limit - TICK_USAGE + used, 0)))

// ---------------------------------------------------------------- SSbehaviours' remaining duties

/// SSbehaviours stopped firing; its profiler and benchmark counters are fed from the kernel's scheduler passes.
/datum/controller/kernel/proc/note_behaviours(pass_ms)
	if(!SSbehaviours)
		return
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.bench_ms += pass_ms
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.last_done = sched.pass_done
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.cost = SSbehaviours.cost ? MC_AVERAGE_FAST(SSbehaviours.cost, pass_ms) : pass_ms
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.times_fired++
	// ALLOW(sys_world_time_write, system_boundary): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry; the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	SSbehaviours.last_fire = world.time

/// The pipeline missed-wake audit (pipeline.dm), on its interval.
/datum/controller/kernel/proc/run_audits()
	// ALLOW(system_boundary): the kernel is the scheduler core SSbehaviours delegates to: it reads and updates that subsystem own fire bookkeeping
	if(!SSbehaviours || !SSbehaviours.audit_due())
		return
	om_pipeline_audit(sched, OM_AUDIT_PARKED_SAMPLE, OM_AUDIT_AWAKE_SAMPLE)
	om_sleeper_audit(64, TRUE)

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
