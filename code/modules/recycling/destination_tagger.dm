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

/obj/item/destTagger/tgui_static_data(mob/user)
	. = ..()
	.["level_names"] = using_map.zlevels

/obj/item/destTagger/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["currTag"] = currTag
	var/list/merged_1 = ui_data_obj_item_destTagger(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/destTagger's window data.
/obj/item/destTagger/proc/ui_data_obj_item_destTagger(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["taggerLocs"] = GLOB.tagger_locations

	return data

CAPABILITIES(/obj/item/destTagger)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	interface("DestinationTagger", state = nameof(GLOB.tgui_inventory_state))
	op("set_tag", ui_act("set_tag", arg("tag", schema_text(4096))), then(PROC_REF(ui_act_set_tag)))
	op("new_tag", ui_act("new_tag", arg("tag", schema_text(4096))), then(PROC_REF(ui_act_new_tag)))

/// Old attack_self.
/obj/item/destTagger/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/obj/item/destTagger/proc/ui_act_set_tag(datum/act/op/A, tag)
	add_fingerprint(A.actor)
	var/new_tag = tag
	if(!(new_tag in GLOB.tagger_locations))
		return FALSE
	currTag = new_tag
	return TRUE

/obj/item/destTagger/proc/ui_act_new_tag(datum/act/op/A, tag)
	add_fingerprint(A.actor)
	var/dest_tag = sanitizeName(tag, allow_numbers = TRUE)
	if(!istext(dest_tag) || length(dest_tag) < 3)
		return FALSE
	if(dest_tag in GLOB.tagger_locations)
		return FALSE
	GLOB.tagger_locations[dest_tag] = null
	currTag = dest_tag
	return TRUE
