// Integrated electronics list pin editor — structured TGUI.

/datum/integrated_io/list/interact(mob/user)
	tgui_interact(user)

CAPABILITIES(/datum/integrated_io/list)
	interface("ListPin", state = nameof(GLOB.tgui_always_state))
	op("add", ui_act("add"), then(PROC_REF(ui_act_add)))
	op("swap", ui_act("swap"), then(PROC_REF(ui_act_swap)))
	op("clear", ui_act("clear"), then(PROC_REF(ui_act_clear)))
	op("edit", ui_act("edit", arg("pos", num())), then(PROC_REF(ui_act_edit)))
	op("remove", ui_act("remove", arg("pos", num())), then(PROC_REF(ui_act_remove)))
	op("refresh", ui_act("refresh"), then(PROC_REF(ui_act_refresh)))

/datum/integrated_io/list/ui_title(mob/user)
	return "List Pin: [name]"

/// /datum/integrated_io/list's window data.
/datum/integrated_io/list/ui_data(datum/act/eval/A)
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

/datum/integrated_io/list/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!holder().check_interactivity(user))
		return FALSE
	return TRUE

/datum/integrated_io/list/proc/ui_act_add(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	add_to_list(user)
	SStgui.update_uis(src)
	return TRUE

/datum/integrated_io/list/proc/ui_act_swap(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	swap_inside_list(user)
	SStgui.update_uis(src)
	return TRUE

/datum/integrated_io/list/proc/ui_act_clear(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	clear_list(user)
	SStgui.update_uis(src)
	return TRUE

/datum/integrated_io/list/proc/ui_act_edit(datum/act/op/A, pos)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/position = pos
	if(position)
		edit_in_list_by_position(user, position)
	else
		edit_in_list(user)
	SStgui.update_uis(src)
	return TRUE

/datum/integrated_io/list/proc/ui_act_remove(datum/act/op/A, pos)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/position = pos
	if(position)
		remove_from_list_by_position(user, position)
	else
		remove_from_list(user)
	SStgui.update_uis(src)
	return TRUE

/datum/integrated_io/list/proc/ui_act_refresh(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	SStgui.update_uis(src)
	return TRUE
