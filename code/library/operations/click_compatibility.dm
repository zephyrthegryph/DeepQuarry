/datum/input_event/click/publish_compatibility_click()
	PUBLISH_LEGACY(target, /datum/notice/click, location, control, params, actor)

/mob/op_compatibility_click(atom/target, params)
	return ClickOn(target, params)

/mob/op_click_params(params)
	return dq_interaction_set_click_params(src, params)

/// Click parameters of the click each actor is inside (an item's swing, a drag), so an effect can place precisely: dq_interaction_click_params().
GLOBAL_LIST_EMPTY(interaction_entry_click_params)

/// Sets `actor`'s click parameters (null clears them); returns the previous value to restore.
/proc/dq_interaction_set_click_params(mob/actor, params)
	if(!actor)
		return null
	. = GLOB.interaction_entry_click_params[actor]
	if(params)
		GLOB.interaction_entry_click_params[actor] = params
	else
		GLOB.interaction_entry_click_params -= actor

/// The click parameters of the click `actor` is inside, or null.
/proc/dq_interaction_click_params(mob/actor)
	return actor ? GLOB.interaction_entry_click_params[actor] : null
