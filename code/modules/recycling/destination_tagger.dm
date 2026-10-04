/obj/item/destTagger
	name = "destination tagger"
	desc = "Used to set the destination of properly wrapped packages."
	icon = 'icons/obj/device.dmi'
	icon_state = "dest_tagger"
	var/currTag = 0

	w_class = ITEMSIZE_SMALL
	item_state = "electronic"
	slot_flags = SLOT_BELT
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

DECLARE_UI_STATE(/obj/item/destTagger, GLOB.tgui_inventory_state)

DECLARE_UI(/obj/item/destTagger, "DestinationTagger")

/obj/item/destTagger/tgui_static_data(mob/user)
	. = ..()
	.["level_names"] = using_map.zlevels

UI_DATA(/obj/item/destTagger, "currTag:num", "merge:ui_data_obj_item_destTagger{taggerLocs:unknown}")

/// The computed part of /obj/item/destTagger's window data (declared on its UI_DATA row).
/obj/item/destTagger/proc/ui_data_obj_item_destTagger(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["taggerLocs"] = GLOB.tagger_locations

	return data

CAPABILITIES(/obj/item/destTagger)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/destTagger/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/destTagger/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/item/destTagger, "set_tag", ui_act_set_tag, UI_ARG_TEXT("tag"))
UI_ACT_PROC(/obj/item/destTagger, ui_act_set_tag)
	var/new_tag = params["tag"]
	if(!(new_tag in GLOB.tagger_locations))
		return FALSE
	currTag = new_tag
	return TRUE

UI_ACT(/obj/item/destTagger, "new_tag", ui_act_new_tag, UI_ARG_TEXT("tag"))
UI_ACT_PROC(/obj/item/destTagger, ui_act_new_tag)
	var/dest_tag = sanitizeName(params["tag"], allow_numbers = TRUE)
	if(!istext(dest_tag) || length(dest_tag) < 3)
		return FALSE
	if(dest_tag in GLOB.tagger_locations)
		return FALSE
	GLOB.tagger_locations[dest_tag] = null
	currTag = dest_tag
	return TRUE
