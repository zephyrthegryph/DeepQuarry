/datum/tgui_module/gyrotron_control
	name = "Gyrotron Control"

	var/gyro_tag = ""
	var/scan_range = 25

CAPABILITIES(/datum/tgui_module/gyrotron_control)
	interface("GyrotronControl")
	op("set_tag", ui_act("set_tag"), then(PROC_REF(ui_act_set_tag)))
	op("toggle_active", ui_act("toggle_active", arg("gyro", schema_ref(/obj/machinery/power/emitter/gyrotron))), then(PROC_REF(ui_act_toggle_active)))
	op("set_str", ui_act("set_str", arg("gyro", schema_ref(/obj/machinery/power/emitter/gyrotron)), arg("str", num())), then(PROC_REF(ui_act_set_str)))
	op("set_rate", ui_act("set_rate", arg("gyro", schema_ref(/obj/machinery/power/emitter/gyrotron)), arg("rate", num())), then(PROC_REF(ui_act_set_rate)))

/datum/tgui_module/gyrotron_control/proc/ui_act_set_tag(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(tag_entered), valid = PROC_REF(request_usable), answerer = A.actor, title = "Gyrotron Control", question = "Enter a new ident tag.", default = gyro_tag, timeout = 0)

/datum/tgui_module/gyrotron_control/proc/tag_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_ident = sanitize_text(A.answer.value)
	if(new_ident)
		gyro_tag = new_ident
	SStgui.update_uis(src)

/datum/tgui_module/gyrotron_control/proc/ui_act_toggle_active(datum/act/op/A, gyro)
	var/mob/user = A.actor
	var/obj/machinery/power/emitter/gyrotron/G = gyro
	if(!G)
		return TRUE
	G.activate(user)
	return TRUE

/datum/tgui_module/gyrotron_control/proc/ui_act_set_str(datum/act/op/A, gyro, str)
	var/obj/machinery/power/emitter/gyrotron/G = gyro
	var/new_strength = str
	if(new_strength && G)
		G.set_beam_power(new_strength)
	return TRUE

/datum/tgui_module/gyrotron_control/proc/ui_act_set_rate(datum/act/op/A, gyro, rate)
	var/obj/machinery/power/emitter/gyrotron/G = gyro
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
				"ref" = "\ref[G]"
			)))

	data["gyros"] = gyros
	return data

/datum/tgui_module/gyrotron_control/ntos
	ntos = TRUE
