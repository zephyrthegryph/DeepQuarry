//UPDATE TRIGGERS, when the chunk (and the surrounding chunks) should update.

#define CULT_UPDATE_BUFFER 30


/mob/living/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(!GLOB.cultnet.provides_vision(src))
		return
	if(!sparse_get_or(src, updating_cult_vision, 0))
		sparse_set(src, updating_cult_vision, 1)
		after(src, CULT_UPDATE_BUFFER, PROC_REF(cult_vision_settle), with = list(old_loc))

/mob/living/proc/cult_vision_settle(atom/old_loc)
	sparse_set(src, updating_cult_vision, 0)
	if(old_loc != loc)
		GLOB.cultnet.updateVisibility(old_loc, 0)
		GLOB.cultnet.updateVisibility(loc, 0)

#undef CULT_UPDATE_BUFFER

/// The cult's net sees a living mob come, when it is placed in the world.
/mob/living/on_materialize()
	. = ..()
	GLOB.cultnet.updateVisibility(src, 0)

/datum/antagonist/add_antagonist(datum/mind/player)
	. = ..()
	if(src == antag_cult())
		GLOB.cultnet.updateVisibility(player.current, 0)

/datum/antagonist/remove_antagonist(datum/mind/player, show_message, implanted)
	..()
	if(src == antag_cult())
		GLOB.cultnet.updateVisibility(player.current, 0)
