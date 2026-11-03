/*
dizzy shake - wiggles the client's pixel offset while the mob is dizzy.

Dizziness itself is the STAT_DIZZY status (0-1000 points, below 100 is not dizzy), which wears
off on its own: 3 points per LIFE_CYCLE, 15 while resting. The shake runs as an every() on /mob gated on the status
itself (when = STAT_DIZZY), so it runs from the status's first hold to its end.
(Was /datum/component/dizzy_shake; its state lives on the mob.)
*/

/// Runs every decisecond while STAT_DIZZY is in effect (its every() in CAPABILITIES(/mob)), parked otherwise.
/mob/proc/dizzy_shake_tick(datum/act/A)
	// The dead stop shaking: the status ends (its on_end hook parks this).
	if(stat == DEAD)
		status_end(STAT_DIZZY)
		return

	// Resting wears dizziness off faster.
	if(resting != sparse_get(src, dizzy_was_resting))
		sparse_set(src, dizzy_was_resting, resting)
		status_rate_check(STAT_DIZZY)

	// Handle wobbles
	var/dizziness = status_units(STAT_DIZZY)
	if(dizziness > 100 && client)
		var/amplitude = dizziness*(sin(dizziness * 0.044 * world.time) + 1) / 70
		client.pixel_x = amplitude * sin(0.008 * dizziness * world.time)
		client.pixel_y = amplitude * cos(0.008 * dizziness * world.time)
