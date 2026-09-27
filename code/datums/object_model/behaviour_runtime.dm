// Sparse activation and dynamically granted behaviours. An entity pays for
// this state only after explicitly entering the object model.
/datum/object_model/behaviour_runtime
	var/datum/entity
	var/datum/object_model/archetype/archetype
	var/list/active = list() // behaviour path -> TRUE
	var/list/periodic_entries = list() // behaviour path -> schedule entry
	var/list/observer_tokens = list() // behaviour path -> active subscription tokens
	var/list/static_watches = list() // declared watch path -> owned watch
	var/list/registry_services // registered service endpoints, only allocated for declarations
	var/watches_refreshing = FALSE
	var/watches_pending = FALSE
	var/list/grants = list() // behaviour path -> grant token list
	var/list/states = list() // behaviour path -> current finite state
	/// Only scheduled behaviours that have been woken or reached their deadline.
	var/list/run_pending
	/// Per-behaviour wall-clock enqueue time and cause; allocated only on wake.
	var/list/run_pending_since
	var/list/run_pending_reason
	/// Optional work units reported by the current on_run, reset each dispatch.
	var/list/run_work_units
	/// Work held by a schedule-set suspension; replayed once on resume.
	var/list/run_suspended
	/// Behaviour path -> absolute world.time. One DM timer serves all deadlines.
	var/list/run_due
	/// Behaviour path -> due virtual time, retained while its clock is stopped.
	var/list/run_clock_due
	var/list/run_last
	/// Shared-cadence membership by behaviour path; ordinary frames need no native token.
	var/list/run_shared
	/// One native reactor-wheel token for this entity's earliest deadline.
	var/run_timer_id
	var/run_timer_at = 0
	var/run_queued = FALSE
	var/run_audit_registered = FALSE
	var/releasing = FALSE
	var/refreshing = FALSE
	var/refresh_pending = FALSE

/datum/object_model/behaviour_runtime/proc/start(datum/new_entity)
	entity = new_entity
	archetype = om_archetype_for(entity.type, entity)
	if(!archetype)
		return FALSE
	for(var/registry_path in archetype.registries)
		var/datum/object_model/registry/service = om_registry(registry_path)
		if(!service || !istype(entity, service.accepts))
			return FALSE
		service.add(entity)
		LAZYADD(registry_services, service)
	if(!refresh_static_watches())
		return FALSE
	refresh()
	return TRUE

/datum/object_model/behaviour_runtime/proc/refresh_static_watches()
	if(watches_refreshing)
		watches_pending = TRUE
		return TRUE
	watches_refreshing = TRUE
	var/iterations = 0
	while(TRUE)
		watches_pending = FALSE
		for(var/path in archetype.watches)
			var/datum/object_model/watch_definition/D = om_watch_definition(path)
			var/datum/desired_subject = D.relation_path ? om_first_linked(entity, D.relation_path) : entity
			if(om_is_dying(desired_subject))
				desired_subject = null
			var/datum/object_model/watch/W = static_watches[path]
			if(W && !QDELETED(W) && W.subject == desired_subject)
				continue
			var/previous_truth = W && !QDELETED(W) ? W.truth : FALSE
			if(W && !QDELETED(W))
				qdel(W)
			static_watches -= path
			if(desired_subject && !QDELETED(desired_subject))
				W = om_watch(entity, desired_subject, D, path)
				if(!W)
					watches_refreshing = FALSE
					return FALSE
				static_watches[path] = W
			if(D.relation_path)
				var/next_truth = W && !QDELETED(W) ? W.truth : FALSE
				if(next_truth != previous_truth)
					D.changed(entity, desired_subject, archetype.watches[path], next_truth, previous_truth)
		if(!watches_pending)
			break
		if(++iterations >= 16)
			CRASH("object-model declared watch rebinding did not settle for [entity.type]")
	watches_refreshing = FALSE
	return TRUE

/datum/object_model/behaviour_runtime/proc/has_behaviour(path)
	return (path in archetype.behaviours) || length(grants[path])

