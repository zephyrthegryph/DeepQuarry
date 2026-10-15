// Concrete device inputs supplied by their actor. These return the actual tool,
// credential, photograph or byline; they do not grant remote authority.
/mob/proc/multitool_for_machine(obj/machine)
	return get_active_hand()?.get_multitool()

/mob/living/silicon/multitool_for_machine(obj/machine)
	return null

/mob/living/silicon/ai/multitool_for_machine(obj/machine)
	return aiMulti

/mob/living/silicon/robot/multitool_for_machine(obj/machine)
	return get_dist(src, machine) <= 1 ? get_active_hand()?.get_multitool() : null

// Airlock programming historically uses the human's worn card (not a held one)
// and a silicon's internal card even when a bolt masks GetIdCard().
/mob/proc/airlock_programming_card()
	return null

/mob/living/carbon/human/airlock_programming_card()
	return get_idcard()

/mob/living/silicon/airlock_programming_card()
	return idcard

// A real camera selection is supplied by the existing silicon implementation.
// Other actors have no stored camera photographs to select.
/mob/proc/GetPicture()
	return null

/mob/proc/receive_news_photo(obj/item/photo/photo)
	put_in_inactive_hand(photo)

/mob/living/silicon/receive_news_photo(obj/item/photo/photo)
	return

/mob/proc/news_byline()
	return "Unknown"

/mob/living/carbon/human/news_byline()
	var/obj/item/card/id/card = GetIdCard()
	return card ? GetNameAndAssignmentFromId(card) : "Unknown"

/mob/living/silicon/news_byline()
	return "[name] ([job])"
