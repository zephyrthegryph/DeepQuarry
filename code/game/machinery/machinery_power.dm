//
// /obj/machinery POWER USAGE CODE HERE! GO GO GADGET STATIC POWER!
// Note: You can find /obj/machinery/power power usage code in power.dm
//
// The following four machinery variables determine the "static" amount of power used every power cycle:
// - use_power, idle_power_usage, active_power_usage, power_channel
//
// Please never change any of these variables! Use the procs that update them instead!
//

// Current power consumption right now.
#define POWER_CONSUMPTION (use_power == USE_POWER_IDLE ? idle_power_usage : (use_power >= USE_POWER_ACTIVE ? active_power_usage : 0))

// returns true if the area has power on given channel (or doesn't require power).
// defaults to power_channel
/obj/machinery/proc/powered(chan = CURRENT_CHANNEL) // defaults to power_channel
	//Don't do this. It allows machines that set use_power to 0 when off (many machines) to
	//be turned on again and used after a power failure because they never gain the NOPOWER flag.
	//if(!use_power)
	//	return 1

	var/area/A = get_area(src)		// make sure it's in an area
	if(!A)
		return 0					// if not, then not powered
	if(chan == CURRENT_CHANNEL)
		chan = power_channel
	return A.powered(chan)			// return power status of the area

// called whenever the power settings of the containing area change
// by default, check equipment channel & set/clear NOPOWER flag
// Returns TRUE if NOPOWER stat flag changed.
// can override if needed
/obj/machinery/proc/power_change()
	if(!set_powered(powered(power_channel)))
		return FALSE
	changed(src) // a power change is a dispatched call: the powered capability's layer follows
	if(has_stat(NOPOWER))
		PUBLISH_LEGACY(src, /datum/notice/machinery_power_lost)
	else
		PUBLISH_LEGACY(src, /datum/notice/machinery_power_restored)
	update_heat_output()
	return TRUE

/**
 * The power capability's "powered" state (G8): the one writer of NOPOWER. A change raises CHANGE_MACHINE_POWER (the
 * stat bit's bridge channel) and publishes MACHINE_KEY_POWERED to its readers. has_stat(NOPOWER) and operable() read
 * it. Returns TRUE when the state changed.
 */
/obj/machinery/proc/set_powered(powered)
	if(!(powered ? stat_remove(NOPOWER) : stat_add(NOPOWER)))
		return FALSE
	PUBLISH_CHANGE(src, MACHINE_KEY_POWERED)
	return TRUE

// Get the amount of power this machine will consume each cycle.  Override by experts only!
/obj/machinery/proc/get_power_usage()
	return POWER_CONSUMPTION

// DEPRECATED! - USE use_power_oneoff() instead!
/obj/machinery/proc/use_power(amount, chan = -1) // defaults to power_channel
	return src.use_power_oneoff(amount, chan);

// This will have this machine have its area eat this much power next tick, and not afterwards. Do not use for continued power draw.
// Returns actual amount drawn (In theory this could be less than the amount asked for. In pratice it won't be FOR NOW)
/obj/machinery/proc/use_power_oneoff(amount, chan = CURRENT_CHANNEL)
	var/area/A = get_area(src)		// make sure it's in an area
	if(!A)
		return
	if(chan == CURRENT_CHANNEL)
		chan = power_channel
	return A.use_power_oneoff(amount, chan)

// Check if we CAN use a given amount of extra power as a one off. Returns amount we could use without actually using it.
// For backwards compatibilty this returns true if the channel is powered. This is consistant with pre-static-power
// behavior of APC powerd machines, but at some point we might want to make this a bit cooler.
/obj/machinery/proc/can_use_power_oneoff(amount, chan = CURRENT_CHANNEL)
	if(powered(chan))
		return amount // If channel is powered then you can do it.
	return 0

/obj/machinery
	var/tmp/recursive_set = FALSE // bool to indicate if recursive movement detection ever got set. If it did, don't try to set it again!

// Do not do power stuff in New/Initialize until after ..()
// ALLOW(init/FRAMEWORK): the machinery base of the init chain reports its draw and joins its area's power
/obj/machinery/Initialize(mapload)
	. = ..()
	// only add this if we init on a non-turf (and non-null)
	if(!recursive_set && loc && !isturf(loc))
		recursive_set = TRUE
		dq_add_recursive_move(src)
		observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(update_power_on_move))) //we only need this for recursive moving
	power_init_complete = TRUE
	rel_set(src, nameof(power_area), get_area(src)) // the machine's draw reaches the area's demand with the relation

