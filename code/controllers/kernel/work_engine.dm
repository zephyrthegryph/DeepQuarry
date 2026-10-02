/// The work-item engine: registration, the phase graph and the run loop (doc/rewrite/kernel.md sec 1.2).

/// Adds `W` for `owner_type`. The same key again replaces the older item. Marks the phase graph stale.
/datum/controller/kernel/proc/register_work(owner_type, datum/work_item/W)
	W.owner_type = owner_type
	W.test_owned = !isnull(test_now)
	if(!W.handler && !istype(W, /datum/work_item/stage))
		CRASH("kernel_register_work: a work item for [owner_type] has no handler")
	W.name ||= "[W.handler]"
	W.key = W.item_key(owner_type)
	if(istype(W, /datum/work_item/stage))
		var/datum/work_item/stage/S = W
		W.key = "[owner_type]:stage:[S.stage_type]"
	var/datum/work_item/old = work_by_key[W.key]
	if(old)
		work_all -= old
		work_by_owner[owner_type] -= old
		if(old.members)
			work_by_members[old.members] -= old
	work_all += W
	var/list/mine = work_by_owner[owner_type]
	if(!mine)
		mine = work_by_owner[owner_type] = list()
	mine += W
	work_by_key[W.key] = W
	if(W.members)
		W.member_list = member_list_for(W.members)
		var/list/watching = work_by_members[W.members]
		if(!watching)
			watching = work_by_members[W.members] = list()
		watching += W
	if(ispath(W.members, /datum/capability) && !cap_wanted[W.members])
		cap_wanted[W.members] = TRUE
		kernel_backfill_members(W.members)
	work_dirty = TRUE
	test_dirty = TRUE
	return W

/// Drops every item `owner_type` registered.
/datum/controller/kernel/proc/unregister_work(owner_type)
	for(var/datum/work_item/W as anything in work_by_owner[owner_type])
		work_all -= W
		work_by_key -= W.key
		if(W.members)
			work_by_members[W.members] -= W
	work_by_owner -= owner_type
	work_dirty = TRUE
	test_dirty = TRUE

/// The items of `phase` in dependency order. Rebuilds and revalidates the graph when items changed.
/datum/controller/kernel/proc/items_of_phase(phase)
	if(work_dirty || !phase_items)
		rebuild_work_graph()
	return phase_items[phase]

/// `member` left membership key `key`: the items that sweep the key forget its execution token.
/datum/controller/kernel/proc/member_left(key, datum/member)
	for(var/datum/work_item/W as anything in work_by_members[key])
		W.forget(member)

