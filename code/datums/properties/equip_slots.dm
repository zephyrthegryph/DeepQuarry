// Equip slot constraints (doc/rewrite/rules.md §3, roadmap P3).
//
// Each equip slot has a predicate, evaluated with the wearer as PRED_ACTOR and
// the item as PRED_TARGET. It holds what the slot accepts: the wearable tag
// (the old slot_flags check) and the slot's own rules (pockets need a
// jumpsuit, suit storage asks the worn suit, ...). C3's body-part slot_defs
// use these as their `accepts`.
//
// equip_refusal() asks the mob's ledger slot (C3): the mob's slot list says
// whether it has the slot, the slot's refusal() whether its body part is there
// and its predicate takes the item, its capacity whether it is free. Then
// reachability and the item's own constraints (CONSTRAINT_FIT except in pockets
// and suit storage, and CONSTRAINT_EQUIP everywhere).

/datum/predicate/equip_slot
	name = "equip slot"
	/// slot_* id.
	var/slot

/datum/predicate/equip_slot/back
	slot = slot_back
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_BACK))

/datum/predicate/equip_slot/belt
	slot = slot_belt
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_BELT))

/datum/predicate/equip_slot/id
	slot = slot_wear_id
	spec = list(
		REQ_TAG(PRED_TARGET, TAG_WEAR_ID),
		REQ_PROC(/proc/dq_equip_has_uniform, null),
	)

/datum/predicate/equip_slot/suit_storage
	slot = slot_s_store
	spec = list(REQ_PROC(/proc/dq_equip_suit_storage_takes, null))

/datum/predicate/equip_slot/pocket
	spec = list(
		REQ_PROC(/proc/dq_equip_has_uniform, null),
		REQ_NO_TAG(PRED_TARGET, TAG_NO_POCKET),
		REQ_BECAUSE(REQ_ANY(REQ_AT_MOST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_SMALL)), REQ_TAG(PRED_TARGET, TAG_POCKETABLE)), "too big for a pocket"),
	)

/datum/predicate/equip_slot/pocket/left
	slot = slot_l_store

/datum/predicate/equip_slot/pocket/right
	slot = slot_r_store

/datum/predicate/equip_slot/glasses
	slot = slot_glasses
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_EYES))

/datum/predicate/equip_slot/mask
	slot = slot_wear_mask
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_MASK))

/datum/predicate/equip_slot/gloves
	slot = slot_gloves
	spec = list(
		REQ_TAG(PRED_TARGET, TAG_WEAR_GLOVES),
		REQ_PROC(/proc/dq_equip_glove_layering, null),
	)

/datum/predicate/equip_slot/head
	slot = slot_head
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_HEAD))

/datum/predicate/equip_slot/shoes
	slot = slot_shoes
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_FEET))

/datum/predicate/equip_slot/suit
	slot = slot_wear_suit
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_SUIT))

/datum/predicate/equip_slot/uniform
	slot = slot_w_uniform
	spec = list(REQ_TAG(PRED_TARGET, TAG_WEAR_UNIFORM))

/// Ears: a two-ear item needs the other ear free.
/datum/predicate/equip_slot/ear

/datum/predicate/equip_slot/ear/left
	slot = slot_l_ear
	spec = list(
		REQ_ANY(REQ_TAG(PRED_TARGET, TAG_WEAR_EARS), REQ_TAG(PRED_TARGET, TAG_WEAR_TWO_EARS)),
		REQ_BECAUSE(REQ_ANY(REQ_AT_MOST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_TINY)), REQ_TAG(PRED_TARGET, TAG_WEAR_EARS)), "too big for an ear"),
		REQ_ANY(REQ_NO_TAG(PRED_TARGET, TAG_WEAR_TWO_EARS), REQ_PROC(/proc/dq_equip_right_ear_free, null)),
	)

/datum/predicate/equip_slot/ear/right
	slot = slot_r_ear
	spec = list(
		REQ_ANY(REQ_TAG(PRED_TARGET, TAG_WEAR_EARS), REQ_TAG(PRED_TARGET, TAG_WEAR_TWO_EARS)),
		REQ_BECAUSE(REQ_ANY(REQ_AT_MOST(PRED_TARGET, PROP_SIZE_CLASS, SIZE_CLASS(ITEMSIZE_TINY)), REQ_TAG(PRED_TARGET, TAG_WEAR_EARS)), "too big for an ear"),
		REQ_ANY(REQ_NO_TAG(PRED_TARGET, TAG_WEAR_TWO_EARS), REQ_PROC(/proc/dq_equip_left_ear_free, null)),
	)

