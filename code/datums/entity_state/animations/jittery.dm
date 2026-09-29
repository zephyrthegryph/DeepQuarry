/*
jittery shake - wiggles the mob's pixel offset while the mob is jittery.

Jitters are the EFFECT_JITTERY status (0-1000 points, below 100 is not jittery), which wears off
on its own: 3 points per LIFE_CYCLE, 15 while resting. The mob attaches this behaviour when the
status starts and detaches it when it ends (the status row's on_start/on_end hooks).
(Was /datum/component/jittery_shake; its state lives on the mob.)
*/

/datum/om/behaviour/jittery_shake
	handles = list(/datum/om/event/mob_death)

/mob
	/// Jittery shake: whether the mob was resting when the status's rate was last checked.
	var/jittery_was_resting

/datum/om/behaviour/jittery_shake/on_start(mob/M)
	if(!ismob(M))
		return
	M.jittery_was_resting = M.resting
	om_after_slot(M, "jittery_shake_timer", 1, TYPE_PROC_REF(/mob, jittery_shake_tick)) // Needs to be a LOT faster than life ticks

/datum/om/behaviour/jittery_shake/on_stop(mob/M)
	if(!ismob(M))
		return
	if(om_timer_slot_pending(M, "jittery_shake_timer"))
		om_cancel_timer_slot(M, "jittery_shake_timer")
	// The jittering mob's pixel offsets reset.
	M.pixel_x = M.old_x
	M.pixel_y = M.old_y

/datum/om/behaviour/jittery_shake/on_event(mob/M, datum/om/event/event)
	if(istype(event, /datum/om/event/mob_death) && ismob(M))
		M.status_end(EFFECT_JITTERY)

/mob/proc/jittery_shake_tick()
	if(QDELETED(src) || !om_attached(src, /datum/om/behaviour/jittery_shake))
		return

	// Resting wears jitters off faster.
	if(resting != jittery_was_resting)
		jittery_was_resting = resting
		status_rate_check(EFFECT_JITTERY)

	// Shakey shakey
	var/jitteriness = status_units(EFFECT_JITTERY)
	if(jitteriness > 100)
		var/amplitude = min(4, jitteriness / 100)
		pixel_x = old_x + rand(-amplitude, amplitude)
		pixel_y = old_y + rand(-amplitude/3, amplitude/3)

	if(om_attached(src, /datum/om/behaviour/jittery_shake))
		om_after_slot(src, "jittery_shake_timer", 1, TYPE_PROC_REF(/mob, jittery_shake_tick))

OWN_TIMER(/mob, jittery_shake_timer)
