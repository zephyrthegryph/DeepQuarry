/**
 * # Clocks (doc/medical_frameworks.md §1.2, §1.3, §1.6)
 *
 * A clock maps world time to clock time: `now = base_clock + (world.time - base_world) * speed`,
 * in clock seconds. Its speed changes only at discrete events (stasis starting, a freezer losing
 * power, a holder moving into a slower holder), and it rebases at every change.
 *
 * `speed = own_speed * parent.speed`: a holder clock inside another holder composes with it. A
 * speed change on a parent rebases and re-speeds its children.
 *
 * Events are stored in clock time, so a speed change never reschedules an object: the clock just
 * turns its earliest pending event into a new REACT_AT. A clock at speed 0 holds no reactor
 * token and its events stay parked.
 *
 * Handlers are SIGNAL_HANDLER-style: they must not sleep (slow work goes to INVOKE_ASYNC). They
 * may schedule or cancel events; on_react() loops until nothing is due.
 */

/// Boot-time world clock (speed 1, never deleted).
GLOBAL_DATUM_INIT(world_clock, /datum/clock/world, new)
/// Log CLOCK: lines for rebinds, schedules and fires (speed changes and late events always log).
GLOBAL_VAR_INIT(clock_trace, FALSE)

/// One pending event. The event itself is the handle: a fired or cancelled event has a null
/// `clock`, so a stale handle never cancels anything, and it drops its target so a caller that
/// keeps an old handle keeps nothing alive.
/datum/clock_event
	/// The clock this event is pending on, or null once it fired or was cancelled.
	var/datum/clock/clock
	/// Clock time (clock seconds) the event is due.
	var/at_clock = 0
	var/datum/target
	var/proc_ref
	var/arg

/datum/clock
	var/kind = CLOCK_KIND_HOLDER
	/// Clock seconds per world second, after composing with the parent clock.
	var/speed = 1
	/// This clock's own factor (a freezer's 0.1); speed = own_speed * parent.speed.
	var/own_speed = 1
	/// world.time at the last rebase (deciseconds).
	var/base_world = 0
	/// Clock reading at the last rebase (clock seconds).
	var/base_clock = 0
	/// The atom or body that provides this clock. It nulls this and qdels the clock in
	/// clock_teardown().
	var/datum/provider
	var/datum/clock/parent
	/// Lazy: child clocks composed on this one.
	var/list/children
	/// Lazy: pending /datum/clock_event.
	var/list/events
	/// Lazy: atoms bound to this clock (their settled state is read against it).
	var/list/bound
	/// Lazy: every datum whose clock_ties holds this clock (the reverse index, so neither side
	/// keeps a deleted one).
	var/list/tied
	/// The pending event the reactor token was set for.
	var/datum/clock_event/earliest
	/// The single REACT_AT token for `earliest`, or null.
	var/react_token
	/// world.time that token is due (for the late-fire log).
	var/react_due

/datum/clock/New(kind = CLOCK_KIND_HOLDER, own_speed = 1, datum/clock/parent, datum/provider)
	..()
	src.kind = kind
	src.own_speed = max(own_speed, 0)
	src.provider = provider
	base_world = parent ? parent.world_now() : world.time
	speed = src.own_speed
	if(parent)
		set_parent(parent)

/datum/clock/Destroy(force)
	var/datum/clock/fallback = parent || GLOB.world_clock
	if(fallback == src)
		fallback = null
	// Child clocks compose on our parent instead.
	for(var/datum/clock/child as anything in children?.Copy())
		child.set_parent(fallback)
	// Bound atoms rebind to the parent; their events move with them (clock_rebind()).
	for(var/atom/movable/AM as anything in bound?.Copy())
		if(fallback)
			AM.clock_rebind(fallback)
		else
			AM.clock_unbind()
	// Events for non-atom targets move too, keeping their remaining clock seconds.
	for(var/datum/clock_event/E as anything in events?.Copy())
		var/datum/target = E.target
		if(fallback && !QDELETED(target))
			fallback.schedule_in(target, max(E.at_clock - now(), 0), E.proc_ref, E.arg)
		drop_event(E)
	for(var/datum/D as anything in tied)
		LAZYREMOVE(D.clock_ties, src)
	tied = null
	events = null
	bound = null
	children = null
	earliest = null
	if(react_token)
		REACT_CANCEL(src, react_token)
		react_token = null
	if(parent)
		LAZYREMOVE(parent.children, src)
		parent = null
	provider = null
	return ..()

