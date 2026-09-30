/// The work-item engine: registration, the phase graph and the run loop (doc/rewrite/kernel.md sec 1.2).

/// Adds `W` for `owner_type`. The same key again replaces the older item. Marks the phase graph stale.
/datum/controller/kernel/proc/register_work(owner_type, datum/work_item/W)
	W.owner_type = owner_type
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
		var/list/watching = work_by_members[W.members]
		if(!watching)
			watching = work_by_members[W.members] = list()
		watching += W
	if(ispath(W.members, /datum/capability) && !cap_wanted[W.members])
		cap_wanted[W.members] = TRUE
		kernel_backfill_members(W.members)
	work_dirty = TRUE
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
	work_errors = list()
	phase_items = new /list(KERNEL_PHASE_COUNT)
	var/list/missing = list()
	var/list/deps = list()
	var/list/scheduled = list()
	for(var/datum/work_item/W as anything in work_all)
		if(!W.event)
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
	for(var/datum/work_item/W as anything in ordered)
		if(W.phase >= KERNEL_PHASE_K && W.phase <= KERNEL_PHASE_G)
			phase_items[W.phase] += W

/// Runs the due items of `phase`, in order. `lane` (phase P) restricts the run to that lane. `limit_abs` is the
/// absolute tick usage to stay under; an item that runs out of budget mid-sweep resumes next pass. Returns TRUE
/// when nothing was left unfinished. `now` is the time due dates are compared against (tests inject it).
/datum/controller/kernel/proc/work_run_phase(phase, limit_abs, lane = 0, now = world.time)
	. = TRUE
	for(var/datum/work_item/W as anything in items_of_phase(phase))
		if(lane && W.lane != lane)
			continue
		if(!run_item(W, limit_abs, now))
			. = FALSE
			if(TICK_USAGE >= limit_abs)
				return

/// Runs one item if it is due and its latency class is admitted. Returns FALSE when it ran out of budget with work left.
/datum/controller/kernel/proc/run_item(datum/work_item/W, limit_abs, now = world.time)
	if(W.parked)
		return TRUE
	if(!W.cursor && !W.yielded && W.next_run > now)
		return TRUE
	if(!kernel_latency().admit(W.latency_class(), W.key))
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
	try
		if(W.members)
			done = run_item_members(W, owner, limit_abs, now)
		else
			done = run_item_once(W, owner, now)
		W.consecutive_faults = 0
	catch(var/exception/e)
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
	var/ms = TICK_USAGE_TO_MS(started)
	W.total_ms += ms
	W.current_ms += ms
	if(done)
		W.runs++
		W.cost = W.cost ? MC_AVERAGE_FAST(W.cost, W.current_ms) : W.current_ms
		W.current_ms = 0
	return done

/// A memberless item: one call. Returns TRUE when done (a yield is not done).
/datum/controller/kernel/proc/run_item_once(datum/work_item/W, datum/owner, now)
	if(W.token_current(null, now) && !W.yielded)
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
		if(TICK_USAGE > limit_abs && i <= length(members))
			W.cursor = i
			return FALSE
	W.next_run = now + W.interval
	return TRUE
