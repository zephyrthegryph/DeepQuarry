/datum/prompt/number/lasertag_setting
	timeout = 0
	step = 1
	var/healing_timer = FALSE

/datum/prompt/number/lasertag_setting/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/lasertag_setting/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/item/clothing/suit/lasertag/suit = owner
	if(!suit.Adjacent(answerer))
		return "not adjacent to the suit"
	return null
