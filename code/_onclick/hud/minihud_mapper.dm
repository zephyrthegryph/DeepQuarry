// Specific types
/datum/mini_hud/mapper
	var/obj/item/mapping_unit/owner

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	rel_set(src, "owner", owner)
	screenobjs = list(new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

// The mapping unit points at its hud datum and at the holder screen object; each
// going clears the var naming it (the holder declares its own).

/// LC-refs: the mapping unit this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/mapper/proc/owner() as /obj/item/mapping_unit
	return owner

REL_PAIR(/datum/mini_hud/mapper, owner, hud_datum)
REL_PAIR(/obj/item/mapping_unit, hud_datum, owner)
