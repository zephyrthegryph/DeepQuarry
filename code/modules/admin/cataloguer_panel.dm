// Cataloguer — structured TGUI.
//
// Two views: a category-grouped catalogue index, and a per-item detail
// view. The DM side picks based on whether `displayed_data` is set on
// the cataloguer.

/obj/item/cataloguer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["points_stored"] = points_stored
	var/list/merged_1 = ui_data_obj_item_cataloguer(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/cataloguer's window data.
/obj/item/cataloguer/proc/ui_data_obj_item_cataloguer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["debug"] = !!debug
	if(displayed_data)
		var/cataloguers_text = null
		if(LAZYLEN(displayed_data.cataloguers))
			cataloguers_text = english_list(displayed_data.cataloguers)
		data["detail"] = list(
			"name" = displayed_data.name,
			"desc" = displayed_data.desc,
			"value" = displayed_data.value,
			"cataloguers" = cataloguers_text,
			"visible" = !!displayed_data.visible,
			"ref" = "\ref[displayed_data]",
		)
	else
		data["detail"] = null
		var/list/groups = list()
		for(var/datum/category_group/group as anything in GLOB.catalogue_data.categories)
			var/list/items = list()
			for(var/datum/category_item/catalogue/item as anything in group.items)
				if(item.visible || debug)
					items += list(list(
						"name" = item.name,
						"ref" = "\ref[item]",
						"visible" = !!item.visible,
					))
			if(items.len || debug)
				groups += list(list(
					"name" = group.name,
					"items" = items,
				))
		data["groups"] = groups
	return data

CAPABILITIES(/obj/item/cataloguer)
	op("pulse_scan", ui_act(), then(PROC_REF(ui_act_pulse_scan)))
	op("back_to_list", ui_act(), then(PROC_REF(ui_act_back_to_list)))
	op("refresh", ui_act(), then(PROC_REF(ui_act_refresh)))
	op("controls", in_hand(), label("Open cataloguer"), then(PROC_REF(cataloguer_controls_opened)))
	interface("Cataloguer", title = "Cataloguer", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("show_data", ui_act("show_data", arg("ref", schema_ref(/datum/category_item/catalogue))), then(PROC_REF(ui_act_show_data)))
	op("debug_unlock", ui_act("debug_unlock", arg("ref", schema_ref(/datum/category_item/catalogue))), then(PROC_REF(ui_act_debug_unlock)))

/obj/item/cataloguer/proc/ui_act_pulse_scan(datum/act/op/A)
	pulse_scan(A.actor)
	return OP_OK

/obj/item/cataloguer/proc/ui_act_show_data(datum/act/op/A, ref)
	var/datum/category_item/catalogue/new_data = ref
	if(istype(new_data))
		displayed_data = new_data
		SStgui.update_uis(src)
	return TRUE

/obj/item/cataloguer/proc/ui_act_back_to_list(datum/act/op/A)
	displayed_data = null
	SStgui.update_uis(src)
	return OP_OK

/obj/item/cataloguer/proc/ui_act_refresh(datum/act/op/A)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/cataloguer/proc/ui_act_debug_unlock(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!debug)
		return TRUE
	var/datum/category_item/catalogue/item = ref
	if(item)
		item.discover(user, list("Debugger"))
	SStgui.update_uis(src)
	return TRUE
