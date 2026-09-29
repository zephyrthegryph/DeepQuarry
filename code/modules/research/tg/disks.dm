MATERIAL_MIX(/obj/item/disk/tech_disk, list(MAT_STEEL = 30, MAT_GLASS = 10))
/obj/item/disk/tech_disk
	name = "technology disk"
	desc = "A disk for storing technology data for further research."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-blue"
	item_state = "card-id"
	randpixel = 5
	w_class = ITEMSIZE_SMALL
	/// The disk's own scratch web (a private copy it owns), or a registered round web (the debug disk).
	var/tmp/datum/techweb/stored_research_static

/obj/item/disk/tech_disk/Initialize(mapload)
	. = ..()
	if(!stored_research())
		proto_set(src, "stored_research_static", new /datum/techweb/disk)
	randpixel_xy()

/obj/item/disk/tech_disk/debug
	name = "\improper CentCom technology disk"
	desc = "A debug item for research"

/obj/item/disk/tech_disk/debug/Initialize(mapload)
	proto_set(src, "stored_research_static", locate_in_list(GLOB.research_service.techwebs, /datum/techweb/admin))
	return ..()

MATERIAL_MIX(/obj/item/disk/design_disk, list(MAT_STEEL = 30, MAT_GLASS = 10))
/obj/item/disk/design_disk
	name = "component design disk"
	desc = "A disk for storing device design data for construction in lathes."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-purple"
	item_state = "card-id"
	randpixel = 5
	w_class = ITEMSIZE_SMALL

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

/// The disk's techweb: its own scratch web, or a shared round web.
/obj/item/disk/tech_disk/proc/stored_research() as /datum/techweb
	return stored_research_static

PROTO(/obj/item/disk/tech_disk, stored_research_static)
