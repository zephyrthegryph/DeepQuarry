// Library storage cost provider: every input used by get_storage_cost, even
// when current storage_cost is nonzero and temporarily masks w_class.
/datum/relation_definition/slot/storage/cost_read_keys(atom/holder, atom/movable/thing)
	. = list()
	if(isitem(thing))
		var/obj/item/I = thing
		. += list(list(I, nameof(I.storage_cost)), list(I, nameof(I.w_class)))

/datum/relation_definition/slot/stock/cost_read_keys(atom/holder, atom/movable/thing)
	. = list()
	if(istype(thing, /obj/item/stack))
		var/obj/item/stack/S = thing
		. += S.amount_read_keys()

/datum/relation_definition/slot/storage/admission_read_keys(atom/holder, atom/movable/thing, mob/actor)
	. = list(list(holder, SLOT_OCCUPANCY_KEY))
	var/datum/rx_state/S = rx_of(holder)
	. += list(list(S, nameof(S.capability_generation)))
	var/datum/capability/lib/storage/C = cap_of(holder, CAP_STORAGE)
	if(!C)
		return
	if(istext(C.space))
		. += list(list(holder, C.space))
	if(istext(C.slots))
		. += list(list(holder, C.slots))
	var/datum/cap_data/storage/D = C.narrowed(holder)
	if(D)
		. += list(list(D, nameof(D.accepts)), list(D, nameof(D.has_accepts)), list(D, nameof(D.max_size)), list(D, nameof(D.has_max_size)))
	if(isitem(thing))
		var/obj/item/I = thing
		. += list(list(I, nameof(I.storage_cost)), list(I, nameof(I.w_class)))
		for(var/key in change_read_keys(I, STAT_TRAIT_HOLDS))
			. += list(list(I, key))
		if(actor)
			. += list(list(actor, SLOT_OCCUPANCY_KEY))
			if(actor.isEquipped(I))
				. += actor.unequip_read_keys(I)
	if(isitem(holder))
		var/obj/item/B = holder
		. += list(list(B, nameof(B.w_class)))
