// Telecommunication Traffic Control — structured TGUI.

/obj/machinery/computer/telecomms/traffic/attack_hand(mob/user as mob)
	if(stat & (BROKEN|NOPOWER))
		return
	user.set_machine(src)
	tgui_interact(user)

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
	else if(screen == 1 && SelectedServer)
		data["selected_id"] = SelectedServer.id
		data["autoruncode"] = !!SelectedServer.autoruncode
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
			Topic("network=1", list("network" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("scan")
			Topic("operation=scan", list("operation" = "scan"))
			SStgui.update_uis(src)
			return TRUE
		if("flush_buffer")
			Topic("operation=release", list("operation" = "release"))
			SStgui.update_uis(src)
			return TRUE
		if("view_server")
			var/id = "[params["id"]]"
			Topic("viewserver=[id]", list("viewserver" = id))
			SStgui.update_uis(src)
			return TRUE
		if("main_menu")
			Topic("operation=mainmenu", list("operation" = "mainmenu"))
			SStgui.update_uis(src)
			return TRUE
		if("refresh")
			Topic("operation=refresh", list("operation" = "refresh"))
			SStgui.update_uis(src)
			return TRUE
		if("edit_code")
			Topic("operation=editcode", list("operation" = "editcode"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_run")
			Topic("operation=togglerun", list("operation" = "togglerun"))
			SStgui.update_uis(src)
			return TRUE
