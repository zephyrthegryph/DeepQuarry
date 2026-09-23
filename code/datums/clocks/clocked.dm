/**
 * # Clocked objects (doc/medical_frameworks.md §1.2, §1.3)
 *
 * An atom with time-based state settles it against the clock of its nearest enclosing holder
 * that provides one (holder_clock(): walks loc upwards; a turf ends it with the world clock).
 * State is settled on read: clock_settle() integrates from the last settle to now through the
 * type's on_settle(seconds). Thresholds are events: after a settle, clock_next_threshold()
 * schedules the next crossing in clock time with clock_schedule_in().
 *
 * **Move hook (J5, not landed yet).** The ledger's move hook calls clock_on_moved() on the
 * moving thing and on each hooked descendant after the move; that is the whole clock side of
 * the hook. The gate is clock_move_hooked(). Until J5 lands, nothing calls clock_on_moved()
 * automatically, so a clocked thing keeps the clock it bound to until it is next rebound by
 * hand (clock_rebind()) or its clock is deleted.
 */

/atom/movable
	/// TRUE for types that carry clocked state (a static per-type answer; see is_clocked()).
	var/clocked = FALSE
	/// The clock this object's time-based state is settled against, or null when unbound.
	var/tmp/datum/clock/bound_clock
	/// bound_clock's reading at the last settle.
	var/tmp/clock_settled_at = 0
	/// Pending events this object scheduled on bound_clock: one /datum/clock_event, or a lazy
	/// list when several.
	var/tmp/clock_handles

/// TRUE when this type carries clocked state (on_settle() / thresholds). The generated
/// split-invariance test iterates the types whose `clocked` is TRUE.
/atom/movable/proc/is_clocked()
	return clocked

/// Holders that provide a clock override this (providers.dm; the body clock in K2).
/atom/proc/provided_clock()
	return null

/// Nearest enclosing clock provider's clock: walks loc upwards; a turf or nullspace ends the
/// walk with the world clock.
/atom/movable/proc/holder_clock()
	var/atom/A = loc
	while(A && !isturf(A))
		var/datum/clock/C = A.provided_clock()
		if(C)
			return C
		A = A.loc
	return GLOB.world_clock

/// Binds to the holder clock if unbound (Initialize, or the first read).
/atom/movable/proc/clock_bind()
	if(bound_clock)
		return bound_clock
	clock_attach(holder_clock())
	clock_next_threshold()
	return bound_clock

/// Low level: bind to `C` and start settling from its current reading.
/atom/movable/proc/clock_attach(datum/clock/C)
	PRIVATE_PROC(TRUE)
	bound_clock = C
	clock_settled_at = C.now()
	LAZYOR(C.bound, src)
	C.tie(src)

/// Unbinds from the clock, dropping this object's pending events on it.
/atom/movable/proc/clock_unbind()
	var/datum/clock/C = bound_clock
	if(!C)
		return
	for(var/datum/clock_event/E as anything in clock_handle_list())
		C.cancel(E)
	LAZYREMOVE(C.bound, src)
	bound_clock = null
	clock_handles = null

/// Integrates to now: calls on_settle() with the clock seconds since the last settle. Returns
/// those seconds (0 on the first read, which only binds).
/atom/movable/proc/clock_settle()
	if(!bound_clock)
		clock_bind()
		return 0
	var/now = bound_clock.now()
	var/seconds = now - clock_settled_at
	if(seconds <= 0)
		return 0
	clock_settled_at = now
	on_settle(seconds)
	return seconds

/// Type hook: advance state by `seconds` at the current rates. Must be exact for any split of
/// the interval (settle(a) + settle(b) == settle(a + b)): use closed forms, not Euler steps.
/atom/movable/proc/on_settle(seconds)
	return

/// Type hook: after a settle, schedule the next threshold with clock_schedule_in(). Default none.
/atom/movable/proc/clock_next_threshold()
	return

/// Settles at the old clock, then binds to `new_clock` (null: resolve from loc). Pending
/// events move with the object and keep their remaining clock seconds, so no threshold needs
/// recomputing: they were stored in clock time.
/atom/movable/proc/clock_rebind(datum/clock/new_clock)
	if(!new_clock)
		new_clock = holder_clock()
	var/datum/clock/old_clock = bound_clock
	if(old_clock == new_clock)
		return
	if(!old_clock)
		clock_bind()
		return
	clock_settle()
	var/old_now = old_clock.now()
	// list(remaining clock seconds, proc_ref, arg) for each of our events on the old clock.
	var/list/carried
	for(var/datum/clock_event/E as anything in clock_handle_list())
		if(E.clock == old_clock)
			LAZYADD(carried, list(list(max(E.at_clock - old_now, 0), E.proc_ref, E.arg)))
	clock_unbind()
	clock_attach(new_clock)
	for(var/list/entry as anything in carried)
		clock_schedule_in(entry[1], entry[2], entry[3])
	if(GLOB.clock_trace)
		log_runtime("CLOCK: [type] rebound from [old_clock.debug_name()] to [new_clock.debug_name()] with [LAZYLEN(carried)] events")

/// Schedules src.proc_ref(arg) `clock_seconds` from now on the bound clock. Returns the handle.
/atom/movable/proc/clock_schedule_in(clock_seconds, proc_ref, arg)
	if(!bound_clock)
		clock_bind()
	var/datum/clock_event/E = bound_clock.schedule_in(src, clock_seconds, proc_ref, arg)
	clock_prune_handles()
	if(!clock_handles)
		clock_handles = E
	else if(islist(clock_handles))
		var/list/handles = clock_handles
		handles += E
	else
		clock_handles = list(clock_handles, E)
	return E

/// Cancels one of this object's events.
/atom/movable/proc/clock_cancel(datum/clock_event/E)
	if(!E)
		return FALSE
	. = bound_clock?.cancel(E)
	clock_prune_handles()

/// This object's pending handles as a list (copy).
/atom/movable/proc/clock_handle_list()
	if(!clock_handles)
		return list()
	if(islist(clock_handles))
		var/list/handles = clock_handles
		return handles.Copy()
	return list(clock_handles)

/// Drops fired and cancelled handles.
/atom/movable/proc/clock_prune_handles()
	var/list/live
	for(var/datum/clock_event/E as anything in clock_handle_list())
		if(E.clock)
			LAZYADD(live, E)
	if(!live)
		clock_handles = null
	else if(length(live) == 1)
		clock_handles = live[1]
	else
		clock_handles = live

/// The J5 move-hook gate: TRUE when a move must call clock_on_moved() on this thing.
/atom/movable/proc/clock_move_hooked()
	return bound_clock || own_clock

/**
 * The clock side of the ledger move hook (J5). Called after this thing moved (right after the
 * ledger's note_enter, before Exited/Uncrossed), for the moving thing and every hooked
 * descendant. Must not move, qdel or sleep. A provider's clock recomposes on its new holder
 * clock; a bound thing rebinds when its holder clock changed. Descendants under a provider
 * need no call: their holder clock is still the provider's.
 */
/atom/movable/proc/clock_on_moved()
	if(own_clock)
		own_clock.set_parent(holder_clock())
	if(bound_clock)
		var/datum/clock/C = holder_clock()
		if(C != bound_clock)
			clock_rebind(C)
