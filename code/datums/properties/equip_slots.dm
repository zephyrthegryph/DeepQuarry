// Equip slot constraints (doc/rewrite/rules.md §3, roadmap P3).
//
// What each equip slot accepts is declared once, in the native catalog at the
// end of this file (GLOB.native_equipment_acceptance), with the wearer as the
// context's wearer and the item as the candidate.
//
// equip_refusal() asks the mob's ledger slot (C3): the mob's slot list says
// whether it has the slot, the slot's refusal() whether its body part is there
// and the catalog takes the item, its capacity whether it is free. Then
// reachability and the item's own constraints (CONSTRAINT_FIT except in pockets
// and suit storage, and CONSTRAINT_EQUIP everywhere).

/// The old slot_flags enumeration, kept for callers that ask "does this slot
/// suit this item" without a mob (worn checks in equipped()).
/proc/dq_item_fits_slot_flags(obj/item/I, slot)
	var/static/alist/tags_by_slot = alist(
		SLOT_ID_MASK = list(TAG_WEAR_MASK),
		SLOT_ID_BACK = list(TAG_WEAR_BACK),
		SLOT_ID_SUIT = list(TAG_WEAR_SUIT),
		SLOT_ID_GLOVES = list(TAG_WEAR_GLOVES),
		SLOT_ID_SHOES = list(TAG_WEAR_FEET),
		SLOT_ID_BELT = list(TAG_WEAR_BELT),
		SLOT_ID_EYES = list(TAG_WEAR_EYES),
		SLOT_ID_HEAD = list(TAG_WEAR_HEAD),
		SLOT_ID_EAR_L = list(TAG_WEAR_EARS, TAG_WEAR_TWO_EARS),
		SLOT_ID_EAR_R = list(TAG_WEAR_EARS, TAG_WEAR_TWO_EARS),
		SLOT_ID_UNIFORM = list(TAG_WEAR_UNIFORM),
		SLOT_ID_ID = list(TAG_WEAR_ID),
		SLOT_ID_TIE = list(TAG_WEAR_TIE),
	)
	for(var/tag in tags_by_slot[slot])
		if(HAS_TAG(I, tag))
			return TRUE
	return FALSE

// ---- Equipping ----

/// Why `M` can't equip this in `slot`, or null if it can.
/// `go_over_slot`: allow an occupied slot. Null uses the item's TAG_WEAR_OVER.
/// `actor`: who puts it on `M` (a stripper dressing a victim); null means `M` itself.
/// Unless `disable_warning`, the reason is shown to the actor.
/obj/item/proc/equip_refusal(mob/M, slot, disable_warning = FALSE, ignore_obstruction = FALSE, go_over_slot = null, mob/actor = null)
	. = dq_equip_refusal(src, M, slot, disable_warning, ignore_obstruction, go_over_slot, actor)
	var/mob/told = actor || M
	if(. && !disable_warning && told)
		to_chat(told, span_warning("You can't wear \the [src] there: [.]."))

/// The stated order (admission.md D2h): the wearer has the slot, the slot's holder state and catalog, occupancy, reach, the item's
/// own fit and equip constraints, then the needs() an item type declares on /datum/act/equip (its holder is the item, its target the wearer).
/proc/dq_equip_refusal(obj/item/I, mob/M, slot, disable_warning, ignore_obstruction, go_over_slot, mob/actor = null)
	if(!slot || !M)
		return "there's nowhere to put it"
	if(!actor)
		actor = M
	var/datum/relation_definition/slot/def = dq_ledger(M)?.def_by_id(slot)
	if(!def && (slot == SLOT_ID_IN_BACKPACK || slot == SLOT_ID_TIE))
		// Action slots (backpack, accessory): the slot rules are all there is.
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(H.species && !(slot in dq_equip_slots_of(H)))
				return "you have nowhere to wear it"
		if(!acceptance_declared(GLOB.native_equipment_acceptance, slot))
			return "you have nowhere to wear it"
		. = dq_native_equip_slot_reason(M, slot, I, actor)
		if(.)
			return .
		return dq_equip_item_refusal(I, M, slot, actor)
	// The mob's slot list says whether it has the slot; the slot's definition
	// (its body part, then the catalog) whether it takes the item.
	if(!def)
		return ishuman(M) ? "you have nowhere to wear it" : "you can't wear things"
	. = def.refusal(M, I, actor)
	if(.)
		return .
	// Capacity: one item per equip slot, unless this one goes on over it.
	if(isnull(go_over_slot))
		go_over_slot = HAS_TAG(I, TAG_WEAR_OVER)
	var/obj/item/present = M.get_equipped_item(slot)
	if(present && present != I && !go_over_slot)
		return "you're already wearing \the [present] there"
	if(!ignore_obstruction && !M.slot_is_accessible(slot, I, disable_warning ? null : M))
		return "something is in the way"
	return dq_equip_item_refusal(I, M, slot, actor)

/// The item's own constraints on its wearer: fit (except in pockets and suit
/// storage) and equip.
/proc/dq_equip_item_refusal(obj/item/I, mob/M, slot, mob/actor = null)
	if(slot != SLOT_ID_POCKET_L && slot != SLOT_ID_POCKET_R && slot != SLOT_ID_SUIT_STORAGE)
		. = dq_constraint_refusal(I, CONSTRAINT_FIT, I, M)
		if(.)
			return .
	. = dq_constraint_refusal(I, CONSTRAINT_EQUIP, I, M)
	if(.)
		return .
	return reason_text(op_transfer_precheck(I, /datum/act/equip, M, slot, actor || M))

