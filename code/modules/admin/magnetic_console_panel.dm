// Magnetic Control Console — structured TGUI.
//
// Re-opens /obj/machinery/magnetic_controller with proper TGUI hooks
// instead of the legacy admin_log_show HTML body. Per-magnet rows are
// structured; all actions dispatch through tgui_act to the existing
// Topic-handler logic.

// The upstream /obj/machinery/magnetic_controller/attack_hand is
// modified (see code/game/machinery/magnet.dm) to call tgui_interact
// directly instead of the legacy HTML body.

DECLARE_UI(/obj/machinery/magnetic_controller, "MagneticConsole", UI_TITLE("Magnetic Control Console"))

DECLARE_UI_STATE(/obj/machinery/magnetic_controller, GLOB.tgui_default_state)

UI_DATA_REPLACE(/obj/machinery/magnetic_controller, "frequency:num", "code", "speed:num", "path", "merge:ui_data_obj_machinery_magnetic_controller{autolink:bool,moving:bool,magnets:list}")

/// The computed part of /obj/machinery/magnetic_controller's window data (declared on its UI_DATA row).
/obj/machinery/magnetic_controller/proc/ui_data_obj_machinery_magnetic_controller(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["autolink"] = !!autolink
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

/obj/machinery/magnetic_controller/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!operable())
		return FALSE
	if(!user)
		return FALSE
	user.set_machine(src)
	add_fingerprint(user)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "set_frequency", ui_act_set_frequency)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_set_frequency)
	magnet_operation(user, "setfreq")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "set_code", ui_act_set_code)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_set_code)
	// Legacy panel used the same "setfreq" handler for both.
	magnet_operation(user, "setfreq")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "probe", ui_act_probe)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_probe)
	magnet_operation(user, "probe")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "toggle_power", ui_act_toggle_power)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_toggle_power)
	magnet_radio_op(user, "togglepower")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "elec_minus", ui_act_elec_minus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_elec_minus)
	magnet_radio_op(user, "minuselec")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "elec_plus", ui_act_elec_plus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_elec_plus)
	magnet_radio_op(user, "pluselec")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "mag_minus", ui_act_mag_minus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_mag_minus)
	magnet_radio_op(user, "minusmag")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "mag_plus", ui_act_mag_plus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_mag_plus)
	magnet_radio_op(user, "plusmag")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "speed_minus", ui_act_speed_minus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_speed_minus)
	magnet_operation(user, "minusspeed")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "speed_plus", ui_act_speed_plus)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_speed_plus)
	magnet_operation(user, "plusspeed")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "set_path", ui_act_set_path)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_set_path)
	magnet_operation(user, "setpath")
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/magnetic_controller, "toggle_moving", ui_act_toggle_moving)
UI_ACT_PROC(/obj/machinery/magnetic_controller, ui_act_toggle_moving)
	magnet_operation(user, "togglemoving")
	SStgui.update_uis(src)
	return TRUE
