MATERIAL_MIX(/obj/item/disk/tech_disk, list(MAT_STEEL = 30, MAT_GLASS = 10))
/obj/item/disk/tech_disk
	name = "technology disk"
	desc = "A disk for storing technology data for further research."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-blue"
	item_state = "card-id"
	w_class = ITEMSIZE_SMALL
	/// The disk's own scratch web (a private copy it owns), or a registered round web (the debug disk).
	var/tmp/datum/techweb/stored_research_static

/obj/item/disk/tech_disk/proc/disk_tech_disk_setup()
	if(!stored_research())
		proto_set(src, nameof(stored_research_static), new /datum/techweb/disk)

/obj/item/disk/tech_disk/debug
	name = "\improper CentCom technology disk"
	desc = "A debug item for research"

CAPABILITIES(/obj/item/disk/tech_disk/debug)
	setup(PROC_REF(link_admin_techweb))

/// Its setup hook: the debug disk holds the admin techweb.
/obj/item/disk/tech_disk/debug/proc/link_admin_techweb()
	proto_set(src, nameof(stored_research_static), locate_in_list(SSresearch.techwebs, /datum/techweb/admin))

MATERIAL_MIX(/obj/item/disk/design_disk, list(MAT_STEEL = 30, MAT_GLASS = 10))
/obj/item/disk/design_disk
	name = "component design disk"
	desc = "A disk for storing device design data for construction in lathes."
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-purple"
	item_state = "card-id"
	w_class = ITEMSIZE_SMALL

	///List of all `/datum/design` stored on the disk.
	var/list/blueprints

CAPABILITIES(/obj/item/disk/design_disk)
	configure(item_handling(randpixel = 5))
	rolls(ROLL_PIXEL, PIXEL_JITTER(PROC_REF(randpixel_range)))

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

CAPABILITIES(/obj/item/disk/tech_disk)
	configure(item_handling(randpixel = 5))
	rolls(ROLL_PIXEL, PIXEL_JITTER(PROC_REF(randpixel_range)))
	setup(PROC_REF(disk_tech_disk_setup))
	owns_one(nameof(stored_research_static), on_destroy = ON_DESTROY_PRIVATE_COPY)
