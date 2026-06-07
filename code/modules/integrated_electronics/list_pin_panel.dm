// Integrated electronics list pin editor — structured TGUI.

/datum/integrated_io/list/interact(mob/user)
	tgui_interact(user)

/datum/integrated_io/list/tgui_state(mob/user)
	return GLOB.tgui_always_state

/datum/integrated_io/list/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ListPin", "List Pin: [name]")
		ui.open()

/datum/integrated_io/list/tgui_data(mob/user)
	var/list/data_out = list()
	data_out["name"] = "[src]"
	var/list/my_list = data
	data_out["length"] = my_list.len
	var/list/entries = list()
	var/i = 0
	for(var/line in my_list)
		i++
		entries += list(list("pos" = i, "display" = display_data(line)))
	data_out["entries"] = entries
	return data_out

/datum/integrated_io/list/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!holder.check_interactivity(ui.user))
		return
	switch(action)
		if("add")
			add_to_list(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("swap")
			swap_inside_list(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("clear")
			clear_list(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("edit")
			var/position = text2num(params["pos"])
			if(position)
				edit_in_list_by_position(ui.user, position)
			else
				edit_in_list(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("remove")
			var/position = text2num(params["pos"])
			if(position)
				remove_from_list_by_position(ui.user, position)
			else
				remove_from_list(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			SStgui.update_uis(src)
			return TRUE
