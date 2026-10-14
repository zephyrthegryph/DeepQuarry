/*
jittery shake - wiggles the mob's pixel offset while the mob is jittery.

Jitters are the STAT_JITTERY status (0-1000 points, below 100 is not jittery), which wears off
on its own: 3 points per LIFE_CYCLE, 15 while resting. The status row's on_start/on_end hooks set
jittery_shaking, and the shake runs as an every() on /mob while it holds.
(Was /datum/component/jittery_shake; its state lives on the mob.)
*/

/mob
	/// Jittery shake: whether the mob was resting when the status's rate was last checked.
	var/jittery_was_resting

/// Set while STAT_JITTERY is in effect: jittery_shake_tick() runs every decisecond (its every() in CAPABILITIES(/mob)), parked otherwise.
/mob/var/tmp/jittery_shaking = FALSE // ALLOW(base_vars): was a declared field on this type; moved, not added
TRACKED(/mob, jittery_shaking)

/mob/proc/jittery_shake_tick(datum/act/A)
	// The dead stop shaking: the status ends (its on_end hook parks this).
	if(stat == DEAD)
		status_end(STAT_JITTERY)
		return

	// Resting wears jitters off faster.
	if(resting != jittery_was_resting)
		jittery_was_resting = resting
		status_rate_check(STAT_JITTERY)

	// Shakey shakey
	var/jitteriness = status_units(STAT_JITTERY)
	if(jitteriness > 100)
		var/amplitude = min(4, jitteriness / 100)
		pixel_x = old_x + rand(-amplitude, amplitude)
		pixel_y = old_y + rand(-amplitude/3, amplitude/3)
