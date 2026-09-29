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

/obj/machinery/computer/telecomms/traffic/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/computer/telecomms/traffic/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TrafficControl", "Telecommunications Traffic Control")
		ui.open()

/obj/machinery/computer/telecomms/traffic/tgui_data(mob/user)
	var/list/data = list()
	data["temp"] = temp
	data["network"] = network
	data["screen"] = screen
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

/obj/machinery/computer/telecomms/traffic/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("clear_temp")
			temp = ""
			SStgui.update_uis(src)
			return TRUE
		if("set_network")
			traffic_set_network(ui.user)
			SStgui.update_uis(src)
			return TRUE
		if("scan")
			traffic_operation(ui.user, "scan")
			SStgui.update_uis(src)
			return TRUE
		if("flush_buffer")
			traffic_operation(ui.user, "release")
			SStgui.update_uis(src)
			return TRUE
		if("view_server")
			var/id = "[params["id"]]"
			traffic_view_server(ui.user, id)
			SStgui.update_uis(src)
			return TRUE
		if("main_menu")
			traffic_operation(ui.user, "mainmenu")
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			traffic_operation(ui.user, "refresh")
			SStgui.update_uis(src)
			return TRUE
		if("edit_code")
			traffic_operation(ui.user, "editcode")
			SStgui.update_uis(src)
			return TRUE
		if("toggle_run")
			traffic_operation(ui.user, "togglerun")
			SStgui.update_uis(src)
			return TRUE
