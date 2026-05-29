// /datum/modifier behavior grants. Mirror of obj/item but for status effects.
//
// A modifier that overrides get_dq_granted_behaviors() with a non-null list
// will inject those behaviors into the holder's brain while attached. They
// drop off automatically when the modifier expires (rebuild_behaviors picks
// up the absence on the next slow tick).

/datum/modifier/proc/get_dq_granted_behaviors()
	return null
