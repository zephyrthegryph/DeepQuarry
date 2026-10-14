// Specific types
/datum/mini_hud/mapper
	var/obj/item/mapping_unit/owner

/datum/mini_hud/mapper/New(datum/hud/other, owner)
	rel_set(src, nameof(owner), owner)
	rel_add(src, nameof(screenobjs), new /atom/movable/screen/movable/mapper_holder(null, owner))
	..()

// The mapping unit owns us as its hud_datum and views our holder screen object as hud_item;
// owner is a plain relation back.

/// The mapping unit this hud shows (a relation view: null once that is deleted).
/datum/mini_hud/mapper/proc/owner() as /obj/item/mapping_unit
	return owner