/datum/object_model/behaviour_runtime/proc/config_for(path)
	var/list/config = archetype.behaviours[path]
	return config || list()

/datum/object_model/behaviour_runtime/proc/refresh(changed_event, changed_mask = 0)
	if(releasing || !entity || om_is_dying(entity))
		return
	if(refreshing)
		refresh_pending = TRUE
		return
	refreshing = TRUE
	for(var/pass in 1 to 16)
		refresh_pending = FALSE
		refresh_once(changed_event, changed_mask)
		if(!refresh_pending || releasing || !entity || om_is_dying(entity))
			break
		changed_event = null // Nested changes require a full readiness pass.
		changed_mask = 0
	refreshing = FALSE
	if(refresh_pending && !releasing && entity && !om_is_dying(entity))
		CRASH("object-model behaviour refresh did not settle for [entity.type]")

/datum/object_model/behaviour_runtime/proc/refresh_once(changed_event, changed_mask)
	if(releasing || !entity || om_is_dying(entity))
		return
	refresh_static_watches()
	if(releasing || !entity || om_is_dying(entity))
		return
	var/relations_ready = om_required_relations_ready(entity, archetype)
	var/list/candidates = length(grants) ? archetype.behaviour_order.Copy() : archetype.behaviour_order
	for(var/path in grants)
		if(!(path in candidates))
			candidates += path
	for(var/path in candidates)
		if(releasing || !entity || om_is_dying(entity))
			return
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(changed_event && !active[path] && !om_behaviour_depends_on(B, changed_event))
			continue
		if(changed_mask && !om_behaviour_depends_on_change(B, changed_mask))
			continue
		var/ready = relations_ready
		for(var/requirement_path in B.requires)
			var/datum/object_model/requirement/R = om_requirement(requirement_path)
			if(R.why_not(entity))
				ready = FALSE
				break
		if(ready && !active[path])
			active[path] = TRUE
			if(B.states && isnull(states[path]))
				states[path] = B.initial_state
				B.on_state_enter(entity, B.initial_state, null, config_for(path))
				if(releasing || !entity || om_is_dying(entity))
					return
			B.on_activate(entity, config_for(path))
			if(releasing || !entity || om_is_dying(entity))
				return
			var/list/subscriptions = om_subscribe_plan(entity, B.om_observer_plan())
			if(length(subscriptions))
				observer_tokens[path] = subscriptions
			if(B.period > 0)
				periodic_entries[path] = om_periodic(entity, B.period, B)
			if(B.run_shared_cadence)
				join_shared(path)
			if(B.run_change_mask || length(B.run_owned_inputs) || length(B.run_relation_inputs) || length(B.run_events) || (B.run_period > 0 && !B.run_shared_cadence))
				wake(path)
		else if(!ready && active[path])
			deactivate(path, relations_ready ? "requirements lost" : "required relation lost")

/// Queue one behaviour without waking unrelated behaviours on the same entity.
/datum/object_model/behaviour_runtime/proc/wake(path, reason = "change")
	if(releasing || !entity || !active[path])
		return FALSE
	var/datum/object_model/behaviour/B = om_behaviour(path)
	if(B.run_set && om_set_suspended(entity, B.run_set))
		if(!run_suspended)
			run_suspended = list()
		run_suspended[path] = TRUE
		return TRUE
	if(B.run_shared_cadence)
		join_shared(path)
	if(!run_audit_registered)
		SSreactor.register_scheduled_runtime(src)
		run_audit_registered = TRUE
	if(!run_pending)
		run_pending = list()
	run_pending[path] = TRUE
	if(!run_pending_since)
		run_pending_since = list()
	if(isnull(run_pending_since[path]))
		run_pending_since[path] = world.time
	if(!run_pending_reason)
		run_pending_reason = list()
	if(isnull(run_pending_reason[path]))
		run_pending_reason[path] = reason
	// A change wake must not postpone an existing virtual-time deadline.
	if(!B.run_clock && !B.preserve_deadline_on_wake && run_due && (path in run_due))
		run_due -= path
		arm_next_run()
	SSreactor.queue_behaviour_runtime(src)
	return TRUE

