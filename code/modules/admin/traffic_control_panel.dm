// Telecommunication Traffic Control — structured TGUI.

/obj/machinery/computer/telecomms/traffic/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/traffic_control_open_ui,
	)
	..()

/// Old attack_hand: never called ..().
/datum/interaction/machine_hand/ungated/traffic_control_open_ui
	id = "traffic_control_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/telecomms/traffic/proc/interaction_open_ui_impl

/obj/machinery/computer/telecomms/traffic/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	if(!operable())
		return TRUE
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/obj/machinery/computer/telecomms/traffic/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["temp"] = temp
	data["network"] = network
	data["screen"] = screen
	var/list/merged_1 = ui_data_obj_machinery_computer_telecomms_traffic(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/computer/telecomms/traffic's window data.
/obj/machinery/computer/telecomms/traffic/proc/ui_data_obj_machinery_computer_telecomms_traffic(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(screen == 0)
		var/list/server_rows = list()
		for(var/obj/machinery/telecomms/T in servers)
			server_rows += list(list(
				"id" = T.id,
				"name" = T.name,
				"ref" = "[T.id]",
			))
		data["servers"] = server_rows
	else if(screen == 1 && SelectedServer())
		data["selected_id"] = SelectedServer().id
		data["autoruncode"] = !!SelectedServer().autoruncode
	return data

/obj/machinery/computer/telecomms/traffic/proc/ui_act_clear_temp(datum/act/op/A)
	set_temp("")
	return OP_OK

/obj/machinery/computer/telecomms/traffic/proc/ui_act_set_network(datum/act/op/A)
	var/mob/user = A.actor
	traffic_set_network(user)
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_scan(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "scan")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_flush_buffer(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "release")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_view_server(datum/act/op/A, id_arg)
	var/mob/user = A.actor
	var/id = "[id_arg]"
	traffic_view_server(user, id)
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_main_menu(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "mainmenu")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_refresh(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "refresh")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_edit_code(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "editcode")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_toggle_run(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "togglerun")
	SStgui.update_uis(src)
	return TRUE
