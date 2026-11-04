/*
jittery shake - wiggles the mob's pixel offset while the mob is jittery.

Jitters are the STAT_JITTERY status (0-1000 points, below 100 is not jittery), which wears off
on its own: 3 points per LIFE_CYCLE, 15 while resting. The shake runs as an every() on /mob gated on the status
itself (when = STAT_JITTERY), so it runs from the status's first hold to its end.
(Was /datum/component/jittery_shake; its state lives on the mob.)
*/

/// Runs every decisecond while STAT_JITTERY is in effect (its every() in CAPABILITIES(/mob)), parked otherwise.
/mob/proc/jittery_shake_tick(datum/act/A)
	// The dead stop shaking: the status ends (its on_end hook parks this).
	if(stat == DEAD)
		status_end(STAT_JITTERY)
		return

	// Resting wears jitters off faster.
	if(resting != sparse_get(src, jittery_was_resting))
		sparse_set(src, jittery_was_resting, resting)
		status_rate_check(STAT_JITTERY)

	// Shakey shakey
	var/jitteriness = status_units(STAT_JITTERY)
	if(jitteriness > 100)
		var/amplitude = min(4, jitteriness / 100)
		set_pixel_x(default_pixel_x + rand(-amplitude, amplitude))
		set_pixel_y(MOB_REST_PIXEL_Y(src) + rand(-amplitude/3, amplitude/3))
