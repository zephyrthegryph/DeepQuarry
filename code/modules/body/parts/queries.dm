// Part queries (doc/medical_frameworks.md §2.3, slice O2).
//
// The ledger's tree slots are the truth; these read it, or the hook-maintained
// caches where a lookup must be O(1). O-slots deleted the internal organ caches
// (the mob's organ list and by-name map, and each limb's organ list):
// organ_in() and internal_organ_list() read the limbs' keyed organ slots.

/// The attached external part tagged `tag` (BP_*), or null. O(1).
/datum/body/proc/part(tag)
	return owner.organs_by_name?[tag]

/// The attached internal organ tagged `tag` (O_*), or null. O(1).
/datum/body/proc/organ(tag)
	return owner.organ_in(tag)

/// The root part (the torso) of this body's tree, or null for a body with no
/// part tree.
/datum/body/proc/root_part()
	return owner.slot_item(SLOT_ID_PART_ROOT)

/// Every attached external part, parents before children. For a mob with no
/// part tree: the loose limbs it owns.
/datum/body/proc/parts()
	. = list()
	var/obj/item/organ/root = root_part()
	if(!root)
		for(var/obj/item/organ/external/E in owner.slot_contents(SLOT_ID_BODY))
			if(E.owner == owner)
				. += E
		return
	for(var/obj/item/organ/external/E in dq_part_subtree(root))
		. += E

/// Every attached internal organ, in tree order. For a mob with no part tree:
/// the loose organs it owns.
/datum/body/proc/organs()
	. = list()
	var/obj/item/organ/root = root_part()
	if(!root)
		for(var/obj/item/organ/O in owner.slot_contents(SLOT_ID_BODY))
			if(O.owner == owner && !istype(O, /obj/item/organ/external))
				. += O
		return
	for(var/obj/item/organ/O in dq_part_subtree(root))
		if(!istype(O, /obj/item/organ/external))
			. += O

/// The limb this part hangs from, read from the ledger, or null.
/obj/item/organ/proc/parent_part()
	var/obj/item/organ/external/E = loc
	if(!istype(E))
		return null
	var/list/entry = E.containment_ledger()?.entries[src]
	if(!entry || !(entry[LEDGER_E_SLOT] == SLOT_ID_PART_CHILD || entry[LEDGER_E_SLOT] == SLOT_ID_PART_ORGANS))
		return null
	return E

/// This limb's child limbs.
/obj/item/organ/external/proc/child_parts()
	return slot_contents(SLOT_ID_PART_CHILD)

/// The internal organs this limb holds.
/obj/item/organ/external/proc/held_organs()
	return slot_contents(SLOT_ID_PART_ORGANS)

// ---- Organ slots (O-slots, code/__defines/body_parts.dm) ----

/// Whether this mob's plan hangs its parts from SLOT_ID_PART_ROOT (the root
/// slot's declared holder, part_slots.dm). Without one, organs sit loose in
/// SLOT_ID_BODY and belong to the mob there (attach.dm).
/mob/living/proc/has_part_tree()
	return istype(body, /datum/body/humanoid)

/// The attached internal organ keyed `tag` (O_*), or null. A keyed ledger
/// lookup in the limb that last held that tag (a learned, species-agnostic
/// hint: layouts are data in has_organ / parent_organ), then in every other
/// attached limb, since surgery and modifiers may relocate organs.
/mob/living/proc/organ_in(tag)
	if(isnull(tag))
		return null
	var/static/list/limb_hint = list()
	var/hint = limb_hint[tag]
	if(hint)
		var/obj/item/organ/external/E = organs_by_name?[hint]
		var/datum/ledger/EL = E?.containment_ledger()
		var/obj/item/organ/found = EL?.slot_lookup(SLOT_ID_PART_ORGANS, tag)
		if(found?.owner == src)
			return found
	for(var/obj/item/organ/external/E as anything in organs)
		var/datum/ledger/EL = E.containment_ledger()
		var/obj/item/organ/found = EL?.slot_lookup(SLOT_ID_PART_ORGANS, tag)
		// owner: a subtree being released lets its organs go before its limbs.
		if(found?.owner == src)
			limb_hint[tag] = E.organ_tag
			return found
	if(has_part_tree())
		return null
	// No tree: loose organs in the interior slot.
	var/datum/ledger/L = containment_ledger()
	for(var/obj/item/organ/O in L?.slots[SLOT_ID_BODY])
		if(O.organ_tag == tag && O.owner == src && !istype(O, /obj/item/organ/external))
			return O
	return null

/// Every attached internal organ, as a fresh list (safe to change while
/// iterating it): each attached limb's organ slot, limbs in attach order
/// (parents first), then for a mob with no part tree its loose organs.
/mob/living/proc/internal_organ_list()
	RETURN_TYPE(/list)
	. = list()
	for(var/obj/item/organ/external/E as anything in organs)
		var/datum/ledger/EL = E.containment_ledger()
		for(var/obj/item/organ/O as anything in EL?.slots[SLOT_ID_PART_ORGANS])
			if(O.owner == src)
				. += O
	if(has_part_tree())
		return
	var/datum/ledger/L = containment_ledger()
	for(var/obj/item/organ/O in L?.slots[SLOT_ID_BODY])
		if(O.owner == src && !istype(O, /obj/item/organ/external))
			. += O

/// Whether `thing` is one of this mob's attached internal organs.
/mob/living/proc/has_internal_organ(atom/movable/thing)
	var/obj/item/organ/O = thing
	return istype(O) && !istype(O, /obj/item/organ/external) && O.owner == src
