// Specific types
/datum/mini_hud/mapper
	var/owner_handle

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	src.owner_handle = om_handle(owner)
	screenobjs = list(new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

/datum/mini_hud/mapper/Destroy()
	owner()?.hud_item = null
	owner()?.hud_datum = null
	return ..()

/// LC-refs: the mapping unit this hud shows -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/mapper/proc/owner() as /obj/item/mapping_unit
	return om_resolve(owner_handle)
