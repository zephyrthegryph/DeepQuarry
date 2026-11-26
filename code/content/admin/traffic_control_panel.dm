// Telecommunication Traffic Control — structured TGUI.

/obj/machinery/computer/telecomms/traffic/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
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
	var/list/server_rows = list()
	if(screen == 0)
		for(var/obj/machinery/telecomms/T in servers)
			server_rows += list(list(
				"id" = T.id,
				"name" = T.name,
			))
	data["servers"] = server_rows
	data["selected_id"] = null
	data["autoruncode"] = FALSE
	if(screen == 1 && SelectedServer())
		data["selected_id"] = SelectedServer().id
		data["autoruncode"] = !!SelectedServer().autoruncode
	return data

/obj/machinery/computer/telecomms/traffic/proc/ui_act_clear_temp(datum/act/op/A)
	set_temp(null)
	return OP_OK

/obj/machinery/computer/telecomms/traffic/proc/ui_act_set_network(datum/act/op/A)
	var/mob/user = A.actor
	traffic_access(user)
	network_entered(A)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_scan(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "scan")
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_flush_buffer(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "release")
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_view_server(datum/act/op/A, id_arg)
	var/mob/user = A.actor
	var/id = "[id_arg]"
	traffic_view_server(user, id)
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_main_menu(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "mainmenu")
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_refresh(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "refresh")
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_edit_code(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "editcode")
	return TRUE

/obj/machinery/computer/telecomms/traffic/proc/ui_act_toggle_run(datum/act/op/A)
	var/mob/user = A.actor
	traffic_operation(user, "togglerun")
	return TRUE
