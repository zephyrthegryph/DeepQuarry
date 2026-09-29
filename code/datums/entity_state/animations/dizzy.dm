/*
dizzy shake - wiggles the client's pixel offset while the mob is dizzy.

Dizziness itself is the EFFECT_DIZZY status (0-1000 points, below 100 is not dizzy), which wears
off on its own: 3 points per LIFE_CYCLE, 15 while resting. The mob attaches this behaviour when the
status starts and detaches it when it ends (the status row's on_start/on_end hooks).
(Was /datum/component/dizzy_shake; its state lives on the mob.)
*/

/datum/om/behaviour/dizzy_shake
	handles = list(/datum/om/event/mob_death)

/mob
	/// Dizzy shake: whether the mob was resting when the status's rate was last checked.
	var/dizzy_was_resting

/datum/om/behaviour/dizzy_shake/on_start(mob/M)
	if(!ismob(M))
		return
	M.dizzy_was_resting = M.resting
	om_after_slot(M, "dizzy_shake_timer", 1, TYPE_PROC_REF(/mob, dizzy_shake_tick)) // Needs to be a LOT faster than life ticks

/datum/om/behaviour/dizzy_shake/on_stop(mob/M)
	if(!ismob(M))
		return
	if(om_timer_slot_pending(M, "dizzy_shake_timer"))
		om_cancel_timer_slot(M, "dizzy_shake_timer")
	// The shaken client's view offset resets.
	if(M.client)
		M.client.pixel_x = 0
		M.client.pixel_y = 0

/datum/om/behaviour/dizzy_shake/on_event(mob/M, datum/om/event/event)
	if(istype(event, /datum/om/event/mob_death) && ismob(M))
		M.status_end(EFFECT_DIZZY)

/mob/proc/dizzy_shake_tick()
	if(QDELETED(src) || !om_attached(src, /datum/om/behaviour/dizzy_shake))
		return

	// Resting wears dizziness off faster.
	if(resting != dizzy_was_resting)
		dizzy_was_resting = resting
		status_rate_check(EFFECT_DIZZY)

	// Handle wobbles
	var/dizziness = status_units(EFFECT_DIZZY)
	if(dizziness > 100 && client)
		var/amplitude = dizziness*(sin(dizziness * 0.044 * world.time) + 1) / 70
		client.pixel_x = amplitude * sin(0.008 * dizziness * world.time)
		client.pixel_y = amplitude * cos(0.008 * dizziness * world.time)

	if(om_attached(src, /datum/om/behaviour/dizzy_shake))
		om_after_slot(src, "dizzy_shake_timer", 1, TYPE_PROC_REF(/mob, dizzy_shake_tick))

/mob/om_declared_timer_slots()
	. = ..()
	. += "dizzy_shake_timer"
