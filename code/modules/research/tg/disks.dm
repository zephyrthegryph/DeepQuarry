/obj/item/disk/tech_disk
	name = "technology disk"
	desc = "A disk for storing technology data for further research."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-blue"
	item_state = "card-id"
	randpixel = 5
	w_class = ITEMSIZE_SMALL
	MATERIAL_MIX(list(MAT_STEEL = 30, MAT_GLASS = 10))
	var/tmp/stored_research_handle

/obj/item/disk/tech_disk/Initialize(mapload)
	. = ..()
	if(!stored_research())
		stored_research_handle = om_handle(new /datum/techweb/disk)
	randpixel_xy()

/obj/item/disk/tech_disk/debug
	name = "\improper CentCom technology disk"
	desc = "A debug item for research"

/obj/item/disk/tech_disk/debug/Initialize(mapload)
	stored_research_handle = om_handle(locate(/datum/techweb/admin) in SSresearch.techwebs)
	return ..()

/obj/item/disk/design_disk
	name = "component design disk"
	desc = "A disk for storing device design data for construction in lathes."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-purple"
	item_state = "card-id"
	randpixel = 5
	w_class = ITEMSIZE_SMALL
	MATERIAL_MIX(list(MAT_STEEL = 30, MAT_GLASS = 10))

	///List of all `/datum/design` stored on the disk.
	var/list/blueprints

/obj/item/disk/design_disk/Initialize(mapload)
	. = ..()
	randpixel_xy()

/**
 * Used for special interactions with a techweb when uploading the designs.
 * Args:
 * - stored_research - The techweb that's storing us.
 */
/obj/item/disk/design_disk/proc/on_upload(datum/techweb/stored_research, atom/research_source)
	return

/// LC-refs: the stored_research this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/disk/tech_disk/proc/stored_research() as /datum/techweb
	return om_resolve(stored_research_handle)