/datum/predicate/equip_slot/tie
	slot = slot_tie
	spec = list(
		REQ_TAG(PRED_TARGET, TAG_WEAR_TIE),
		REQ_PROC(/proc/dq_equip_accessory_attachable, null),
	)

/datum/predicate/equip_slot/handcuffs
	slot = slot_handcuffed
	spec = list(REQ_BECAUSE(REQ_ALL(REQ_TYPE(PRED_TARGET, list(/obj/item/handcuffs)), REQ_NOT_TYPE(PRED_TARGET, list(/obj/item/handcuffs/legcuffs))), "only handcuffs go there"))

/datum/predicate/equip_slot/legcuffs
	slot = slot_legcuffed
	spec = list(REQ_BECAUSE(REQ_TYPE(PRED_TARGET, list(/obj/item/handcuffs/legcuffs)), "only legcuffs go there"))

/datum/predicate/equip_slot/backpack
	slot = slot_in_backpack
	spec = list(REQ_PROC(/proc/dq_equip_backpack_takes, null))

/// The compiled slot predicate for `slot`, or null for slots with no rules (hands, legs).
/proc/dq_equip_slot_predicate(slot)
	var/static/list/by_slot
	if(!by_slot)
		by_slot = list()
		by_slot.len = SLOT_TOTAL
		for(var/path in subtypesof(/datum/predicate/equip_slot))
			var/datum/predicate/equip_slot/P = path
			var/id = initial(P.slot)
			if(id)
				by_slot[id] = dq_predicate(path)
	if(!isnum(slot) || slot < 1 || slot > SLOT_TOTAL)
		return null
	return by_slot[slot]

/// The old slot_flags enumeration, kept for callers that ask "does this slot
/// suit this item" without a mob (worn checks in equipped()).
/proc/dq_item_fits_slot_flags(obj/item/I, slot)
	switch(slot)
		if(slot_wear_mask)
			return HAS_TAG(I, TAG_WEAR_MASK)
		if(slot_back)
			return HAS_TAG(I, TAG_WEAR_BACK)
		if(slot_wear_suit)
			return HAS_TAG(I, TAG_WEAR_SUIT)
		if(slot_gloves)
			return HAS_TAG(I, TAG_WEAR_GLOVES)
		if(slot_shoes)
			return HAS_TAG(I, TAG_WEAR_FEET)
		if(slot_belt)
			return HAS_TAG(I, TAG_WEAR_BELT)
		if(slot_glasses)
			return HAS_TAG(I, TAG_WEAR_EYES)
		if(slot_head)
			return HAS_TAG(I, TAG_WEAR_HEAD)
		if(slot_l_ear, slot_r_ear)
			return HAS_TAG(I, TAG_WEAR_EARS) || HAS_TAG(I, TAG_WEAR_TWO_EARS)
		if(slot_w_uniform)
			return HAS_TAG(I, TAG_WEAR_UNIFORM)
		if(slot_wear_id)
			return HAS_TAG(I, TAG_WEAR_ID)
		if(slot_tie)
			return HAS_TAG(I, TAG_WEAR_TIE)
	return FALSE

// ---- Equipping ----

/// Why `M` can't equip this in `slot`, or null if it can.
/// `go_over_slot`: allow an occupied slot. Null uses the item's TAG_WEAR_OVER.
/// Unless `disable_warning`, the reason is shown to `M`.
/obj/item/proc/equip_refusal(mob/M, slot, disable_warning = FALSE, ignore_obstruction = FALSE, go_over_slot = null)
	. = dq_equip_refusal(src, M, slot, disable_warning, ignore_obstruction, go_over_slot)
	if(. && !disable_warning && M)
		to_chat(M, span_warning("You can't wear \the [src] there: [.]."))

