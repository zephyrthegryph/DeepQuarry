// Little define makes it cleaner to read the tripple color values out of mobs.
#define MENU_MAIN "Main"
#define MENU_BODYRECORDS "Body Records"
#define MENU_STOCKRECORDS "Stock Records"
#define MENU_SPECIFICRECORD "Specific Record"
#define MENU_OOCNOTES "OOC Notes"

/obj/machinery/computer/transhuman/designer
	name = "body design console"
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	icon = 'icons/obj/computer.dmi'
	icon_keyboard = "med_key"
	icon_screen = "explosive"
	light_color = "#315ab4"
	circuit = /obj/item/circuitboard/body_designer
	req_access = list(ACCESS_MEDICAL) // Used for loading people's designs
	var/datum/tgui_module/appearance_changer/body_designer/designer_gui
	var/obj/item/disk/body_record/disk = null
	var/selected_record = FALSE

	// Resleeving database this machine interacts with. Blank for default database
	// Needs a matching /datum/transcore_db with key defined in code
	var/db_key
	var/tmp/datum/transcore_db/our_db_static	// These persist all round and are never destroyed, just keep a hard ref

/obj/machinery/computer/transhuman/designer/Initialize(mapload)
	. = ..()
	our_db_static = GLOB.transcore_service.db_by_key(db_key)

OWN(/obj/machinery/computer/transhuman/designer, disk, OWN_SPILL)

/obj/machinery/computer/transhuman/designer/dismantle()
	if(disk)
		disk.forceMove(get_turf(src))
		own_take(src, "disk")
	. = ..()

EXTEND_INTERACTIONS(/obj/machinery/computer/transhuman/designer, \
	INTERACT_INSERT(/obj/item/disk/body_record, PROC_REF(body_designer_interaction_insert_disk), "Insert disk"), \
	INTERACT_HAND_UNGATED(null, PROC_REF(body_designer_interaction_hand)), \
)

/// Old attackby.
/obj/machinery/computer/transhuman/designer/proc/body_designer_interaction_insert_disk(mob/user, obj/item/W, datum/interaction/interaction)
	if(!own_set(src, nameof(src.disk), W, user = user))
		return INTERACTION_HANDLED_PASS
	to_chat(user, span_notice("You insert \the [W] into \the [src]."))
	SStgui.update_uis(src)
	return INTERACTION_HANDLED_PASS

/// Old attack_hand.
/obj/machinery/computer/transhuman/designer/proc/body_designer_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	add_fingerprint(user)
	if(!operable())
		return
	if(!designer_gui)
		own_set(src, "designer_gui", new /datum/tgui_module/appearance_changer/body_designer(src, null))
		rel_set(designer_gui, "linked_body_design_console", src)
		designer_gui.jiggle_map()
	if(!designer_gui.owner())
		designer_gui.make_fake_owner()
		selected_record = FALSE
	designer_gui.tgui_interact(user)

// Disk for manually moving body records between the designer and sleever console etc.
/obj/item/disk/body_record
	name = "Body Design Disk"
	desc = "It has a small label: \n\
	\"Portable Body Record Storage Disk. \n\
	Insert into resleeving control console\""
	icon = 'icons/obj/discs_vr.dmi'
	icon_state = "data-green"
	item_state = "card-id"
	w_class = ITEMSIZE_SMALL
	var/datum/transhuman/body_record/stored = null

/*
 *	Diskette Box
 */

/obj/item/storage/box/body_record_disk
	name = "body record disk box"
	desc = "A box of body record disks, apparently."
	icon_state = "disk_kit"

/obj/item/storage/box/body_record_disk/Initialize(mapload)
	. = ..()
	for(var/i = 0 to 7)
		new /obj/item/disk/body_record(src)

#undef MENU_MAIN
#undef MENU_BODYRECORDS
#undef MENU_STOCKRECORDS
#undef MENU_SPECIFICRECORD
#undef MENU_OOCNOTES


/// DECLARE_REF(..., STATIC): a shared definition/flyweight, held strongly and never cleared.
/obj/machinery/computer/transhuman/designer/proc/our_db() as /datum/transcore_db
	return our_db_static
