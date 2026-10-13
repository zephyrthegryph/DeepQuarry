// Shared tool and body hand queries retained unchanged when predicate compiler retires.

/mob/proc/dq_has_free_hand()
	return FALSE

/// Tier of `quality` on `I`: its value in an associative tool_qualities list, else 1.
/proc/dq_tool_tier(obj/item/I, quality)
	if(!I.has_tool_quality(quality))
		return 0
	var/tier = I.tool_qualities[quality]
	return isnum(tier) ? tier : 1


/mob/living/carbon/human/dq_has_free_hand()
	return !get_equipped_item(SLOT_ID_HAND_L) || !get_equipped_item(SLOT_ID_HAND_R)

/mob/living/simple_mob/dq_has_free_hand()
	return has_hands && (!get_equipped_item(SLOT_ID_HAND_L) || !get_equipped_item(SLOT_ID_HAND_R))


/// Preserve the tool refusal grammar shared with tool_quality_failure().
/proc/dq_pred_article(noun)
	return "[(copytext(noun, 1, 2) in list("a", "e", "i", "o", "u")) ? "an" : "a"] [noun]"

/proc/dq_pred_tool_name(quality)
	switch(quality)
		if(TOOL_CABLE_COIL)
			return "cable coil"
		if(TOOL_BLOODFILTER)
			return "blood filter"
		if(TOOL_ROLLINGPIN)
			return "rolling pin"
		if(TOOL_MINING)
			return "mining tool"
	return quality

