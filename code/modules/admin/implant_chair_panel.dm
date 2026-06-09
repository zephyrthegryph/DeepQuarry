// Implant chair — structured TGUI.

/obj/machinery/implantchair/attack_hand(mob/user)
	user.set_machine(src)
	tgui_interact(user)

/obj/machinery/implantchair/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/implantchair/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ImplantChair", "Implanter Status")
		ui.open()

/obj/machinery/implantchair/tgui_data(mob/user)
	var/list/data = list()
	data["has_occupant"] = !!occupant
	if(occupant)
		data["occupant_name"] = "[occupant]"
		var/health_text = "[round(occupant.health, 0.1)]"
		data["health_text"] = health_text
		data["dead"] = occupant.health <= -100
		data["damaged"] = occupant.health < 0
	data["implants_left"] = implant_list ? implant_list.len : 0
	data["ready"] = !!ready
	return data

/obj/machinery/implantchair/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("implant")
			Topic("implant=1", list("implant" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("replenish")
			Topic("replenish=1", list("replenish" = "1"))
			SStgui.update_uis(src)
			return TRUE
