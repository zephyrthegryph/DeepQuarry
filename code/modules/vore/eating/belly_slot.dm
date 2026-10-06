// C7: vore on slots (doc/rewrite/containment.md §9).
//
// A belly stays an atom, because a prey mob needs an atom as its loc, and its
// interior is a sealed slot (C1/C2): prey go in with move_into(), leave with
// slot_remove() and move between bellies with slot_transfer(). The ledger is
// made on first use, so an empty belly has none.
//
// Scheduling. There is no belly subsystem. A belly runs its digestion cycle on its
// own clock (the belly_cycle capability's every(), granted while it is occupied) only while something is inside it (or its owner previews it):
// belly_reschedule() starts it when the first thing enters and cancels it when the
// last one leaves. An empty belly that makes liquid from nutrition sleeps on an
// after() timer for its next batch instead. An empty, idle belly holds no
// scheduler state and runs no code.
//
// Rates. Every mode's effect is a rate per BELLY_BASELINE_TICK scaled by the
// real time since the belly's last cycle (the clock passes the seconds), so a
// late or a turbo cycle changes nothing but granularity: the same totals over
// the same time.

/obj/belly
	/// TRUE while the belly's cycle clock runs (it is occupied), else null.
	var/tmp/cycle_token
	/// The period the clock runs at, and when it last ran a cycle.
	var/tmp/cycle_period
	EXPIRY_TMP_DECLARE(cycle_last)

/// The inside of a belly: sealed (its own air and temperature), and it reaches the
/// mobs inside it. Outside effects don't pass the predator's body into it; the
/// belly's own modes are what act on its contents.
/datum/om/relation/slot/belly_interior
	holder = /obj/belly
	slot_id = BELLY_SLOT_INTERIOR
	name = "belly"
	is_default = TRUE
	exposure = SLOT_EXPOSURE_SEALED
	reaches_mobs = TRUE
	drop_policy = SLOT_DROP_SPILL
	heat_transmission = 0
	radiation_transmission = 1
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// The inside of a belly is inside the predator: its contents see the predator's
/// body temperature (the belly air is made at it, and prey who haven't opted into
/// temperature play feel it). A prey who allows it feels `bellytemperature`
/// instead (see the human environment life system).
/obj/belly/get_interior_temperature()
	var/mob/living/pred = owner
	if(istype(pred))
		return pred.body_temperature()
	return ..()

/// Seconds per cycle for this belly: the baseline, or a third of it in turbo mode.
/obj/belly/proc/belly_cycle_period()
	return (speedy_mob_processing || (mode_flags & DM_FLAG_TURBOMODE)) ? BELLY_TURBO_TICK : BELLY_BASELINE_TICK

/// Whether this belly has anything to do every cycle.
/obj/belly/proc/belly_occupied()
	if(!isliving(owner) || QDELETED(src))
		return FALSE
	return contents_count(src) || owner.previewing_belly == src

/// Whether this belly makes liquid from its owner's nutrition over time.
/obj/belly/proc/belly_generates_liquid()
	return isliving(owner) && show_liquids && reagentbellymode && (reagent_mode_flags & DM_FLAG_REAGENTSNUTRI) && !isnewplayer(owner)

/// An occupied belly's digestion cycle: every(belly_cycle_period()) on the belly's own clock, granted by belly_reschedule().
CAPABILITY_TYPE(belly_cycle, CAP_BELLY_CYCLE, /datum/capability/belly_cycle, key = NONE)
/datum/capability/belly_cycle

/datum/capability/belly_cycle/entries()
	return list(every(TYPE_PROC_REF(/obj/belly, belly_cycle_interval), then(CAP_PROC(cycle_run))))

/datum/capability/belly_cycle/proc/cycle_run(datum/act/timer/A)
	var/obj/belly/B = A.holder
	B.belly_cycle_due()

/// The every() interval of the cycle: the period in deciseconds (the interval proc's form, x(datum/act/A)).
/obj/belly/proc/belly_cycle_interval(datum/act/A)
	return cycle_period || belly_cycle_period()

/// Starts, retunes or stops this belly's scheduled work to match what it holds.
/// Call it whenever contents, turbo mode, liquid settings or the preview change.
/obj/belly/proc/belly_reschedule()
	if(QDELETED(src))
		return
	if(belly_occupied())
		if(after_pending(src, "liquid_timer"))
			cancel_after(src, "liquid_timer")
		cycle_period = belly_cycle_period()
		if(!cycle_token)
			EXPIRY_STAMP(src, cycle_last, CLOCK_WORLD)
			cycle_token = TRUE
			grant(src, /datum/capability/belly_cycle, src)
		return
	if(cycle_token)
		revoke(src, /datum/capability/belly_cycle, src)
		cycle_token = null
		cycle_period = null
		belly_surrounding = null
	if(belly_generates_liquid())
		if(!after_pending(src, "liquid_timer"))
			var/cycles_left = max(gen_time + 1 - gen_interval, 1)
			sleep_audit_join(src)
			after(src, cycles_left * belly_cycle_period(), PROC_REF(liquid_batch_due), key = "liquid_timer")
	else if(after_pending(src, "liquid_timer"))
		cancel_after(src, "liquid_timer")

/// Occupied: one digestion cycle for the real time since the last one (the capability's every() arms the next).
/obj/belly/proc/belly_cycle_due()
	if(QDELETED(src) || !cycle_token)
		return
	var/seconds = (world.time - cycle_last) / (1 SECONDS)
	EXPIRY_STAMP(src, cycle_last, CLOCK_WORLD)
	belly_cycle(seconds)
	if(!QDELETED(src) && !belly_occupied())
		belly_reschedule()

/// Empty and generating: the next liquid batch is due.
/obj/belly/proc/liquid_batch_due()
	if(!after_pending(src, "liquid_timer"))
		return
	if(belly_occupied())
		belly_reschedule()
		return
	gen_interval = max(gen_interval, gen_time)
	HandleBellyReagents()
	belly_reschedule()

/// Asleep means no cycle while empty and not previewed.
/obj/belly/sleep_violation()
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
	return move_into(src, BELLY_SLOT_INTERIOR, thing, actor)

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
