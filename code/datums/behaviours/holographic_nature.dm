/*
 * Holographic objects glitch out when passed through. Its one user, the AI hologram, reacts
 * in Crossed() instead.
 */
#define GLITCH_DURATION 0.45 SECONDS
#define GLITCH_REMOVAL_DURATION 0.25 SECONDS

/obj/effect/overlay/aiholo
	///cooldown before we can glitch out again
	COOLDOWN_DECLARE(glitch_cooldown)

/obj/effect/overlay/aiholo/Crossed(atom/movable/AM, oldloc)
	. = ..()
	if(!isturf(loc))
		return
	if(AM.density || AM.throwing)
		holographic_glitch()

/obj/effect/overlay/aiholo/proc/holographic_glitch()
	if(!COOLDOWN_FINISHED(src, glitch_cooldown))
		return
	COOLDOWN_START(src, glitch_cooldown, GLITCH_DURATION + GLITCH_REMOVAL_DURATION)
	apply_wibbly_filters(src)
	om_after(src, GLITCH_DURATION, GLOBAL_PROC_REF(remove_wibbly_filters), src, GLITCH_REMOVAL_DURATION)

#undef GLITCH_DURATION
#undef GLITCH_REMOVAL_DURATION
