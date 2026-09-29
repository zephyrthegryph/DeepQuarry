// Integrated electronics list pin editor — structured TGUI.

/datum/integrated_io/list/interact(mob/user)
	tgui_interact(user)

/datum/integrated_io/list/tgui_state(mob/user)
	return GLOB.tgui_always_state

DECLARE_UI(/datum/integrated_io/list, "ListPin")

/datum/integrated_io/list/ui_title(mob/user)
	return "List Pin: [name]"

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

/datum/integrated_io/list/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!holder().check_interactivity(ui.user))
		return FALSE
	return TRUE

UI_ACT(/datum/integrated_io/list, "add", ui_act_add)
UI_ACT_PROC(/datum/integrated_io/list, ui_act_add)
	add_to_list(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/integrated_io/list, "swap", ui_act_swap)
UI_ACT_PROC(/datum/integrated_io/list, ui_act_swap)
	swap_inside_list(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/integrated_io/list, "clear", ui_act_clear)
UI_ACT_PROC(/datum/integrated_io/list, ui_act_clear)
	clear_list(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/integrated_io/list, "edit", ui_act_edit, UI_ARG_NUM("pos"))
UI_ACT_PROC(/datum/integrated_io/list, ui_act_edit)
	var/position = params["pos"]
	if(position)
		edit_in_list_by_position(ui.user, position)
	else
		edit_in_list(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/integrated_io/list, "remove", ui_act_remove, UI_ARG_NUM("pos"))
UI_ACT_PROC(/datum/integrated_io/list, ui_act_remove)
	var/position = params["pos"]
	if(position)
		remove_from_list_by_position(ui.user, position)
	else
		remove_from_list(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/datum/integrated_io/list, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/integrated_io/list, ui_act_refresh)
	SStgui.update_uis(src)
	return TRUE
