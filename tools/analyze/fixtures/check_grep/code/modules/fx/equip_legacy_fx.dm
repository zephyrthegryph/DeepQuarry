/obj/item/thing
	can_hold = list()
	cant_hold = list()
	species_restricted = list()
	// can_hold = list()
	 * cant_hold doc
	can_holder = 3
	if(slot_flags & ITEM_X)
	if(slot_flags &ITEM_Y)
	if(slot_flags & ITEM_Z) // note
	slot_flags &= ~ITEM_Q
	// if(slot_flags & ITEM_COMMENT)
	if(slot_flags & ITEM_A) // ALLOW(check_grep): ok
