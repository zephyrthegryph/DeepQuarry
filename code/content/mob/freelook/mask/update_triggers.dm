//UPDATE TRIGGERS, when the chunk (and the surrounding chunks) should update.

#define CULT_UPDATE_BUFFER 30


/mob/living/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	MOVE_COST_BEGIN(follow_started)
	// No cult eye has looked anywhere yet (no chunk is generated): a chunk computes what it sees when it is made, so there is nothing to update.
	if(!LAZYLEN(GLOB.cultnet.chunks) || !GLOB.cultnet.provides_vision(src))
		MOVE_COST_END(MOVE_COST_FOLLOW, follow_started)
		return
	// The pending keyed timer is the debounce: no state flag, whose writes republished the mob's living_misc row (and redrew a human) twice per window.
	if(!after_pending(src, "cult_vision"))
		after(src, CULT_UPDATE_BUFFER, PROC_REF(cult_vision_settle), key = "cult_vision", with = list(old_loc))
	MOVE_COST_END(MOVE_COST_FOLLOW, follow_started)

/mob/living/proc/cult_vision_settle(atom/old_loc)
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
