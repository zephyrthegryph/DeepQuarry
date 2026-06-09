// Special Operations Shuttle console — structured TGUI.

/obj/machinery/computer/specops_shuttle/attack_hand(mob/user as mob)
	if(!allowed(user))
		to_chat(user, span_warning("Access Denied."))
		return
	if(..())
		return
	user.set_machine(src)
	tgui_interact(user)

/obj/machinery/computer/specops_shuttle/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/computer/specops_shuttle/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SpecopsShuttle", "Special Operations Shuttle")
		ui.open()

/obj/machinery/computer/specops_shuttle/tgui_data(mob/user)
	var/list/data = list()
	if(temp)
		data["status_message"] = temp
		return data
	if(GLOB.specops_shuttle_moving_to_station || GLOB.specops_shuttle_moving_to_centcom)
		data["state"] = "moving"
		data["timeleft"] = GLOB.specops_shuttle_timeleft
		data["destination"] = station_name()
	else if(GLOB.specops_shuttle_at_station)
		data["state"] = "at_station"
	else
		data["state"] = "at_dock"
		data["destination"] = station_name()
	return data

/obj/machinery/computer/specops_shuttle/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("send_to_dock")
			Topic("sendtodock=1", list("sendtodock" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("send_to_station")
			Topic("sendtostation=1", list("sendtostation" = "1"))
			SStgui.update_uis(src)
			return TRUE