/// Resolves every `after` edge, validates the graph with the same validator the boot DAG uses (graph_validate),
/// and orders each phase. Edges to an earlier phase are satisfied already; an edge to a later phase, a target
/// that names nothing, and a cycle are recorded in work_errors. Items caught in a cycle still run, in
/// registration order after the ordered ones: a bad graph must not silence gameplay, it must be caught by the test.
/datum/controller/kernel/proc/rebuild_work_graph()
	work_dirty = FALSE
	work_due_reset()
	work_errors = list()
	phase_items = new /list(KERNEL_PHASE_COUNT)
	var/list/missing = list()
	var/list/deps = list()
	var/list/scheduled = list()
	// The live graph holds the live items and a test's graph the test-owned ones (test_enter() builds that one).
	for(var/datum/work_item/W as anything in work_all)
		if(!W.event && W.test_owned == test_stepping)
			scheduled += W
	for(var/datum/work_item/W as anything in scheduled)
		var/list/resolved = list()
		if(W.phase < KERNEL_PHASE_K || W.phase > KERNEL_PHASE_G || W.phase == KERNEL_PHASE_U)
			missing += "[W.key]: phase [W.phase] is not a phase work items run in"
		for(var/target in W.after)
			var/list/found = list()
			if(ispath(target))
				found = work_by_owner[target]
			else
				var/datum/work_item/T = work_by_key["[target]"]
				if(T)
					found = list(T)
			if(!length(found))
				missing += "[W.key]: after [target], which names no work item"
				continue
			for(var/datum/work_item/T as anything in found)
				if(T == W || T.event)
					continue
				if(T.phase > W.phase)
					missing += "[W.key]: after [T.key], which runs later (phase [phase_letter(T.phase)] after [phase_letter(W.phase)])"
					continue
				if(T.phase == W.phase)
					resolved += T
		deps[W] = resolved
	var/datum/graph_check/G = graph_validate(scheduled, deps, missing)
	work_errors = G.errors
	var/list/ordered = G.order
	var/list/leftover = scheduled - ordered
	ordered += leftover
	for(var/i in 1 to KERNEL_PHASE_COUNT)
		phase_items[i] = list()
	phase_lane_items = new /list(OM_LANE_COUNT)
	for(var/lane in 1 to OM_LANE_COUNT)
		phase_lane_items[lane] = list()
	for(var/datum/work_item/W as anything in ordered)
		if(W.phase >= KERNEL_PHASE_K && W.phase <= KERNEL_PHASE_G)
			phase_items[W.phase] += W
			if(W.phase == KERNEL_PHASE_P && W.lane >= 1 && W.lane <= OM_LANE_COUNT)
				phase_lane_items[W.lane] += W

/// Runs the due items of `phase`, in order. `lane` (phase P) restricts the run to that lane. `limit_abs` is the
/// absolute tick usage to stay under; an item that runs out of budget mid-sweep resumes next pass. Returns TRUE
/// when nothing was left unfinished. `now` is the time due dates are compared against (tests inject it).
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/work_run_phase(phase, limit_abs, lane = 0, now = world.time)
	. = TRUE
	if(work_dirty || !phase_items)
		rebuild_work_graph()
	// Nothing in this list can be due before phase_due (the last walk's earliest due date): no walk.
	var/due_key = lane ? KERNEL_PHASE_COUNT + lane : phase
	if(now < phase_due[due_key])
		return
	// Phase P runs once per lane: each pass walks only that lane's items (rebuild_work_graph() files them).
	var/list/items = (lane && phase == KERNEL_PHASE_P) ? phase_lane_items[lane] : phase_items[phase]
	var/soonest = INFINITY
	for(var/datum/work_item/W as anything in items)
		if(lane && W.lane != lane)
			continue
		if(W.parked)
			continue
		// Not due (run_item() asks the same first): most items most ticks, so they cost no call.
		if(!W.cursor && !W.yielded && W.next_run > now)
			if(W.next_run < soonest)
				soonest = W.next_run
			continue
		// A member sweep with nobody to sweep (most cadences most ticks: projectiles, throwing, ...) is closed
		// here, as run_item_members() and run_item_spread() close it, without a call into the engine.
		if(W.members && !W.member_list)
			W.member_list = member_list_for(W.members)
		if(W.member_list && !W.cursor && !length(W.member_list))
			W.next_run = now + W.interval
			W.runs++
			if(W.next_run < soonest)
				soonest = W.next_run
			continue
		if(!run_item(W, limit_abs, now))
			. = FALSE
			// Out of the lane's share with work left: phase R offers it the tick's leftovers (run_leftover_phase()).
			// A spread sweep is paced on purpose and waits for its next pass.
			if(lane && !W.spread)
				LAZYOR(p_carry, W)
			if(TICK_USAGE >= limit_abs)
				phase_due[due_key] = 0 // the walk stopped early: the next pass walks again
				return
		// Its next due date after the run (an open sweep or a yield: the next pass).
		if(W.parked)
			continue
		var/next = (W.cursor || W.yielded) ? now : W.next_run
		if(next < soonest)
			soonest = next
	phase_due[due_key] = soonest

