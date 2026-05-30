// Cataloguer — structured TGUI.
//
// Two views: a category-grouped catalogue index, and a per-item detail
// view. The DM side picks based on whether `displayed_data` is set on
// the cataloguer.

/obj/item/cataloguer/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/cataloguer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Cataloguer", "Cataloguer")
		ui.open()

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

/obj/item/cataloguer/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("pulse_scan")
			pulse_scan(ui.user)
			return TRUE
		if("show_data")
			displayed_data = locate(params["ref"])
			SStgui.update_uis(src)
			return TRUE
		if("back_to_list")
			displayed_data = null
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			SStgui.update_uis(src)
			return TRUE
		if("debug_unlock")
			if(!debug)
				return TRUE
			var/datum/category_item/catalogue/item = locate(params["ref"])
			if(item)
				item.discover(ui.user, list("Debugger"))
			SStgui.update_uis(src)
			return TRUE
