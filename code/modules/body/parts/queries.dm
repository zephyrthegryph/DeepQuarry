// Part queries (doc/medical_frameworks.md §2.3, slice O2).
//
// The ledger's tree slots are the truth; these read it, or the hook-maintained
// caches where a lookup must be O(1). O3 converts the ~400 direct reads of
// organs_by_name / internal_organs_by_name / organs / internal_organs to these
// and then drops the mob-side caches.

/// The attached external part tagged `tag` (BP_*), or null. O(1).
/datum/body/proc/part(tag)
	return owner.organs_by_name?[tag]

/// The attached internal organ tagged `tag` (O_*), or null. O(1).
/datum/body/proc/organ(tag)
	return owner.internal_organs_by_name?[tag]

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
	var/list/entry = E.ledger?.entries[src]
	if(!entry || !(entry[LEDGER_E_SLOT] == SLOT_ID_PART_CHILD || entry[LEDGER_E_SLOT] == SLOT_ID_PART_ORGANS))
		return null
	return E

/// This limb's child limbs.
/obj/item/organ/external/proc/child_parts()
	return slot_contents(SLOT_ID_PART_CHILD)

/// The internal organs this limb holds.
/obj/item/organ/external/proc/held_organs()
	return slot_contents(SLOT_ID_PART_ORGANS)
