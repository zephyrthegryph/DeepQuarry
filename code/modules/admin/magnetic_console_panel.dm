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
	data["moving"] = !!path_moving

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
	if(!operable())
		return
	var/mob/user = ui?.user
	if(!user)
		return
	user.set_machine(src)
	add_fingerprint(user)

	switch(action)
		if("set_frequency")
			magnet_operation(user, "setfreq")
			SStgui.update_uis(src)
			return TRUE
		if("set_code")
			// Legacy panel used the same "setfreq" handler for both.
			magnet_operation(user, "setfreq")
			SStgui.update_uis(src)
			return TRUE
		if("probe")
			magnet_operation(user, "probe")
			SStgui.update_uis(src)
			return TRUE
		if("toggle_power")
			magnet_radio_op(user, "togglepower")
			SStgui.update_uis(src)
			return TRUE
		if("elec_minus")
			magnet_radio_op(user, "minuselec")
			SStgui.update_uis(src)
			return TRUE
		if("elec_plus")
			magnet_radio_op(user, "pluselec")
			SStgui.update_uis(src)
			return TRUE
		if("mag_minus")
			magnet_radio_op(user, "minusmag")
			SStgui.update_uis(src)
			return TRUE
		if("mag_plus")
			magnet_radio_op(user, "plusmag")
			SStgui.update_uis(src)
			return TRUE
		if("speed_minus")
			magnet_operation(user, "minusspeed")
			SStgui.update_uis(src)
			return TRUE
		if("speed_plus")
			magnet_operation(user, "plusspeed")
			SStgui.update_uis(src)
			return TRUE
		if("set_path")
			magnet_operation(user, "setpath")
			SStgui.update_uis(src)
			return TRUE
		if("toggle_moving")
			magnet_operation(user, "togglemoving")
			SStgui.update_uis(src)
			return TRUE