/proc/dq_equip_refusal(obj/item/I, mob/M, slot, disable_warning, ignore_obstruction, go_over_slot)
	if(!slot || !M)
		return "there's nowhere to put it"
	var/id = dq_slot_id(slot)
	if(!id)
		// Action slots (backpack, accessory): the slot rules are all there is.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species && !(slot in dq_equip_slots_of(H)))
				return "you have nowhere to wear it"
		var/datum/predicate/slot_rules = dq_equip_slot_predicate(slot)
		if(!slot_rules)
			return "you have nowhere to wear it"
		. = slot_rules.why_not(M, I, null)
		if(.)
			return .
		return dq_equip_item_refusal(I, M, slot)
	// The mob's slot list says whether it has the slot; the slot's definition
	// (its body part, then its equip_slot predicate) whether it takes the item.
	var/datum/ledger/L = dq_ledger(M)
	var/datum/slot_def/def = L?.def_by_id(id)
	if(!def)
		return ishuman(M) ? "you have nowhere to wear it" : "you can't wear things"
	. = def.refusal(M, I, M)
	if(.)
		return .
	// Capacity: one item per equip slot, unless this one goes on over it.
	if(isnull(go_over_slot))
		go_over_slot = HAS_TAG(I, TAG_WEAR_OVER)
	var/obj/item/present = M.get_equipped_item(id)
	if(present && present != I && !go_over_slot)
		return "you're already wearing 	he [present] there"
	if(!ignore_obstruction && !M.slot_is_accessible(slot, I, disable_warning ? null : M))
		return "something is in the way"
	return dq_equip_item_refusal(I, M, slot)

/// The item's own constraints on its wearer: fit (except in pockets and suit
/// storage) and equip.
/proc/dq_equip_item_refusal(obj/item/I, mob/M, slot)
	if(slot != slot_l_store && slot != slot_r_store && slot != slot_s_store)
		. = dq_constraint_refusal(I, CONSTRAINT_FIT, I, M)
		if(.)
			return .
	return dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, M)

/// The equip slots a human's species has.
/proc/dq_equip_slots_of(mob/living/carbon/human/H)
	var/static/list/none = list()
	return H.species?.hud?.equip_slots || none

// ---- Slot rules (REQ_PROC clauses: (actor, target, held) -> TRUE or a reason) ----

/proc/dq_equip_has_uniform(mob/living/carbon/human/H, obj/item/I)
	if(!ishuman(H) || H.get_equipped_item(SLOT_ID_UNIFORM) || !(slot_w_uniform in dq_equip_slots_of(H)))
		return TRUE
	return "you need a jumpsuit first"

/proc/dq_equip_suit_storage_takes(mob/living/carbon/human/H, obj/item/I)
	if(!ishuman(H))
		return "there's nowhere to put it"
	var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
	if(!suit)
		return "you need a suit first"
	var/datum/predicate/P = dq_constraint(suit, CONSTRAINT_SUIT_STORAGE)
	if(!P)
		return "\the [suit] has no suit storage"
	if(istype(I, /obj/item/pda) || istype(I, /obj/item/pen))
		return TRUE
	return P.why_not(H, I, null) || TRUE

/proc/dq_equip_glove_layering(mob/living/carbon/human/H, obj/item/I)
	if(!ishuman(H) || !istype(I, /obj/item/clothing/gloves))
		return TRUE
	var/obj/item/clothing/gloves/new_gloves = I
	if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/accessory))
		var/obj/item/clothing/accessory/ring = H.get_equipped_item(SLOT_ID_GLOVES)
		if(ring.glove_level >= new_gloves.glove_level)
			return "\the [ring] is in the way"
	else if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/worn = H.get_equipped_item(SLOT_ID_GLOVES)
		if(worn.glove_level >= new_gloves.glove_level || worn.overgloves)
			return "\the [worn] are in the way"
	return TRUE

/proc/dq_equip_left_ear_free(mob/living/carbon/human/H, obj/item/I)
	return (ishuman(H) && H.get_equipped_item(slot_l_ear)) ? "it needs both ears free" : TRUE

/proc/dq_equip_right_ear_free(mob/living/carbon/human/H, obj/item/I)
	return (ishuman(H) && H.get_equipped_item(slot_r_ear)) ? "it needs both ears free" : TRUE

/proc/dq_equip_accessory_attachable(mob/living/carbon/human/H, obj/item/I)
	if(ishuman(H))
		for(var/obj/item/clothing/C in H.worn_clothing)
			if(C.can_attach_accessory(I))
				return TRUE
	return "you're not wearing anything you can attach it to"

/proc/dq_equip_backpack_takes(mob/living/carbon/human/H, obj/item/I)
	var/obj/item/storage/backpack/B = ishuman(H) ? H.get_equipped_item(SLOT_ID_BACK) : null
	if(!istype(B))
		return "you have no backpack"
	return B.insert_refusal(I, H) || TRUE