/// Forgets every phase list's earliest due date, so each is walked again on its next pass: an item was woken, added
/// or rescheduled from outside the walk.
/datum/controller/kernel/proc/work_due_reset()
	// In place: the live graph and a test's graph each keep their list, and both forget.
	if(length(phase_due) != KERNEL_PHASE_COUNT + OM_LANE_COUNT)
		phase_due = new /list(KERNEL_PHASE_COUNT + OM_LANE_COUNT)
	if(length(test_due) != KERNEL_PHASE_COUNT + OM_LANE_COUNT)
		test_due = new /list(KERNEL_PHASE_COUNT + OM_LANE_COUNT)
	for(var/i in 1 to length(phase_due))
		phase_due[i] = 0
		test_due[i] = 0

/// Runs one item if it is due and its latency class is admitted. Returns FALSE when it ran out of budget with work left.
// ALLOW(sys_world_time_write): the kernel clock: a per-tick timestamp of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_item(datum/work_item/W, limit_abs, now = world.time)
	if(W.parked)
		return TRUE
	if(!W.cursor && !W.yielded && W.next_run > now)
		return TRUE
	if(!W.admitted_now())
		// Not in this item's run levels: it is due again next pass, and its sweep (if one was open) resumes then.
		return TRUE
	// The latency gate refuses only while shedding: one var read most ticks instead of three calls.
	var/datum/kernel_latency/latency = latency_state || (latency_state = kernel_latency())
	if(latency.shedding && !latency.admit(W.latency_class(), W.key))
		return TRUE
	if(TICK_USAGE >= limit_abs)
		return FALSE
	var/datum/owner = W.owner()
	if(!owner || QDELETED(owner))
		return TRUE
	if(W.budget)
		limit_abs = min(limit_abs, TICK_USAGE + W.budget)
	var/started = TICK_USAGE
	var/done = TRUE
	// A fire() body (system.dm fire_step) and CHECK_TICK read the tick budget from here.
	var/saved_ticklimit = Master.current_ticklimit
	Master.current_ticklimit = limit_abs
	try
		done = W.sweep(src, owner, limit_abs, now)
		W.consecutive_faults = 0
	catch(var/exception/e) // ALLOW(silent_catch): the fault is counted per work item and escalated by consecutive_faults
		W.faults++
		W.consecutive_faults++
		W.cursor = 0
		W.yielded = FALSE
		W.next_run = now + max(W.interval, world.tick_lag)
		var/msg = "work item [W.key] runtime: [e] ([e.file]:[e.line])"
		report_fault(e, msg)
		if(W.consecutive_faults >= KERNEL_FAULT_PARK)
			W.parked = TRUE
			var/park_msg = "Kernel: work item [W.key] parked after [W.consecutive_faults] faults in a row."
			log_world(park_msg)
			message_admins(park_msg)
	Master.current_ticklimit = saved_ticklimit
	var/ms = TICK_USAGE_TO_MS(started)
	W.total_ms += ms
	W.current_ms += ms
	// A spread sweep's slices add up to one run: it is counted when the sweep closes.
	if(done && !(W.spread && W.cursor))
		W.runs++
		W.cost = W.cost ? MC_AVERAGE_FAST(W.cost, W.current_ms) : W.current_ms
		W.current_ms = 0
	return done

/// A memberless item: one call. Returns TRUE when done (a yield is not done).
/datum/controller/kernel/proc/run_item_once(datum/work_item/W, datum/owner, now)
	// Only an urgent-capable item can have been run ahead of its cadence (kernel_urgent()); the rest skip the token read.
	if(W.urgent && !W.yielded && W.token_current(null, now))
		// An urgent run already covered this instant.
		W.next_run = now + W.interval
		return TRUE
	if(!W.runnable(owner, null))
		W.skips++
		W.next_run = now + W.interval
		W.yielded = FALSE
		return TRUE
	var/dt = W.take_dt(null, now)
	var/result = W.perform(owner, null, dt)
	return read_result(W, result, now)

