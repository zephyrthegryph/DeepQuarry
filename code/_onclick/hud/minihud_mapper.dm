// Specific types
/datum/mini_hud/mapper
	var/owner_handle

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	src.owner_handle = om_handle(owner)
	screenobjs = list(new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

// the mapping unit points at its hud datum; the hud going clears those vars.
/datum/mini_hud/mapper/on_destroy(force)
	owner()?.hud_item = null
	owner()?.hud_datum = null
	..()

/// LC-refs: the mapping unit this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/mapper/proc/owner() as /obj/item/mapping_unit
	return om_resolve(owner_handle)
