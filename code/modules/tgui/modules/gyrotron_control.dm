/datum/tgui_module/gyrotron_control
	name = "Gyrotron Control"
	tgui_id = "GyrotronControl"

	var/gyro_tag = ""
	var/scan_range = 25

/// The devices this console controls, for the UI's refs.
/datum/tgui_module/gyrotron_control/proc/gyrotrons()
	return REGISTRY_MEMBERS(REGISTRY_GYROTRONS)

UI_ACT(/datum/tgui_module/gyrotron_control, "set_tag", ui_act_set_tag)
UI_ACT_PROC(/datum/tgui_module/gyrotron_control, ui_act_set_tag)
	var/_answer_a1 = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/text, message = "Enter a new ident tag.", title = "Gyrotron Control", default = gyro_tag)
	if(isnull(_answer_a1))
		return
	var/new_ident = sanitize_text(_answer_a1)
	if(new_ident)
		gyro_tag = new_ident
	return TRUE

UI_ACT(/datum/tgui_module/gyrotron_control, "toggle_active", ui_act_toggle_active, UI_ARG_REF("gyro", "proc:gyrotrons", /obj/machinery/power/emitter/gyrotron))
UI_ACT_PROC(/datum/tgui_module/gyrotron_control, ui_act_toggle_active)
	var/obj/machinery/power/emitter/gyrotron/G = params["gyro"]
	if(!G)
		return TRUE
	G.activate(ui.user)
	return TRUE

UI_ACT(/datum/tgui_module/gyrotron_control, "set_str", ui_act_set_str, UI_ARG_REF("gyro", "proc:gyrotrons", /obj/machinery/power/emitter/gyrotron), UI_ARG_NUM("str"))
UI_ACT_PROC(/datum/tgui_module/gyrotron_control, ui_act_set_str)
	var/obj/machinery/power/emitter/gyrotron/G = params["gyro"]
	var/new_strength = params["str"]
	if(new_strength && G)
		G.set_beam_power(new_strength)
	return TRUE

UI_ACT(/datum/tgui_module/gyrotron_control, "set_rate", ui_act_set_rate, UI_ARG_REF("gyro", "proc:gyrotrons", /obj/machinery/power/emitter/gyrotron), UI_ARG_NUM("rate"))
UI_ACT_PROC(/datum/tgui_module/gyrotron_control, ui_act_set_rate)
	var/obj/machinery/power/emitter/gyrotron/G = params["gyro"]
	var/new_delay = params["rate"]
	if(new_delay && G)
		G.rate = new_delay
	return TRUE

/datum/tgui_module/gyrotron_control/tgui_data(mob/user)
	var/list/data = list()
	var/list/gyros = list()

	for(var/obj/machinery/power/emitter/gyrotron/G in REGISTRY_MEMBERS(REGISTRY_GYROTRONS))
		if(G.id_tag == gyro_tag)// && (get_dist(get_turf(G), get_turf(src)) <= scan_range))
			gyros.Add(list(list(
				"name" = G.name,
				"active" = G.active,
				"strength" = G.mega_energy,
				"fire_delay" = G.rate,
				"deployed" = (G.state == 2),
				"x" = G.x,
				"y" = G.y,
				"z" = G.z,
				"ref" = "\ref[G]"
			)))

	data["gyros"] = gyros
	return data

/datum/tgui_module/gyrotron_control/ntos
	ntos = TRUE