/datum/object_model/behaviour_runtime/proc/join_shared(path)
	if(releasing || !active[path] || run_shared?[path])
		return
	if(!run_shared)
		run_shared = list()
	SSreactor.register_shared_runtime(src, path)
	run_shared[path] = TRUE

/datum/object_model/behaviour_runtime/proc/leave_shared(path)
	if(!run_shared?[path])
		return
	run_shared -= path
	SSreactor.unregister_shared_runtime(src, path)

/datum/object_model/behaviour_runtime/proc/run_shared_frame(path, scheduled_at = null)
	if(releasing || !entity || om_is_dying(entity) || !active[path] || !run_shared?[path])
		return
	// Native deadlines and producer wakes dispatch after shared slices. Give an
	// already-due owner event the frame, regardless of which lane runs first.
	if(run_pending?[path] || (run_due?[path] && run_due[path] <= world.time) || run_last?[path] == world.time)
		return
	run_one(path, scheduled_at, "shared cadence")

/// Selection metadata for the pending-runtime queue. Work inside a runtime
/// retains archetype declaration order, including before/after dependencies.
/datum/object_model/behaviour_runtime/proc/queue_priority()
	var/best = 0
	for(var/path in run_pending)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(B && B.run_priority > best)
			best = B.run_priority
	return best

/datum/object_model/behaviour_runtime/proc/queue_oldest_at()
	var/oldest
	for(var/path in run_pending)
		var/queued = run_pending_since?[path]
		if(!isnull(queued) && (isnull(oldest) || queued < oldest))
			oldest = queued
	return isnull(oldest) ? world.time : oldest

/// A behaviour with integrated or batched work may report how much virtual
/// work it completed without forcing one callback per simulated step.
/datum/object_model/behaviour_runtime/proc/report_work_units(path, units)
	if(!active[path] || !isnum(units) || units < 0)
		return FALSE
	if(!run_work_units)
		run_work_units = list()
	run_work_units[path] = units
	return TRUE

/datum/object_model/behaviour_runtime/proc/wake_changed(mask)
	if(releasing || !entity || !archetype || !mask)
		return
	var/bit = 1
	for(var/index in 1 to 24)
		if(mask & bit)
			for(var/path in archetype.run_change_handlers[index])
				wake(path, "tracked change")
		bit *= 2
	for(var/path in grants)
		if(path in archetype.behaviours)
			continue
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(B.run_change_mask & mask)
			wake(path, "tracked change")

/// Called by the shared DM executor. A wake during on_run queues a later pass.
/datum/object_model/behaviour_runtime/proc/run_ready()
	if(releasing || !entity || om_is_dying(entity) || !length(run_pending))
		return
	var/list/ready = run_pending
	run_pending = null
	for(var/path in archetype.behaviour_order)
		if(!ready[path] || !active[path])
			continue
		run_one(path)
		if(releasing || !entity || om_is_dying(entity))
			return
	for(var/path in grants)
		if((path in archetype.behaviours) || !ready[path] || !active[path])
			continue
		run_one(path)
		if(releasing || !entity || om_is_dying(entity))
			return

