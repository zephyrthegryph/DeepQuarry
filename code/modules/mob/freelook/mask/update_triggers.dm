//UPDATE TRIGGERS, when the chunk (and the surrounding chunks) should update.

#define CULT_UPDATE_BUFFER 30

/mob/living/var/updating_cult_vision = 0

/mob/living/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(!GLOB.cultnet.provides_vision(src))
		return
	if(!updating_cult_vision)
		updating_cult_vision = 1
		spawn(CULT_UPDATE_BUFFER)
			if(old_loc != src.loc)
				GLOB.cultnet.updateVisibility(old_loc, 0)
				GLOB.cultnet.updateVisibility(loc, 0)
			updating_cult_vision = 0

#undef CULT_UPDATE_BUFFER

/mob/living/Initialize(mapload)
	. = ..()
	GLOB.cultnet.updateVisibility(src, 0)

/datum/antagonist/add_antagonist(datum/mind/player)
	. = ..()
	if(src == GLOB.cult)
		GLOB.cultnet.updateVisibility(player.current, 0)

/datum/antagonist/remove_antagonist(datum/mind/player, show_message, implanted)
	..()
	if(src == GLOB.cult)
		GLOB.cultnet.updateVisibility(player.current, 0)
