/*
dizzy shake - wiggles the client's pixel offset while the mob is dizzy.

Dizziness itself is the EFFECT_DIZZY status (0-1000 points, below 100 is not dizzy), which wears
off on its own: 3 points per LIFE_CYCLE, 15 while resting. The mob adds this component when the
status starts and deletes it when it ends (the status row's on_start/on_end hooks).
*/

/datum/component/dizzy_shake
	var/mob/owner
	/// Whether the owner was resting when the status's rate was last checked.
	var/was_resting

/datum/component/dizzy_shake/Initialize()
	if (!ismob(parent))
		return COMPONENT_INCOMPATIBLE
	owner = parent
	was_resting = owner.resting
	RegisterSignal(owner, COMSIG_MOB_DEATH, PROC_REF(mob_death))
	om_after(src, 1, PROC_REF(handle_tick)) // Needs to be a LOT faster than life ticks

/datum/component/dizzy_shake/proc/handle_tick()
	if(QDELETED(parent))
		return

	// Resting wears dizziness off faster.
	if(owner.resting != was_resting)
		was_resting = owner.resting
		owner.status_rate_check(EFFECT_DIZZY)

	// Handle wobbles
	var/dizziness = owner.status_units(EFFECT_DIZZY)
	if(dizziness > 100 && owner.client)
		var/amplitude = dizziness*(sin(dizziness * 0.044 * world.time) + 1) / 70
		owner.client.pixel_x = amplitude * sin(0.008 * dizziness * world.time)
		owner.client.pixel_y = amplitude * cos(0.008 * dizziness * world.time)

	om_after(src, 1, PROC_REF(handle_tick))

/datum/component/dizzy_shake/proc/mob_death()
	SIGNAL_HANDLER
	owner.status_end(EFFECT_DIZZY)

// ALLOW(lifecycle): the shaken client's view offset resets.
/datum/component/dizzy_shake/Destroy(force = FALSE)
	if(owner.client)
		owner.client.pixel_x = 0
		owner.client.pixel_y = 0
	. = ..()