/datum/object_model/behaviour_runtime/proc/run_one(path, scheduled_at = null, dispatch_reason = null)
	var/datum/object_model/behaviour/B = om_behaviour(path)
	if(B.run_set && om_set_suspended(entity, B.run_set))
		if(!run_suspended)
			run_suspended = list()
		run_suspended[path] = TRUE
		return
	var/queued_at = run_pending_since?[path]
	var/queued_reason = run_pending_reason?[path]
	if(run_pending_since)
		run_pending_since -= path
	if(run_pending_reason)
		run_pending_reason -= path
	var/datum/object_model/clock_state/C = B.run_clock ? clock_for(B.run_clock) : null
	var/now = C ? C.settle() : world.time
	var/previous = run_last?[path]
	var/seconds = !isnull(previous) ? max(0, (now - previous) / (1 SECONDS)) : 0
	if(!run_last)
		run_last = list()
	run_last[path] = now
	var/start_at = world.time
	var/profile_start = TICK_USAGE_REAL
	SSreactor.prepare_scheduler_tick()
	var/observed_child_before = SSreactor.scheduler_tick_child_ms
	var/entity_type = entity.type
	if(run_work_units)
		run_work_units -= path
	var/delay = B.on_run(entity, seconds, config_for(path))
	var/elapsed_ticks = TICK_USAGE_REAL - profile_start
	var/elapsed_ms = TICK_DELTA_TO_MS(elapsed_ticks)
	var/exclusive_ms = max(elapsed_ms - (SSreactor.scheduler_tick_child_ms - observed_child_before), 0)
	var/work_units = run_work_units && (path in run_work_units) ? run_work_units[path] : 1
	if(run_work_units)
		run_work_units -= path
	SSreactor.observe_dispatch("behaviour", B.type, entity_type, isnull(scheduled_at) ? queued_at : scheduled_at, start_at, exclusive_ms, dispatch_reason || queued_reason || "deadline", work_units, B.run_priority)
	SSreactor.record_scheduled_cost(B.type, elapsed_ticks)
	if(releasing || !entity || om_is_dying(entity) || !active[path])
		return
	if(isnull(delay))
		delay = B.run_period
	if(!isnum(delay) || delay < 0)
		CRASH("[B.type] returned an invalid scheduled delay [delay]")
	if(B.run_shared_cadence)
		if(delay == B.run_period)
			join_shared(path)
			return
		leave_shared(path)
		if(!delay)
			return
	if(C && delay <= 0)
		if(run_clock_due)
			run_clock_due -= path
		if(run_due)
			run_due -= path
		arm_next_run()
	if(delay > 0 && !run_pending?[path])
		if(C)
			if(!run_clock_due)
				run_clock_due = list()
			var/new_due = C.settle() + delay
			var/previous_due = run_clock_due[path]
			run_clock_due[path] = isnull(previous_due) ? new_due : min(previous_due, new_due)
			reschedule_clock_path(path, C)
		else
			if(!run_due)
				run_due = list()
			var/previous_due = run_due[path]
			var/new_due = world.time + delay
			run_due[path] = B.preserve_deadline_on_wake && !isnull(previous_due) ? min(previous_due, new_due) : new_due
		arm_next_run()

/// Request an exact world-time deadline for an active scheduled behaviour.
/datum/object_model/behaviour_runtime/proc/schedule_at(path, due)
	if(releasing || !active[path] || !isnum(due) || due < world.time)
		return FALSE
	if(!run_due)
		run_due = list()
	var/previous = run_due[path]
	run_due[path] = isnull(previous) ? due : min(previous, due)
	arm_next_run()
	return TRUE

/datum/object_model/behaviour_runtime/proc/cancel_deadline(path)
	if(!run_due || !(path in run_due))
		return
	run_due -= path
	arm_next_run()

/datum/object_model/behaviour_runtime/proc/clock_for(domain)
	if(!ispath(domain, /datum/object_model/clock_domain))
		CRASH("invalid object-model clock domain [domain]")
	return om_clock_for(entity, domain)

/datum/object_model/behaviour_runtime/proc/reschedule_clock_path(path, datum/object_model/clock_state/C)
	var/due = run_clock_due?[path]
	if(isnull(due))
		return
	if(!run_due)
		run_due = list()
	if(C.rate <= 0)
		run_due -= path
		return
	var/remaining = max(0, due - C.settle())
	run_due[path] = world.time + max(world.tick_lag, remaining / C.rate)

/datum/object_model/behaviour_runtime/proc/clock_rate_changed(domain)
	if(releasing || !entity || om_is_dying(entity))
		return
	var/datum/object_model/clock_state/C = entity.om_state?.clock_states?[domain]
	if(!C)
		return
	for(var/path in run_clock_due)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(B.run_clock == domain)
			reschedule_clock_path(path, C)
	arm_next_run()

