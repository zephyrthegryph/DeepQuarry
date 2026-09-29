// Cataloguer — structured TGUI.
//
// Two views: a category-grouped catalogue index, and a per-item detail
// view. The DM side picks based on whether `displayed_data` is set on
// the cataloguer.

/obj/item/cataloguer/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/cataloguer, "Cataloguer", UI_TITLE("Cataloguer"))

/obj/item/cataloguer/tgui_data(mob/user)
	var/list/data = list()
	data["points_stored"] = points_stored
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

UI_ACT(/obj/item/cataloguer, "pulse_scan", ui_act_pulse_scan)
UI_ACT_PROC(/obj/item/cataloguer, ui_act_pulse_scan)
	pulse_scan(ui.user)
	return TRUE

UI_ACT(/obj/item/cataloguer, "show_data", ui_act_show_data, UI_ARG_REF("ref", null, /datum/category_item/catalogue))
UI_ACT_PROC(/obj/item/cataloguer, ui_act_show_data)
	var/datum/category_item/catalogue/new_data = params["ref"]
	if(istype(new_data))
		displayed_data = new_data
		SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/cataloguer, "back_to_list", ui_act_back_to_list)
UI_ACT_PROC(/obj/item/cataloguer, ui_act_back_to_list)
	displayed_data = null
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/cataloguer, "refresh", ui_act_refresh)
UI_ACT_PROC(/obj/item/cataloguer, ui_act_refresh)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/cataloguer, "debug_unlock", ui_act_debug_unlock, UI_ARG_REF("ref", null, /datum/category_item/catalogue))
UI_ACT_PROC(/obj/item/cataloguer, ui_act_debug_unlock)
	if(!debug)
		return TRUE
	var/datum/category_item/catalogue/item = params["ref"]
	if(item)
		item.discover(ui.user, list("Debugger"))
	SStgui.update_uis(src)
	return TRUE