/// The world time (deciseconds) this clock reads: world.time, or its root clock's time source.
/// Only test clocks (dq_clock_tests.dm) override it; nothing global is ever shifted.
/datum/clock/proc/world_now()
	return parent ? parent.world_now() : world.time

/// Clock seconds now.
/datum/clock/proc/now()
	return base_clock + CLOCK_SECONDS(world_now() - base_world) * speed

/// Fold elapsed time into the base: base_* := now.
/datum/clock/proc/rebase()
	var/t = world_now()
	base_clock += CLOCK_SECONDS(t - base_world) * speed
	base_world = t

/// Changes this clock's own factor: rebase, recompose children, rearm.
/datum/clock/proc/set_own_speed(new_speed, reason)
	new_speed = max(new_speed, 0)
	if(new_speed == own_speed)
		return
	var/old_speed = speed
	rebase_tree()
	own_speed = new_speed
	respeed_tree()
	log_runtime("CLOCK: [debug_name()] speed [old_speed] -> [speed] ([reason || "unspecified"]); [LAZYLEN(events)] events, [LAZYLEN(bound)] bound, [LAZYLEN(children)] children")

/// Composes this clock on `new_parent` (null: none, speed = own_speed).
/datum/clock/proc/set_parent(datum/clock/new_parent)
	if(new_parent == parent || new_parent == src)
		return
	// A clock never composes on its own descendant.
	for(var/datum/clock/C = new_parent; C; C = C.parent)
		if(C == src)
			CRASH("CLOCK: [debug_name()] refused parent [new_parent.debug_name()], which composes on it")
	rebase_tree()
	if(parent)
		LAZYREMOVE(parent.children, src)
	parent = new_parent
	if(parent)
		LAZYADD(parent.children, src)
	// Folded at the old time source above; restart the bases on the new one.
	restart_base_tree()
	respeed_tree()
	if(GLOB.clock_trace)
		log_runtime("CLOCK: [debug_name()] composed on [parent ? parent.debug_name() : "nothing"], speed [speed]")

/datum/clock/proc/restart_base_tree()
	base_world = world_now()
	for(var/datum/clock/child as anything in children)
		child.restart_base_tree()

/datum/clock/proc/rebase_tree()
	rebase()
	for(var/datum/clock/child as anything in children)
		child.rebase_tree()

/// After rebase_tree(): recompute composed speeds top-down and rearm each clock.
/datum/clock/proc/respeed_tree()
	speed = own_speed * (parent ? parent.speed : 1)
	rearm(TRUE)
	for(var/datum/clock/child as anything in children)
		child.respeed_tree()

/// world.time at which this clock reads `at_clock`, or null when stopped.
/datum/clock/proc/world_time_of(at_clock)
	if(speed <= 0)
		return null
	return base_world + (at_clock - base_clock) / speed * (1 SECONDS)

/// Schedules target.proc_ref(arg) at clock time `at_clock`. Returns the event (the handle).
/datum/clock/proc/schedule(datum/target, at_clock, proc_ref, arg)
	if(QDELETED(target))
		CRASH("CLOCK: [debug_name()] refused an event for a deleted [target?.type]")
	var/datum/clock_event/E = new
	E.clock = src
	E.at_clock = at_clock
	E.target = target
	E.proc_ref = proc_ref
	E.arg = arg
	LAZYADD(events, E)
	tie(target)
	if(GLOB.clock_trace)
		log_runtime("CLOCK: [debug_name()] scheduled [proc_ref] on [target.type] at [at_clock] (now [now()])")
	if(!earliest || at_clock < earliest.at_clock)
		earliest = E
		rearm(TRUE)
	return E

/// Schedules target.proc_ref(arg) `clock_seconds` from now on this clock.
/datum/clock/proc/schedule_in(datum/target, clock_seconds, proc_ref, arg)
	return schedule(target, now() + max(clock_seconds, 0), proc_ref, arg)

/// Cancels one event. TRUE if it was pending here.
/datum/clock/proc/cancel(datum/clock_event/E)
	if(!istype(E) || E.clock != src)
		return FALSE
	var/was_earliest = (E == earliest)
	drop_event(E)
	if(was_earliest)
		rearm()
	return TRUE

/// Cancels every event that targets `target`.
/datum/clock/proc/cancel_all(datum/target)
	var/rearm_needed = FALSE
	for(var/datum/clock_event/E as anything in events?.Copy())
		if(E.target != target)
			continue
		if(E == earliest)
			rearm_needed = TRUE
		drop_event(E)
	if(rearm_needed)
		rearm()

/// Removes an event without rearming. The caller rearms if it was the earliest.
/datum/clock/proc/drop_event(datum/clock_event/E)
	LAZYREMOVE(events, E)
	if(E == earliest)
		earliest = null
	E.clock = null
	E.target = null
	E.arg = null

