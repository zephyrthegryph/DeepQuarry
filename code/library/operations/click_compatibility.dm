/datum/input_event/click/publish_compatibility_click()
	PUBLISH_LEGACY(target, /datum/notice/click, location, control, params, actor)

/mob/op_compatibility_click(atom/target, params)
	return ClickOn(target, params)

/mob/op_click_params(params)
	return dq_interaction_set_click_params(src, params)
