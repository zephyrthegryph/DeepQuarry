// MASK EYE
//
// A mob that a cultists controls to look around the station with.
// It streams chunks as it moves around, which will show it what the cultist can and cannot see.

/mob/observer/eye/maskEye
	name = "Eye of Nar-Sie"
	acceleration = 0
	owner_follows_eye = 1

/// Declared setup: join cult visualnet, after the complete parent chain.
/mob/observer/eye/maskEye/proc/join_cult_visualnet()
	rel_set(src, nameof(visualnet), GLOB.cultnet)

CAPABILITIES(/mob/observer/eye/maskEye)
	setup(PROC_REF(join_cult_visualnet))
