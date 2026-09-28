// Specific types
/datum/mini_hud/mapper
	var/owner_handle

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	src.owner_handle = om_handle(owner)
	screenobjs = list(new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

// The mapping unit points at its hud datum and at the holder screen object; each
// going clears the var naming it (the holder declares its own).
DECLARE_REF(/datum/mini_hud/mapper, "owner_handle", BACK_HANDLE, "hud_datum")

/// LC-refs: the mapping unit this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/mapper/proc/owner() as /obj/item/mapping_unit
	return om_resolve(owner_handle)