/// Records that `D` holds a tie to this clock (an event, a binding, or providing it).
/datum/clock/proc/tie(datum/D)
	LAZYOR(D.clock_ties, src)
	LAZYOR(tied, D)

/// Called by clock_teardown() when a tied datum is deleted: drop its events, its binding, and
/// this clock itself if the datum provides it.
/datum/clock/proc/release(datum/D)
	LAZYREMOVE(tied, D)
	cancel_all(D)
	if(bound && (D in bound))
		LAZYREMOVE(bound, D)
	if(provider == D)
		provider = null
		qdel(src)

/// Points the reactor at the earliest pending event (one REACT_AT per clock). At speed 0 or
/// with nothing pending the token is dropped and events park. `force` rearms even when the
/// earliest event is unchanged (the speed or base moved).
/datum/clock/proc/rearm(force = FALSE)
	if(QDELING(src))
		return
	var/datum/clock_event/first
	for(var/datum/clock_event/E as anything in events)
		if(!first || E.at_clock < first.at_clock)
			first = E
	if(!force && first == earliest && react_token)
		return
	earliest = first
	if(react_token)
		REACT_CANCEL(src, react_token)
		react_token = null
	react_due = null
	if(!first || speed <= 0)
		return
	// A deadline in the past fires on the next reactor step (reactor.md §3).
	react_due = world_time_of(first.at_clock)
	// The reactor runs on world.time; a test clock's time source is offset from it.
	var/due = world.time + (react_due - world_now())
	react_token = REACT_AT(src, due)

/datum/clock/on_react(reason, source, source_kind)
	react_token = null
	fire_due()

/// Fires every due event in clock-time order, then rearms. Handlers may schedule or cancel.
/datum/clock/proc/fire_due()
	var/fired = 0
	while(LAZYLEN(events))
		var/datum/clock_event/first
		for(var/datum/clock_event/E as anything in events)
			if(!first || E.at_clock < first.at_clock)
				first = E
		if(first.at_clock > now())
			break
		var/datum/target = first.target
		var/proc_ref = first.proc_ref
		var/arg = first.arg
		var/at_clock = first.at_clock
		drop_event(first)
		fired++
		if(QDELETED(target))
			log_runtime("CLOCK: [debug_name()] skipped [proc_ref] for a deleted [target?.type]: its Destroy() did not cancel it")
			continue
		if(!isnull(react_due) && speed > 0)
			var/late = world_now() - world_time_of(at_clock)
			if(late > world.tick_lag * 2)
				log_runtime("CLOCK: [debug_name()] fired [proc_ref] on [target.type] [late / (1 SECONDS)]s late")
		if(GLOB.clock_trace)
			log_runtime("CLOCK: [debug_name()] fired [proc_ref] on [target.type] (due [at_clock], now [now()])")
		if(isnull(arg))
			call(target, proc_ref)()
		else
			call(target, proc_ref)(arg)
		if(QDELETED(src))
			return fired
	rearm(TRUE)
	return fired

/datum/clock/proc/debug_name()
	return "[type] (kind [kind], [provider ? "[provider.type]" : "no provider"])"

/// The world clock: never deleted, never composed.
/datum/clock/world
	kind = CLOCK_KIND_WORLD

/datum/clock/world/set_parent(datum/clock/new_parent)
	return

/datum/clock/world/set_own_speed(new_speed, reason)
	return

/datum/clock/world/Destroy(force)
	if(!force)
		return QDEL_HINT_LETMELIVE
	return ..()

// --- Teardown ------------------------------------------------------------------------------

/datum
	/// Lazy: clocks this datum is tied to (events targeting it, its binding, or the clock it
	/// provides). Read only by clock_teardown().
	var/tmp/list/clock_ties

/**
 * The one clock teardown entry point: cancels every clock event that targets `D`, unbinds it
 * from its clock, and deletes the clock it provides (its bound contents rebind to the parent).
 *
 * Integration point: the other session's framework-owned destruction calls this for every
 * deleted datum with `clock_ties`. Until that lands, the base /datum/Destroy() calls it.
 */
/proc/clock_teardown(datum/D)
	var/list/ties = D.clock_ties
	if(!ties)
		return
	D.clock_ties = null
	if(ismovable(D))
		var/atom/movable/AM = D
		AM.bound_clock = null
		AM.clock_handles = null
		AM.own_clock = null
	for(var/datum/clock/C as anything in ties)
		if(!QDELETED(C))
			C.release(D)