/datum/object_model/behaviour_runtime/proc/set_suspended(set_path)
	if(releasing)
		return
	if(!run_suspended)
		run_suspended = list()
	for(var/path in active)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(B.run_set != set_path)
			continue
		leave_shared(path)
		run_suspended[path] = TRUE
		if(run_pending)
			run_pending -= path
		if(run_pending_since)
			run_pending_since -= path
		if(run_pending_reason)
			run_pending_reason -= path
		if(run_due)
			run_due -= path
		if(run_clock_due)
			run_clock_due -= path
	arm_next_run()

/datum/object_model/behaviour_runtime/proc/set_resumed(set_path)
	if(releasing || !entity || om_is_dying(entity))
		return
	if(!length(run_suspended))
		return
	for(var/path in run_suspended.Copy())
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(B.run_set != set_path || !active[path])
			continue
		run_suspended -= path
		if(run_pending_since)
			run_pending_since -= path
		if(run_pending_reason)
			run_pending_reason -= path
		if(!run_last)
			run_last = list()
		run_last[path] = B.run_clock ? clock_for(B.run_clock).settle() : world.time
		wake(path, "resumed")

/// Keep one timer at the earliest outstanding per-behaviour deadline.
/datum/object_model/behaviour_runtime/proc/arm_next_run()
	var/earliest = 0
	for(var/path in run_due)
		var/due = run_due[path]
		if(!earliest || due < earliest)
			earliest = due
	if(run_timer_id && run_timer_at == earliest)
		return
	if(run_timer_id)
		REACT_CANCEL(src, run_timer_id)
		run_timer_id = null
	run_timer_at = earliest
	if(earliest && !releasing)
		run_timer_id = REACT_AT(src, max(world.time + world.tick_lag, earliest))

/datum/object_model/behaviour_runtime/on_react(reason, source, source_kind)
	if(!(reason & REACT_REASON_TIMER) || source != run_timer_id)
		return
	run_timer_fired()

/datum/object_model/behaviour_runtime/proc/run_timer_fired()
	run_timer_id = null
	run_timer_at = 0
	if(releasing || !entity || om_is_dying(entity))
		return
	if(run_due)
		for(var/path in run_due.Copy())
			var/due = run_due[path]
			if(due <= world.time)
				run_due -= path
				if(run_clock_due)
					run_clock_due -= path
				if(active[path])
					if(!run_pending)
						run_pending = list()
					run_pending[path] = TRUE
					if(!run_pending_since)
						run_pending_since = list()
					if(isnull(run_pending_since[path]))
						run_pending_since[path] = due
					if(!run_pending_reason)
						run_pending_reason = list()
					if(isnull(run_pending_reason[path]))
						run_pending_reason[path] = "deadline"
					SSreactor.queue_behaviour_runtime(src)
	arm_next_run()

/datum/object_model/behaviour_runtime/react_sleep_violation()
	if(releasing || !entity || om_is_dying(entity))
		return null
	for(var/path in active)
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(!B.audit_sleep || run_pending?[path] || (run_due?[path] && run_due[path] <= world.time))
			continue
		var/violation = B.sleep_violation(entity, config_for(path))
		if(violation)
			return "[B.type]: [violation]"
	return null

/datum/object_model/behaviour_runtime/proc/deactivate(path, reason)
	if(!active[path])
		return
	leave_shared(path)
	active -= path
	if(run_pending)
		run_pending -= path
	if(run_pending_since)
		run_pending_since -= path
	if(run_pending_reason)
		run_pending_reason -= path
	if(run_due && (path in run_due))
		run_due -= path
		arm_next_run()
	if(run_clock_due)
		run_clock_due -= path
	if(run_suspended)
		run_suspended -= path
	if(run_last)
		run_last -= path
	var/list/subscriptions = observer_tokens[path]
	if(subscriptions)
		for(var/datum/object_model/subscription/S as anything in subscriptions)
			qdel(S)
		observer_tokens -= path
	var/datum/object_model/schedule_entry/entry = periodic_entries[path]
	if(entry)
		qdel(entry)
		periodic_entries -= path
	var/datum/object_model/behaviour/B = om_behaviour(path)
	B.on_deactivate(entity, config_for(path), reason)

