/datum/tgui_module/gyrotron_control
	name = "Gyrotron Control"

	var/gyro_tag = ""
	var/scan_range = 25

CAPABILITIES(/datum/tgui_module/gyrotron_control)
	interface("GyrotronControl")
	op("set_tag", ui_act("set_tag"), asks(/datum/prompt/text, fields = list("title" = "Gyrotron Control", "question" = "Enter a new ident tag.", "default" = nameof(gyro_tag), "timeout" = 0), step = "tag"), then(PROC_REF(ui_act_set_tag)))
	op("toggle_active", ui_act("toggle_active", arg("gyro", schema_text(32))), then(PROC_REF(ui_act_toggle_active)))
	op("set_str", ui_act("set_str", arg("gyro", schema_text(32)), arg("str", num())), then(PROC_REF(ui_act_set_str)))
	op("set_rate", ui_act("set_rate", arg("gyro", schema_text(32)), arg("rate", num())), then(PROC_REF(ui_act_set_rate)))

/datum/tgui_module/gyrotron_control/proc/ui_act_set_tag(datum/act/op/A)
	var/new_ident = sanitize_text(A.step_value("tag"))
	if(new_ident)
		set_gyro_tag(new_ident)
	SStgui.update_uis(src)

/// The gyrotrons the window lists: those on this console's tag.
/datum/tgui_module/gyrotron_control/proc/listed_gyros()
	var/list/listed = list()
	for(var/obj/machinery/power/emitter/gyrotron/G in registry_all(REGISTRY_GYROTRONS, gyro_tag))
		if(G.id_tag == gyro_tag)
			listed += G
	return listed

/datum/tgui_module/gyrotron_control/proc/ui_act_toggle_active(datum/act/op/A, gyro)
	var/mob/user = A.actor
	var/obj/machinery/power/emitter/gyrotron/G = ui_member(gyro, listed_gyros(), /obj/machinery/power/emitter/gyrotron)
	if(!G)
		return TRUE
	G.activate(user)
	return TRUE

/datum/tgui_module/gyrotron_control/proc/ui_act_set_str(datum/act/op/A, gyro, str)
	var/obj/machinery/power/emitter/gyrotron/G = ui_member(gyro, listed_gyros(), /obj/machinery/power/emitter/gyrotron)
	var/new_strength = str
	if(new_strength && G)
		G.set_beam_power(new_strength)
	return TRUE

/datum/tgui_module/gyrotron_control/proc/ui_act_set_rate(datum/act/op/A, gyro, rate)
	var/obj/machinery/power/emitter/gyrotron/G = ui_member(gyro, listed_gyros(), /obj/machinery/power/emitter/gyrotron)
	var/new_delay = rate
	if(new_delay && G)
		G.rate = new_delay
	return TRUE

/datum/tgui_module/gyrotron_control/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/gyros = list()

	for(var/obj/machinery/power/emitter/gyrotron/G in registry_all(REGISTRY_GYROTRONS, gyro_tag))
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
				"ref" = ref_token(G)
			)))

	data["gyros"] = gyros
	return data

/datum/tgui_module/gyrotron_control/ntos
	ntos = TRUE
