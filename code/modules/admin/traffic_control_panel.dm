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

DECLARE_UI_STATE(/obj/machinery/computer/telecomms/traffic, GLOB.tgui_default_state)

DECLARE_UI(/obj/machinery/computer/telecomms/traffic, "TrafficControl", UI_TITLE("Telecommunications Traffic Control"))

UI_DATA_REPLACE(/obj/machinery/computer/telecomms/traffic, "temp:text", "network", "screen:num", "merge:ui_data_obj_machinery_computer_telecomms_traffic{servers:list,selected_id:num,autoruncode:bool}")

/// The computed part of /obj/machinery/computer/telecomms/traffic's window data (declared on its UI_DATA row).
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
	temp = ""
	SStgui.update_uis(src)
	return OP_OK

UI_ACT(/obj/machinery/computer/telecomms/traffic, "set_network", ui_act_set_network)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_set_network)
	traffic_set_network(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_scan)
	traffic_operation(ui.user, "scan")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "flush_buffer", ui_act_flush_buffer)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_flush_buffer)
	traffic_operation(ui.user, "release")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "view_server", ui_act_view_server, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_view_server)
	var/id = "[params["id"]]"
	traffic_view_server(ui.user, id)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "main_menu", ui_act_main_menu)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_main_menu)
	traffic_operation(ui.user, "mainmenu")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "refresh", ui_act_refresh)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_refresh)
	traffic_operation(ui.user, "refresh")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "edit_code", ui_act_edit_code)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_edit_code)
	traffic_operation(ui.user, "editcode")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/telecomms/traffic, "toggle_run", ui_act_toggle_run)
UI_ACT_PROC(/obj/machinery/computer/telecomms/traffic, ui_act_toggle_run)
	traffic_operation(ui.user, "togglerun")
	SStgui.update_uis(src)
	return TRUE