/datum/object_model/behaviour_runtime/proc/grant(path, datum/source)
	if(releasing || !entity || !source || om_is_dying(source) || !om_behaviour(path))
		return FALSE
	var/list/tokens = grants[path]
	if(tokens)
		for(var/datum/object_model/behaviour_grant/existing as anything in tokens)
			if(existing.source == source)
				return TRUE
	var/datum/object_model/behaviour_grant/G = new
	G.runtime = src
	G.source = source
	G.behaviour_path = path
	if(!om_link(entity, /datum/object_model/relation/grant_holder, G) || !om_link(G, /datum/object_model/relation/grant_source, source))
		qdel(G)
		return FALSE
	if(!tokens)
		tokens = list()
		grants[path] = tokens
	tokens += G
	refresh()
	om_changed(entity, "grants")
	om_emit(entity, /datum/object_model/event/grant_changed, path, source, TRUE, !!active[path])
	return TRUE

/datum/object_model/behaviour_runtime/proc/revoke(path, datum/source)
	var/list/tokens = grants[path]
	for(var/datum/object_model/behaviour_grant/G as anything in tokens)
		if(G.source == source)
			qdel(G)
			return TRUE
	return FALSE

/datum/object_model/behaviour_runtime/proc/grant_token_lost(datum/object_model/behaviour_grant/G)
	var/path = G.behaviour_path
	var/list/tokens = grants[path]
	if(!tokens || !(G in tokens))
		return
	tokens -= G
	var/datum/grant_source = G.source
	if(!length(tokens))
		grants -= path
		if(archetype && !(path in archetype.behaviours))
			deactivate(path, "grant revoked")
			states -= path
	if(!releasing && entity && !om_is_dying(entity))
		om_changed(entity, "grants")
		om_emit(entity, /datum/object_model/event/grant_changed, path, grant_source, FALSE, !!active[path])

/datum/object_model/behaviour_runtime/proc/release()
	if(releasing)
		return
	releasing = TRUE
	for(var/path in run_shared?.Copy())
		leave_shared(path)
	if(run_audit_registered)
		SSreactor.unregister_scheduled_runtime(src)
		run_audit_registered = FALSE
	if(run_timer_id)
		REACT_CANCEL(src, run_timer_id)
		run_timer_id = null
	if(reactor_id)
		REACT_CLEAR(src)
	run_pending = null
	run_pending_since = null
	run_pending_reason = null
	run_work_units = null
	run_suspended = null
	run_due = null
	run_clock_due = null
	run_last = null
	if(entity)
		for(var/datum/object_model/registry/service in registry_services)
			if(!QDELETED(service))
				service.remove(entity)
	registry_services = null
	for(var/path in static_watches)
		var/datum/object_model/watch/W = static_watches[path]
		qdel(W)
	static_watches.Cut()
	for(var/path in active.Copy())
		deactivate(path, "entity destroyed")
	var/list/all_tokens = list()
	for(var/path in grants)
		all_tokens += grants[path]
	for(var/datum/object_model/behaviour_grant/G as anything in all_tokens)
		qdel(G)
	grants.Cut()
	states.Cut()
	observer_tokens.Cut()
	entity = null
	archetype = null

/datum/object_model/behaviour_runtime/Destroy(force = FALSE)
	release()
	return ..()

/proc/om_behaviour_depends_on(datum/object_model/behaviour/B, event_path)
	for(var/requirement_path in B.requires)
		var/datum/object_model/requirement/R = om_requirement(requirement_path)
		if(R.depends_on && (event_path in R.depends_on))
			return TRUE
	return FALSE

/// Unknown requirements retain the broad refresh semantics of legacy writes.
/proc/om_behaviour_depends_on_change(datum/object_model/behaviour/B, mask)
	for(var/requirement_path in B.requires)
		var/datum/object_model/requirement/R = om_requirement(requirement_path)
		if(!R.change_mask || (R.change_mask & mask))
			return TRUE
	return FALSE

