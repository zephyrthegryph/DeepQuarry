// How an item is placed and handled: the item_handling() type trait (doc/rewrite/proposals/base_vars.md). Its values are per-type data in
// CAPABILITIES (configure(item_handling(center_x = 8, center_y = 4))), read with handling_of(I).center_x.
//
//   center_x / center_y   where the item's sprite balances when placed on a table (auto_align()); 0, 0 means it is scattered by randpixel instead
//   randpixel             the range of the random pixel offset an item takes when it is scattered
//   preserve              nonzero: cryo-storage and the gateway keep the item with its owner
//   no_attack_log         nonzero: hitting with the item writes no attack log
//   no_random_knockdown   TRUE: the item can never knock people down at random in combat
//   zoom_name   what a scope or binoculars call themselves when zooming
//   cavity_implantable   FALSE: surgery cannot implant it in a body cavity
//
// A value that changes at run time (a glass taking the look of its drink) is written with set_<old var>(), which gives the item its own copy
// and publishes ITEM_HANDLING_KEY.

STATIC_ENTRY(item_handling)

/proc/item_handling(center_x = null, center_y = null, randpixel = null, preserve = null, no_attack_log = null, no_random_knockdown = null, zoom_name = null, cavity_implantable = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_HANDLING, null, list("center_x" = center_x, "center_y" = center_y, "randpixel" = randpixel, "preserve" = preserve, "no_attack_log" = no_attack_log, "no_random_knockdown" = no_random_knockdown, "zoom_name" = zoom_name, "cavity_implantable" = cavity_implantable))

/datum/type_trait/item_handling
	var/center_x = 16
	var/center_y = 16
	var/randpixel = 6
	var/preserve = 0
	var/no_attack_log = 0
	var/no_random_knockdown = FALSE
	var/zoom_name = null
	var/cavity_implantable = TRUE

/datum/type_trait/item_handling/copy_values(datum/type_trait/item_handling/into)
	into.center_x = center_x
	into.center_y = center_y
	into.randpixel = randpixel
	into.preserve = preserve
	into.no_attack_log = no_attack_log
	into.no_random_knockdown = no_random_knockdown
	into.zoom_name = zoom_name
	into.cavity_implantable = cavity_implantable

/datum/entry_engine/type_trait/item_handling
	kind = ENTRY_ITEM_HANDLING
	trait_type = /datum/type_trait/item_handling
	publish_key = ITEM_HANDLING_KEY
	base_type = /obj/item
	var_names = list("center_of_mass_x" = "center_x", "center_of_mass_y" = "center_y", "randpixel" = "randpixel", "preserve_item" = "preserve", "no_attack_log" = "no_attack_log", "no_random_knockdown" = "no_random_knockdown", "zoomdevicename" = "zoom_name", "cavity_implantable" = "cavity_implantable")

/// The holder's item_handling values (its own once one was set at run time). Read only.
READS_AS(/proc/handling_of, ITEM_HANDLING_KEY)
/proc/handling_of(obj/item/holder) as /datum/type_trait/item_handling
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_HANDLING)

/// What a type declares (no instance): the old initial().
/proc/handling_of_type(type) as /datum/type_trait/item_handling
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_HANDLING)

/obj/item/proc/set_center_of_mass_x(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "center_x", value)

/obj/item/proc/set_center_of_mass_y(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "center_y", value)

/obj/item/proc/set_randpixel(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "randpixel", value)

/obj/item/proc/set_preserve_item(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "preserve", value)

/obj/item/proc/set_no_attack_log(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "no_attack_log", value)

/obj/item/proc/set_no_random_knockdown(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "no_random_knockdown", value)

/obj/item/proc/set_zoomdevicename(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "zoom_name", value)

/obj/item/proc/set_cavity_implantable(value)
	return set_trait(src, ENTRY_ITEM_HANDLING, "cavity_implantable", value)

/// The range of this item's random pixel offset (what a PIXEL_JITTER(PROC_REF(randpixel_range)) roll reads).
/obj/item/proc/randpixel_range()
	return handling_of(src).randpixel
