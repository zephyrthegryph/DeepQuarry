// C7: vore on slots (doc/rewrite/containment.md §9).
//
// A belly stays an atom, because a prey mob needs an atom as its loc, and its
// interior is a sealed slot (C1/C2): prey go in with move_into(), leave with
// slot_remove() and move between bellies with slot_transfer(). The ledger is
// made on first use, so an empty belly has none.
//
// Scheduling. There is no belly subsystem. A belly runs its digestion cycle on
// SSreactor only while something is inside it (or its owner previews it):
// belly_reschedule() declares one REACT_EVERY when the first thing enters and
// cancels it when the last one leaves. An empty belly that makes liquid from
// nutrition sleeps on a REACT_AT timer for its next batch instead. An empty,
// idle belly holds no reactor state and runs no code.
//
// Rates. Every mode's effect is a rate per BELLY_BASELINE_TICK scaled by the
// real time since the belly's last cycle (the reactor passes the seconds), so a
// late or a turbo cycle changes nothing but granularity: the same totals over
// the same time.

/obj/belly
	/// The belly's REACT_EVERY token while it is occupied, else null.
	var/tmp/cycle_token
	/// The period that token was declared with.
	var/tmp/cycle_period
	/// REACT_AT token for the next liquid batch of an empty, generating belly.
	var/tmp/liquid_timer

/obj/belly/slot_def_types()
	var/static/list/types = list(/datum/slot_def/belly_interior)
	return types

/// The inside of a belly: sealed (its own air and temperature), and it reaches the
/// mobs inside it. Outside effects don't pass the predator's body into it; the
/// belly's own modes are what act on its contents.
/datum/slot_def/belly_interior
	id = BELLY_SLOT_INTERIOR
	name = "belly"
	is_default = TRUE
	exposure = SLOT_EXPOSURE_SEALED
	reaches_mobs = TRUE
	drop_policy = SLOT_DROP_SPILL
	heat_transmission = 0
	radiation_transmission = 1
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// Seconds per cycle for this belly: the baseline, or a third of it in turbo mode.
/obj/belly/proc/belly_cycle_period()
	return (speedy_mob_processing || (mode_flags & DM_FLAG_TURBOMODE)) ? BELLY_TURBO_TICK : BELLY_BASELINE_TICK

/// Whether this belly has anything to do every cycle.
/obj/belly/proc/belly_occupied()
	if(!isliving(owner) || QDELETED(src))
		return FALSE
	return length(contents) || owner.previewing_belly == src

/// Whether this belly makes liquid from its owner's nutrition over time.
/obj/belly/proc/belly_generates_liquid()
	return isliving(owner) && show_liquids && reagentbellymode && (reagent_mode_flags & DM_FLAG_REAGENTSNUTRI) && !isnewplayer(owner)

/// Starts, retunes or stops this belly's reactor work to match what it holds.
/// Call it whenever contents, turbo mode, liquid settings or the preview change.
/obj/belly/proc/belly_reschedule()
	if(QDELETED(src))
		return
	if(belly_occupied())
		if(liquid_timer)
			REACT_CANCEL(src, liquid_timer)
			liquid_timer = null
		var/period = belly_cycle_period()
		if(cycle_token && cycle_period != period)
			REACT_CANCEL(src, cycle_token)
			cycle_token = null
		if(!cycle_token)
			cycle_token = REACT_EVERY(src, period, "occupied belly: digestion, emotes and sounds each cycle; stops when empty")
			cycle_period = period
		return
	if(cycle_token)
		REACT_CANCEL(src, cycle_token)
		cycle_token = null
		cycle_period = null
		belly_surrounding = null
	if(belly_generates_liquid())
		if(!liquid_timer)
			var/cycles_left = max(gen_time + 1 - gen_interval, 1)
			liquid_timer = REACT_AT(src, world.time + cycles_left * belly_cycle_period())
	else if(liquid_timer)
		REACT_CANCEL(src, liquid_timer)
		liquid_timer = null

/// Occupied: one digestion cycle for the real time since the last one.
/obj/belly/react_every(seconds, token)
	if(token != cycle_token)
		REACT_CANCEL(src, token)
		return
	belly_cycle(seconds)
	if(!QDELETED(src) && !belly_occupied())
		belly_reschedule()

/// Empty and generating: the next liquid batch is due.
/obj/belly/on_react(reason, source, source_kind)
	if(source != liquid_timer)
		return
	liquid_timer = null
	if(belly_occupied())
		belly_reschedule()
		return
	gen_interval = max(gen_interval, gen_time)
	HandleBellyReagents()
	belly_reschedule()

/// Asleep means no cycle while empty and not previewed.
/obj/belly/react_sleep_violation()
	if(!cycle_token && belly_occupied())
		return "[src] of [owner] holds [length(contents)] things but has no cycle"
	if(cycle_token && !belly_occupied())
		return "[src] of [owner] is empty but still cycles"
	return null

// ---- Moves: the ledger transaction API, with the old guarantees ----

/// Puts `thing` into this belly's interior slot. TRUE if it is inside.
/obj/belly/proc/belly_insert(atom/movable/thing, mob/actor)
	if(thing.loc == src)
		return TRUE
	return thing.move_into(src, BELLY_SLOT_INTERIOR, actor)

/// Takes `thing` out of this belly to `destination`. A release always succeeds:
/// when the destination's own slots refuse it (a full closet), it lands on the turf.
/obj/belly/proc/belly_release_to(atom/movable/thing, atom/destination, mob/actor)
	if(thing.loc != src)
		return thing.loc == destination
	if(slot_remove(thing, destination, actor))
		return TRUE
	var/turf/T = get_turf(destination) || get_turf(src)
	if(T && slot_remove(thing, T, actor))
		return TRUE
	return FALSE