/proc/om_behaviour_start(datum/entity)
	var/datum/object_model/state/state = om_state_for(entity)
	if(!state)
		return null
	if(state.behaviour_runtime)
		return state.behaviour_runtime
	var/datum/object_model/behaviour_runtime/R = new
	state.behaviour_runtime = R
	if(!R.start(entity))
		state.behaviour_runtime = null
		qdel(R)
		return null
	return R

/proc/om_behaviour_refresh(datum/entity, changed_event, changed_mask = 0)
	entity?.om_state?.behaviour_runtime?.refresh(changed_event, changed_mask)

/// Explicitly wake one scheduled behaviour, including after an external event.
/proc/om_behaviour_wake(datum/entity, path, reason = "explicit wake")
	return entity?.om_state?.behaviour_runtime?.wake(path, reason)

/// Called from on_run after integrated or batched work. Zero means the frame
/// only checked state; omitted calls count as one unit.
/proc/om_behaviour_report_work(datum/entity, path, units)
	return entity?.om_state?.behaviour_runtime?.report_work_units(path, units)

/proc/om_behaviour_due_at(datum/entity, path, due)
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(entity)
	return R?.schedule_at(path, due)

/// Static dispatch keeps event-triggered work compositional and coalesced.
/proc/om_behaviour_wake_event(datum/entity, event_path, datum/object_model/archetype/A)
	var/list/paths = A?.run_event_handlers?[event_path]
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	if(!length(paths) && !R)
		return
	if(!R && length(paths))
		R = om_behaviour_start(entity)
	if(!R)
		return
	for(var/path in paths)
		R.wake(path, "event [event_path]")
	for(var/path in R.grants)
		if(path in A.behaviours)
			continue
		var/datum/object_model/behaviour/B = om_behaviour(path)
		if(event_path in B.run_events)
			R.wake(path, "event [event_path]")

/proc/om_behaviour_grant(datum/entity, path, datum/source)
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(entity)
	return R?.grant(path, source)

/proc/om_behaviour_revoke(datum/entity, path, datum/source)
	return entity?.om_state?.behaviour_runtime?.revoke(path, source)

/// Snapshot grant sources without exposing the runtime's mutable token index.
/proc/om_behaviour_grant_sources(datum/entity, path)
	var/list/sources = list()
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	var/list/tokens = R?.grants[path]
	for(var/datum/object_model/behaviour_grant/G as anything in tokens)
		if(G.source && !QDELETED(G.source))
			sources += G.source
	return sources

/proc/om_behaviour_has_grant(datum/entity, path, datum/source)
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	var/list/tokens = R?.grants[path]
	for(var/datum/object_model/behaviour_grant/G as anything in tokens)
		if(G.source == source)
			return TRUE
	return FALSE

/// Returns FALSE for an undeclared or disallowed transition.
/proc/om_behaviour_transition(datum/entity, path, new_state)
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	if(!R || !R.active[path])
		return FALSE
	var/datum/object_model/behaviour/B = om_behaviour(path)
	if(!B.states || !(new_state in B.states))
		return FALSE
	var/old_state = R.states[path]
	if(old_state == new_state)
		return TRUE
	var/list/allowed = B.transitions?[old_state]
	if(!allowed || !(new_state in allowed))
		return FALSE
	B.on_state_exit(entity, old_state, new_state, R.config_for(path))
	R.states[path] = new_state
	B.on_state_enter(entity, new_state, old_state, R.config_for(path))
	return TRUE

/proc/om_behaviour_release(datum/entity)
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	if(R)
		entity.om_state.behaviour_runtime = null
		qdel(R)

/datum/object_model/behaviour/om_on_periodic(datum/entity, seconds)
	var/datum/object_model/behaviour_runtime/R = entity?.om_state?.behaviour_runtime
	if(!R || !R.active[type])
		return
	R.refresh()
	if(R.active[type])
		on_tick(entity, R.config_for(type))
