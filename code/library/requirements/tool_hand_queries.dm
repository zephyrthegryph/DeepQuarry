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


