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

/obj/item/destTagger/tgui_state(mob/user)
	return GLOB.tgui_inventory_state

DECLARE_UI(/obj/item/destTagger, "DestinationTagger")

/obj/item/destTagger/tgui_static_data(mob/user)
	. = ..()
	.["level_names"] = using_map.zlevels

/obj/item/destTagger/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["taggerLocs"] = GLOB.tagger_locations
	data["currTag"] = currTag

	return data

DECLARE_INTERACTIONS(/obj/item/destTagger, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/destTagger/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/obj/item/destTagger/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/item/destTagger, "set_tag", ui_act_set_tag, UI_ARG_VALUE("tag"))
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
