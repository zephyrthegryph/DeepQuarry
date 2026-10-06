// Magnetic Control Console — structured TGUI.
//
// Re-opens /obj/machinery/magnetic_controller with proper TGUI hooks
// instead of the legacy admin_log_show HTML body. Per-magnet rows are
// structured; all actions dispatch through tgui_act to the existing
// Topic-handler logic.

// The upstream /obj/machinery/magnetic_controller/attack_hand is
// modified (see code/game/machinery/magnet.dm) to call tgui_interact
// directly instead of the legacy HTML body.

CAPABILITIES(/obj/machinery/magnetic_controller)
	started_work(step = PROC_REF(work_step), wakes_on = list(nameof(stat)))
	interface("MagneticConsole", title = "Magnetic Control Console", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("set_frequency", ui_act("set_frequency"), then(PROC_REF(ui_act_set_frequency)))
	op("set_code", ui_act("set_code"), then(PROC_REF(ui_act_set_code)))
	op("probe", ui_act("probe"), then(PROC_REF(ui_act_probe)))
	op("toggle_power", ui_act("toggle_power"), then(PROC_REF(ui_act_toggle_power)))
	op("elec_minus", ui_act("elec_minus"), then(PROC_REF(ui_act_elec_minus)))
	op("elec_plus", ui_act("elec_plus"), then(PROC_REF(ui_act_elec_plus)))
	op("mag_minus", ui_act("mag_minus"), then(PROC_REF(ui_act_mag_minus)))
	op("mag_plus", ui_act("mag_plus"), then(PROC_REF(ui_act_mag_plus)))
	op("speed_minus", ui_act("speed_minus"), then(PROC_REF(ui_act_speed_minus)))
	op("speed_plus", ui_act("speed_plus"), then(PROC_REF(ui_act_speed_plus)))
	op("set_path", ui_act("set_path"), then(PROC_REF(ui_act_set_path)))
	op("toggle_moving", ui_act("toggle_moving"), then(PROC_REF(ui_act_toggle_moving)))
	op("open", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open)))

/obj/machinery/magnetic_controller/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["frequency"] = frequency
	data["code"] = code
	data["speed"] = speed
	data["path"] = path
	var/list/merged_1 = ui_data_obj_machinery_magnetic_controller(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/magnetic_controller's window data.
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

/obj/machinery/magnetic_controller/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return FALSE
	if(!user)
		return FALSE
	user.set_machine(src)
	add_fingerprint(user)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_set_frequency(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "setfreq")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_set_code(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	// Legacy panel used the same "setfreq" handler for both.
	magnet_operation(user, "setfreq")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_probe(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "probe")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_toggle_power(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_radio_op(user, "togglepower")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_elec_minus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_radio_op(user, "minuselec")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_elec_plus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_radio_op(user, "pluselec")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_mag_minus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_radio_op(user, "minusmag")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_mag_plus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_radio_op(user, "plusmag")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_speed_minus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "minusspeed")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_speed_plus(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "plusspeed")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_set_path(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "setpath")
	SStgui.update_uis(src)
	return TRUE

/obj/machinery/magnetic_controller/proc/ui_act_toggle_moving(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	magnet_operation(user, "togglemoving")
	SStgui.update_uis(src)
	return TRUE
