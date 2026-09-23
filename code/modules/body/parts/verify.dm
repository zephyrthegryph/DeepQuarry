// Part tree verification (doc/medical_frameworks.md §2.2 and §2.10, slice O2).
//
// verify_body_tree() recomputes everything the attach/detach hooks derive
// from the ledger and compares: ownership, the owner caches, the tree caches
// and where afflictions sit. Tests call it after every step; it returns the
// faults as strings, empty when the tree is sound.

/// The faults in `M`'s part tree, or an empty list.
/proc/verify_body_tree(mob/living/M)
	. = list()
	if(!M?.body)
		return
	var/list/tree = list()
	var/obj/item/organ/root = M.slot_item(SLOT_ID_PART_ROOT)
	if(root)
		tree = dq_part_subtree(root)
	else
		for(var/obj/item/organ/O in M.slot_contents(SLOT_ID_BODY))
			tree += O

	// Every part in the tree is owned, cached and linked to its parent.
	for(var/obj/item/organ/part as anything in tree)
		if(part.owner != M)
			. += "[part] ([part.type]) is in [M]'s tree but owned by [part.owner || "nobody"]"
		if(part.resolve_owner() != M)
			. += "[part] ([part.type]) resolves to [part.resolve_owner() || "nobody"], not [M]"
		if(istype(part, /obj/item/organ/external))
			if(!(part in M.organs))
				. += "[part] is attached but not in [M].organs"
			if(M.organs_by_name?[part.organ_tag] != part)
				. += "organs_by_name\[[part.organ_tag]] is [M.organs_by_name?[part.organ_tag]], not [part]"
		else
			if(!(part in M.internal_organs))
				. += "[part] is attached but not in [M].internal_organs"
			if(M.internal_organs_by_name?[part.organ_tag] != part)
				. += "internal_organs_by_name\[[part.organ_tag]] is [M.internal_organs_by_name?[part.organ_tag]], not [part]"
		var/obj/item/organ/external/E = part
		if(istype(E))
			. += dq_verify_limb_links(E)

	// Nothing else is cached.
	for(var/obj/item/organ/O as anything in M.organs)
		if(!(O in tree))
			. += "[M].organs lists [O] ([O?.type]), which is not in the tree"
	for(var/obj/item/organ/O as anything in M.internal_organs)
		if(!(O in tree))
			. += "[M].internal_organs lists [O] ([O?.type]), which is not in the tree"
	for(var/tag in M.organs_by_name)
		if(!(M.organs_by_name[tag] in tree))
			. += "organs_by_name\[[tag]] holds [M.organs_by_name[tag]], which is not in the tree"
	for(var/tag in M.internal_organs_by_name)
		if(!(M.internal_organs_by_name[tag] in tree))
			. += "internal_organs_by_name\[[tag]] holds [M.internal_organs_by_name[tag]], which is not in the tree"

	// Located afflictions sit on attached parts.
	for(var/location in M.body.afflictions_by_location)
		var/obj/item/organ/O = location
		if(istype(O) && !(O in tree))
			. += "an affliction on [O] ([O.type]) is in [M]'s body, but [O] is not attached"
		for(var/datum/affliction/A as anything in M.body.afflictions_by_location[location])
			if(A.location != location || A.owner != M)
				. += "[A.type] is indexed on [location] but sits on [A.location] owned by [A.owner]"

	// No part below this mob is lost to nullspace.
	for(var/obj/item/organ/part as anything in tree)
		if(!part.loc && !QDELETED(part))
			. += "[part] ([part.type]) is in nullspace"

/// The faults in one limb's tree caches against its slots.
/proc/dq_verify_limb_links(obj/item/organ/external/E)
	. = list()
	var/list/kids = E.slot_contents(SLOT_ID_PART_CHILD)
	var/list/inner = E.slot_contents(SLOT_ID_PART_ORGANS)
	if(length(kids) != LAZYLEN(E.children) || length(kids - E.children))
		. += "[E].children ([jointext(E.children || list(), ", ")]) differs from its child slot ([jointext(kids, ", ")])"
	if(length(inner) != LAZYLEN(E.internal_organs) || length(inner - E.internal_organs))
		. += "[E].internal_organs ([jointext(E.internal_organs || list(), ", ")]) differs from its organ slot ([jointext(inner, ", ")])"
	for(var/obj/item/organ/external/child as anything in kids)
		if(child.parent != E)
			. += "[child].parent is [child.parent], not [E]"

/// The faults of a part that is not attached to any body: no owner, and its
/// afflictions ride it detached.
/proc/verify_detached_part(obj/item/organ/part)
	. = list()
	for(var/obj/item/organ/O as anything in dq_part_subtree(part))
		if(O.owner)
			. += "[O] ([O.type]) is detached but owned by [O.owner]"
		for(var/datum/affliction/A as anything in O.detached_afflictions)
			if(A.body || A.location != O)
				. += "[A.type] rides [O] but has body [A.body] and location [A.location]"
		if(!O.loc && !QDELETED(O))
			. += "[O] ([O.type]) is in nullspace"
