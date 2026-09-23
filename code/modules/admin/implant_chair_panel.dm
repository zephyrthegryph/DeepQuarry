// Implant chair — structured TGUI.

/obj/machinery/implantchair/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/implantchair_open_ui,
	)
	..()

/// Old attack_hand (never called ..()): set_machine() then open the interface.
/datum/interaction/machine_hand/ungated/implantchair_open_ui
	id = "implantchair_open_ui"
	name = "Use"
	effect = /obj/machinery/implantchair/proc/interaction_open_ui_impl

/obj/machinery/implantchair/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

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
		var/health_text = "[round(occupant.vitality() * 100, 0.1)]%"
		data["health_text"] = health_text
		data["dead"] = occupant.stat == DEAD
		data["damaged"] = occupant.is_critical()
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
