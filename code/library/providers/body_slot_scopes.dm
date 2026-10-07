/datum/om/relation/slot/body/hand/is_hand_provider_slot()
	return TRUE

/datum/om/relation/slot/body/is_carried_provider_slot()
	return TRUE

/datum/om/relation/slot/body/is_worn_provider_slot()
	return !!(roles & BODY_SLOT_WORN)
