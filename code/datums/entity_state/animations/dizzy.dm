/*
dizzy shake - wiggles the client's pixel offset while the mob is dizzy.

Dizziness itself is the STAT_DIZZY status (0-1000 points, below 100 is not dizzy), which wears
off on its own: 3 points per LIFE_CYCLE, 15 while resting. The mob attaches this behaviour when the
status starts and detaches it when it ends (the status row's on_start/on_end hooks).
(Was /datum/component/dizzy_shake; its state lives on the mob.)
*/

/datum/om/behaviour/dizzy_shake
	handles = list(/datum/om/event/mob_death)

/mob
	/// Dizzy shake: whether the mob was resting when the status's rate was last checked.
	var/dizzy_was_resting

/// Set while the dizzy_shake behaviour is attached: dizzy_shake_tick() runs every tick (DECLARE_REPEAT).
OM_FIELD_TYPED(/mob, tmp, dizzy_shaking, FALSE, CHANGE_MOB_CONDITIONS)
DECLARE_REPEAT(/mob, 1, dizzy_shake_tick, "dizzy_shaking") // Needs to be a LOT faster than life ticks

/datum/om/behaviour/dizzy_shake/on_start(mob/M)
	if(!ismob(M))
		return
	M.dizzy_was_resting = M.resting
	M.set_dizzy_shaking(TRUE)

/datum/om/behaviour/dizzy_shake/on_stop(mob/M)
	if(!ismob(M))
		return
	M.set_dizzy_shaking(FALSE)
	// The shaken client's view offset resets.
	if(M.client)
		M.client.pixel_x = 0
		M.client.pixel_y = 0

/datum/om/behaviour/dizzy_shake/on_event(mob/M, datum/om/event/event)
	if(istype(event, /datum/om/event/mob_death) && ismob(M))
		M.status_end(STAT_DIZZY)

/mob/proc/dizzy_shake_tick()
	if(QDELETED(src) || !om_attached(src, /datum/om/behaviour/dizzy_shake))
		return REPEAT_STOP

	// Resting wears dizziness off faster.
	if(resting != dizzy_was_resting)
		dizzy_was_resting = resting
		status_rate_check(STAT_DIZZY)

	// Handle wobbles
	var/dizziness = status_units(STAT_DIZZY)
	if(dizziness > 100 && client)
		var/amplitude = dizziness*(sin(dizziness * 0.044 * world.time) + 1) / 70
		client.pixel_x = amplitude * sin(0.008 * dizziness * world.time)
		client.pixel_y = amplitude * cos(0.008 * dizziness * world.time)