/// The equip slots a human's species has.
/proc/dq_equip_slots_of(mob/living/carbon/human/H)
	var/static/list/none = list()
	return H.species?.hud?.equip_slots || none

// Native slot declaration catalog: plans compile once, contexts carry the real wearer.
GLOBAL_DATUM_INIT(native_equipment_acceptance, /datum/native_equipment_acceptance, new)
LIFECYCLE_KEEP_UNLESS_FORCED(/datum/native_equipment_acceptance)
/datum/native_equipment_acceptance

CAPABILITIES(/datum/native_equipment_acceptance)
	acceptance(SLOT_ID_BACK, req_acceptance_tag(TAG_WEAR_BACK), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_BELT, req_acceptance_tag(TAG_WEAR_BELT), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_ID, req_acceptance_tag(TAG_WEAR_ID), req_acceptance_has_uniform(), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_SUIT_STORAGE, req_acceptance_suit_storage_takes(), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_POCKET_L, req_acceptance_has_uniform(), req_acceptance_tag(TAG_NO_POCKET, exclude = TRUE), req_acceptance_either(list(req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS), req_acceptance_tag(TAG_POCKETABLE)), "too big for a pocket"), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_POCKET_R, req_acceptance_has_uniform(), req_acceptance_tag(TAG_NO_POCKET, exclude = TRUE), req_acceptance_either(list(req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS), req_acceptance_tag(TAG_POCKETABLE)), "too big for a pocket"), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_EYES, req_acceptance_tag(TAG_WEAR_EYES), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_MASK, req_acceptance_tag(TAG_WEAR_MASK), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_GLOVES, req_acceptance_tag(TAG_WEAR_GLOVES), req_acceptance_glove_layering(), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_HEAD, req_acceptance_tag(TAG_WEAR_HEAD), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_SHOES, req_acceptance_tag(TAG_WEAR_FEET), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_SUIT, req_acceptance_tag(TAG_WEAR_SUIT), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_UNIFORM, req_acceptance_tag(TAG_WEAR_UNIFORM), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_EAR_L, any_of(req_acceptance_tag(TAG_WEAR_EARS), req_acceptance_tag(TAG_WEAR_TWO_EARS)), req_acceptance_either(list(req_acceptance_max_size(ITEMSIZE_TINY, PROP_UNIT_SIZE_CLASS), req_acceptance_tag(TAG_WEAR_EARS)), "too big for an ear"), any_of(req_acceptance_tag(TAG_WEAR_TWO_EARS, exclude = TRUE), req_acceptance_right_ear_free()), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_EAR_R, any_of(req_acceptance_tag(TAG_WEAR_EARS), req_acceptance_tag(TAG_WEAR_TWO_EARS)), req_acceptance_either(list(req_acceptance_max_size(ITEMSIZE_TINY, PROP_UNIT_SIZE_CLASS), req_acceptance_tag(TAG_WEAR_EARS)), "too big for an ear"), any_of(req_acceptance_tag(TAG_WEAR_TWO_EARS, exclude = TRUE), req_acceptance_left_ear_free()), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_TIE, req_acceptance_tag(TAG_WEAR_TIE), req_acceptance_accessory_attachable(), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_HANDCUFFED, req_acceptance_both(list(req_acceptance_type(/obj/item/handcuffs), req_acceptance_type(/obj/item/handcuffs/legcuffs, exclude = TRUE)), "only handcuffs go there"), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_LEGCUFFED, req_acceptance_type(/obj/item/handcuffs/legcuffs, because = "only legcuffs go there"), mode = ACCEPTANCE_REPLACE)
	acceptance(SLOT_ID_IN_BACKPACK, req_acceptance_backpack_takes(), mode = ACCEPTANCE_REPLACE)

/proc/req_acceptance_either(list/parts, because)
	return part_make(/datum/entry/part/req/acceptance_either, list("because" = because), parts)
/datum/entry/part/req/acceptance_either
	parent_type = /datum/entry/part/req/any
/datum/entry/part/req/acceptance_either/refusal(datum/act/op/A)
	return req_reason_value(A, src.args["because"], default_reason)

/proc/req_acceptance_both(list/parts, because)
	return part_make(/datum/entry/part/req/acceptance_both, list("because" = because), parts)
/datum/entry/part/req/acceptance_both
	parent_type = /datum/entry/part/req/all
/datum/entry/part/req/acceptance_both/refusal(datum/act/op/A)
	return req_reason_value(A, src.args["because"], default_reason)

/// The catalog's answer for `candidate` in `wearer`'s `slot`; the actor is `mover` (who puts it there), the wearer when null (admission.md D2m).
/proc/dq_native_equip_slot_reason(mob/wearer, slot, atom/movable/candidate, mob/mover)
	return acceptance_reason(GLOB.native_equipment_acceptance, slot, wearer, candidate, wearer, mover || wearer, slot)

/proc/dq_native_equip_slot_reads(mob/wearer, slot, atom/movable/candidate, mob/mover)
	return acceptance_read_keys(GLOB.native_equipment_acceptance, slot, wearer, candidate, wearer, mover || wearer, slot)