/// Reads a memberless step result. Returns TRUE unless the step yielded.
/datum/controller/kernel/proc/read_result(datum/work_item/W, result, now)
	W.yielded = FALSE
	switch(result)
		if(PROCESS_KILL, STEP_PARK)
			W.parked = TRUE
			W.next_run = now + W.interval
			return TRUE
		if(STEP_YIELD)
			W.yielded = TRUE
			return FALSE
	W.next_run = now + W.interval
	return TRUE

/// A member item: one sweep over the members, resumed where it stopped when it ran out of budget. A member that
/// already ran at this instant (an urgent run: its execution token is current) is skipped, so the elapsed time
/// it covered is applied once.
/datum/controller/kernel/proc/run_item_members(datum/work_item/W, datum/owner, limit_abs, now)
	var/list/members = members_of(W.members)
	var/i = W.cursor || 1
	W.cursor = 0
	while(i <= length(members))
		var/datum/M = members[i]
		i++
		if(QDELETED(M))
			continue
		if(!W.token_current(M, now) && W.runnable(owner, M))
			var/dt = W.take_dt(M, now)
			if(dt > 0)
				W.perform(owner, M, dt)
				W.member_runs++
		// A member that left during its own step (or one the step removed) took a swap-remove: the last member now
		// sits in its slot. Look at that slot again so the moved member is not skipped this sweep.
		if(i - 1 > length(members) || members[i - 1] != M)
			i--
		if(TICK_USAGE > limit_abs && i <= length(members))
			W.cursor = i
			return FALSE
	W.next_run = now + W.interval
	return TRUE

/**
 * A spread member item: one sweep over the members per interval, taken a share at a time. Each pass runs the members
 * that are due by the end of this tick (the share of the interval that has elapsed since the sweep began), so every
 * member keeps its phase and a large set costs a slice per tick, not a spike once per interval. A sweep that fell behind
 * (a stalled tick, a budget cut) catches up by at most KERNEL_SPREAD_CATCHUP passes' share per pass. Returns FALSE only
 * when it ran out of budget; a pass that ran its share leaves the sweep open (W.cursor) for the next pass.
 */
// The kernel clock: a per-sweep timestamp of the scheduler itself, not a per-entity expiry
/datum/controller/kernel/proc/run_item_spread(datum/work_item/W, datum/owner, limit_abs, now)
	var/list/members = members_of(W.members)
	var/count = length(members)
	if(!W.cursor)
		if(!count)
			W.next_run = now + W.interval
			return TRUE
		W.cursor = 1
		W.sweep_began = now
	var/interval = max(W.interval, world.tick_lag)
	var/share = CEILING(count * world.tick_lag / interval, 1)
	var/due = CEILING(count * min(1, (now - W.sweep_began + world.tick_lag) / interval), 1)
	var/target = min(due, W.cursor - 1 + share * KERNEL_SPREAD_CATCHUP, count)
	var/i = W.cursor
	while(i <= target && i <= length(members))
		var/datum/M = members[i]
		i++
		if(QDELETED(M))
			continue
		if(!W.token_current(M, now) && W.runnable(owner, M))
			var/dt = W.take_dt(M, now)
			if(dt > 0)
				W.perform(owner, M, dt)
				W.member_runs++
		// A member that left during its step took a swap-remove: look at its slot again.
		if(i - 1 > length(members) || members[i - 1] != M)
			i--
			target = min(target, length(members))
		if(TICK_USAGE > limit_abs && i <= target)
			W.cursor = i
			return FALSE
	if(i <= length(members))
		// This pass's share is done; the rest of the sweep is due on later passes.
		W.cursor = i
		W.next_run = now
		return TRUE
	// The sweep is closed: the next begins one interval after this one began (its phase), or now if it ran late.
	W.cursor = 0
	W.next_run = max(W.sweep_began + interval, now)
	W.sweep_began = 0
	return TRUE
