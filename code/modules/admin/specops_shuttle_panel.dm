// Special Operations Shuttle console — structured TGUI.

/obj/machinery/computer/specops_shuttle/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/specops_shuttle_open_ui,
	)
	..()

/datum/interaction/machine_hand/specops_shuttle_open_ui
	id = "specops_shuttle_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_ACTOR, /obj/machinery/computer/specops_shuttle/proc/lets_in, "access denied"))
	effect = /obj/machinery/computer/specops_shuttle/proc/interaction_open_ui

/obj/machinery/computer/specops_shuttle/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/obj/machinery/computer/specops_shuttle/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

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
