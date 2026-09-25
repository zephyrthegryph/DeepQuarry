/*
jittery shake - wiggles the mob's pixel offset while the mob is jittery.

Jitters are the EFFECT_JITTERY status (0-1000 points, below 100 is not jittery), which wears off
on its own: 3 points per LIFE_CYCLE, 15 while resting. The mob adds this component when the
status starts and deletes it when it ends (the status row's on_start/on_end hooks).
*/

/datum/component/jittery_shake
	var/mob/owner
	/// Whether the owner was resting when the status's rate was last checked.
	var/was_resting

/datum/component/jittery_shake/Initialize()
	if (!ismob(parent))
		return COMPONENT_INCOMPATIBLE
	owner = parent
	was_resting = owner.resting
	RegisterSignal(owner, COMSIG_MOB_DEATH, PROC_REF(mob_death))
	addtimer(CALLBACK(src, PROC_REF(handle_tick)), 1, TIMER_DELETE_ME) // Needs to be a LOT faster than life ticks

/datum/component/jittery_shake/proc/handle_tick()
	if(QDELETED(parent))
		return

	// Resting wears jitters off faster.
	if(owner.resting != was_resting)
		was_resting = owner.resting
		owner.status_rate_check(EFFECT_JITTERY)

	// Shakey shakey
	var/jitteriness = owner.status_units(EFFECT_JITTERY)
	if(jitteriness > 100)
		var/amplitude = min(4, jitteriness / 100)
		owner.pixel_x = owner.old_x + rand(-amplitude, amplitude)
		owner.pixel_y = owner.old_y + rand(-amplitude/3, amplitude/3)

	addtimer(CALLBACK(src, PROC_REF(handle_tick)), 1, TIMER_DELETE_ME)

/datum/component/jittery_shake/proc/mob_death()
	SIGNAL_HANDLER
	owner.status_end(EFFECT_JITTERY)

/datum/component/jittery_shake/Destroy(force = FALSE)
	UnregisterSignal(owner, COMSIG_MOB_DEATH)
	// Reset the pixel offsets to zero
	owner.pixel_x = owner.old_x
	owner.pixel_y = owner.old_y
	owner = null
	. = ..()
