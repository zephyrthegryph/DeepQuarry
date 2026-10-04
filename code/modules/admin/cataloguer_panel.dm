// Cataloguer — structured TGUI.
//
// Two views: a category-grouped catalogue index, and a per-item detail
// view. The DM side picks based on whether `displayed_data` is set on
// the cataloguer.

DECLARE_UI_STATE(/obj/item/cataloguer, GLOB.tgui_default_state)

DECLARE_UI(/obj/item/cataloguer, "Cataloguer", UI_TITLE("Cataloguer"))

UI_DATA_REPLACE(/obj/item/cataloguer, "points_stored:num", "merge:ui_data_obj_item_cataloguer{debug:bool,detail:list,groups:list}")

/// The computed part of /obj/item/cataloguer's window data (declared on its UI_DATA row).
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

/obj/item/cataloguer/proc/ui_act_pulse_scan(datum/act/op/A)
	pulse_scan(A.actor)
	return OP_OK

UI_ACT(/obj/item/cataloguer, "show_data", ui_act_show_data, UI_ARG_REF("ref", null, /datum/category_item/catalogue))
UI_ACT_PROC(/obj/item/cataloguer, ui_act_show_data)
	var/datum/category_item/catalogue/new_data = params["ref"]
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

UI_ACT(/obj/item/cataloguer, "debug_unlock", ui_act_debug_unlock, UI_ARG_REF("ref", null, /datum/category_item/catalogue))
UI_ACT_PROC(/obj/item/cataloguer, ui_act_debug_unlock)
	if(!debug)
		return TRUE
	var/datum/category_item/catalogue/item = params["ref"]
	if(item)
		item.discover(ui.user, list("Debugger"))
	SStgui.update_uis(src)
	return TRUE