// Or in Destroy at all, but especially after the ..().
// the base machine: its power draw leaves the area budget.
/obj/machinery/on_destroy(force)
	rel_set(src, nameof(power_area), null) // the draw leaves the area's demand
	..()

// Registering moved_event observers for all machines is too expensive.  Instead we do it ourselves.
// 99% of machines are always on a turf anyway, very few need recursive move handling.
/obj/machinery/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	power_area_moved(old_loc, loc)

	// only add this if we move into a non-turf (not null) and we've never been given recursive move handling
	if(!recursive_set && loc && !isturf(loc))
		recursive_set = TRUE
		dq_add_recursive_move(src)
		observe(src, /datum/notice/movable_attempted_move, src, then(PROC_REF(update_power_on_move))) //we only need this for recursive moving

/obj/machinery/proc/update_power_on_move(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/movable_attempted_move/event = A
	power_area_moved(event.old_loc, event.new_loc)

/obj/machinery/proc/power_area_moved(atom/old_loc, atom/new_loc)
	var/area/old_area = get_area(old_loc)
	var/area/new_area = get_area(new_loc)
	if(old_area != new_area)
		area_changed(old_area, new_area)

/obj/machinery/proc/area_changed(area/old_area, area/new_area)
	if(old_area == new_area)
		return
	if(!power_init_complete)
		return
	rel_set(src, nameof(power_area), new_area) // the draw follows the relation: it leaves the old area's demand and joins the new one's
	power_change() // Force check in case the old area was powered and the new one isn't or vice versa.

//
// Usage Update Procs - These procs are the only allowed way to modify these four variables:
// 	- use_power, idle_power_usage, active_power_usage, power_channel
//

// Sets the use_power var. The draw is a contribution to the area's demand that reads it, so the write is the whole update.
/obj/machinery/proc/set_use_power(new_use_power)
	if(use_power == new_use_power)
		return
	use_power = new_use_power
	// A power-mode change is a settings change for a machine on a pipeline (machine_pipeline.dm).
	// Raised after the write: watchers (declared periodic work) read the new value. use_power is the power
	// capability's tracked draw mode (G8): the change publishes nameof(use_power) to its readers, and the area's demand stat
	// that sums it recomputes before this returns.
	changed(src, CHANGE_MACHINE_SETTINGS, nameof(use_power))
	return TRUE

/// Sets the power_channel var; the draw moves between the area's channel demands with it (power_channel is tracked).
/obj/machinery/proc/update_power_channel(new_channel)
	return set_power_channel(new_channel)

/// Convenience wrapper: sets idle or active power consumption depending on use_power_mode.
/// Prefer calling update_idle_power_usage() / update_active_power_usage() directly in new code.
/obj/machinery/proc/change_power_consumption(new_power_consumption, use_power_mode = USE_POWER_IDLE)
	switch(use_power_mode)
		if(USE_POWER_IDLE)
			update_idle_power_usage(new_power_consumption)
		if(USE_POWER_ACTIVE)
			update_active_power_usage(new_power_consumption)

/// Sets the idle draw (tracked: the area's demand follows while the machine is idle).
/obj/machinery/proc/update_idle_power_usage(new_power_usage)
	return set_idle_power_usage(new_power_usage)

/// Sets the active draw (tracked: the area's demand follows while the machine is active).
/obj/machinery/proc/update_active_power_usage(new_power_usage)
	return set_active_power_usage(new_power_usage)

// ---- the draw as the area's demand (doc/rewrite/power_grid.md) ----

/// The channel the machine draws on is EQUIP (the cond of its equipment contribution).
/obj/machinery/proc/draws_equip(datum/act/A)
	return power_channel == EQUIP

/obj/machinery/proc/draws_light(datum/act/A)
	return power_channel == LIGHT

/obj/machinery/proc/draws_environ(datum/act/A)
	return power_channel == ENVIRON

/// What the machine asks of its channel right now: its idle or active draw by the mode it is in, or nothing.
/obj/machinery/proc/power_demand(datum/act/A)
	return get_power_usage()

#undef POWER_CONSUMPTION
