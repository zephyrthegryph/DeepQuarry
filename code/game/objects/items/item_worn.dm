// How an item is worn: the item_worn() type trait (doc/rewrite/proposals/base_vars.md). slots, hides, covers, flags and worn_icon are
// per-type data in CAPABILITIES (configure(item_worn(slots = SLOT_BELT))), read with worn_of(I).slots; a run-time change (a hood up, a
// suit sealed) is set_<old var>(), which gives the item its own copy and publishes ITEM_WORN_KEY. Never mutate the shared datum: write
// set_item_flags(worn_of(src).flags | X).

STATIC_ENTRY(item_worn)

/proc/item_worn(slots = null, hides = null, covers = null, flags = null, worn_icon = null, layer = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_ITEM_WORN, null, list("slots" = slots, "hides" = hides, "covers" = covers, "flags" = flags, "worn_icon" = worn_icon, "layer" = layer))

/datum/type_trait/item_worn
	var/slots = 0	// SLOT_* flags: where it can be worn
	var/hides = 0	// HIDE* flags: what it hides when worn
	var/covers = 0	// body-part flags it covers
	var/flags = 0	// item flags for equippables
	var/layer = null
	var/worn_icon	// the default on-mob icon

/datum/type_trait/item_worn/copy_values(datum/type_trait/item_worn/into)
	into.slots = slots
	into.hides = hides
	into.covers = covers
	into.flags = flags
	into.worn_icon = worn_icon
	into.layer = layer

/datum/entry_engine/type_trait/item_worn
	kind = ENTRY_ITEM_WORN
	trait_type = /datum/type_trait/item_worn
	publish_key = ITEM_WORN_KEY
	base_type = /obj/item
	var_names = list("slot_flags" = "slots", "flags_inv" = "hides", "body_parts_covered" = "covers", "item_flags" = "flags", "default_worn_icon" = "worn_icon", "worn_layer" = "layer")

/// The holder's item_worn values (its own once one was set at run time). Read only.
READS_AS(/proc/worn_of, ITEM_WORN_KEY)
/proc/worn_of(obj/item/holder) as /datum/type_trait/item_worn
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_ITEM_WORN)

/// What a type declares (no instance): the old initial().
/proc/worn_of_type(type) as /datum/type_trait/item_worn
	READS_FROM() // declared per type: constant
	return type_trait_of_type(type, ENTRY_ITEM_WORN)

/obj/item/proc/set_slot_flags(value)
	return set_trait(src, ENTRY_ITEM_WORN, "slots", value)

/obj/item/proc/set_flags_inv(value)
	return set_trait(src, ENTRY_ITEM_WORN, "hides", value)

/obj/item/proc/set_body_parts_covered(value)
	return set_trait(src, ENTRY_ITEM_WORN, "covers", value)

/obj/item/proc/set_item_flags(value)
	return set_trait(src, ENTRY_ITEM_WORN, "flags", value)

/obj/item/proc/set_default_worn_icon(value)
	return set_trait(src, ENTRY_ITEM_WORN, "worn_icon", value)

/obj/item/proc/set_worn_layer(value)
	return set_trait(src, ENTRY_ITEM_WORN, "layer", value)
