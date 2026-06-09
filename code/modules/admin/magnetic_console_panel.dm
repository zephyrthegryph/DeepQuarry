// Magnetic Control Console — structured TGUI.
//
// Re-opens /obj/machinery/magnetic_controller with proper TGUI hooks
// instead of the legacy admin_log_show HTML body. Per-magnet rows are
// structured; all actions dispatch through tgui_act to the existing
// Topic-handler logic.

// The upstream /obj/machinery/magnetic_controller/attack_hand is
// modified (see code/game/machinery/magnet.dm) to call tgui_interact
// directly instead of the legacy HTML body.

/obj/machinery/magnetic_controller/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MagneticConsole", "Magnetic Control Console")
		ui.open()

/obj/machinery/magnetic_controller/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/magnetic_controller/tgui_data(mob/user)
	var/list/data = list()
	data["autolink"] = !!autolink
	data["frequency"] = frequency
	data["code"] = code
	data["speed"] = speed
	data["path"] = path
	data["moving"] = !!moving

	var/list/magnet_rows = list()
	var/i = 0
	for(var/obj/machinery/magnetic_module/M in magnets)
		i++
		magnet_rows += list(list(
			"index" = i,
			"ref" = "\ref[M]",
			"on" = !!M.on,
			"electricity_level" = M.electricity_level,
			"magnetic_field" = M.magnetic_field,
		))
	data["magnets"] = magnet_rows
	return data

/obj/machinery/magnetic_controller/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(stat & (BROKEN|NOPOWER))
		return
	var/mob/user = ui?.user
	if(!user)
		return
	user.set_machine(src)
	add_fingerprint(user)

	switch(action)
		if("set_frequency")
			Topic("operation=setfreq", list("operation" = "setfreq"))
			SStgui.update_uis(src)
			return TRUE
		if("set_code")
			// Legacy panel used the same "setfreq" handler for both.
			Topic("operation=setfreq", list("operation" = "setfreq"))
			SStgui.update_uis(src)
			return TRUE
		if("probe")
			Topic("operation=probe", list("operation" = "probe"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_power")
			Topic("radio-op=togglepower", list("radio-op" = "togglepower"))
			SStgui.update_uis(src)
			return TRUE
		if("elec_minus")
			Topic("radio-op=minuselec", list("radio-op" = "minuselec"))
			SStgui.update_uis(src)
			return TRUE
		if("elec_plus")
			Topic("radio-op=pluselec", list("radio-op" = "pluselec"))
			SStgui.update_uis(src)
			return TRUE
		if("mag_minus")
			Topic("radio-op=minusmag", list("radio-op" = "minusmag"))
			SStgui.update_uis(src)
			return TRUE
		if("mag_plus")
			Topic("radio-op=plusmag", list("radio-op" = "plusmag"))
			SStgui.update_uis(src)
			return TRUE
		if("speed_minus")
			Topic("operation=minusspeed", list("operation" = "minusspeed"))
			SStgui.update_uis(src)
			return TRUE
		if("speed_plus")
			Topic("operation=plusspeed", list("operation" = "plusspeed"))
			SStgui.update_uis(src)
			return TRUE
		if("set_path")
			Topic("operation=setpath", list("operation" = "setpath"))
			SStgui.update_uis(src)
			return TRUE
		if("toggle_moving")
			Topic("operation=togglemoving", list("operation" = "togglemoving"))
			SStgui.update_uis(src)
			return TRUE
