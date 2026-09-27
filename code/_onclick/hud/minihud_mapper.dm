// Specific types
/datum/mini_hud/mapper
	var/obj/item/mapping_unit/owner

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	src.owner = owner
	screenobjs = list(new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

REF_PAIR(/datum/mini_hud/mapper, list("owner" = "hud_datum"))
REF_PAIR(/atom/movable/screen/movable/mapper_holder, list("owner" = "hud_item"))
REF_PAIR(/obj/item/mapping_unit, list("hud_datum" = "owner", "hud_item" = "owner"))
