// ALLOW(sys_tgui_data_override): the data depends on the instance
/obj/al/tgui_data(mob/user)
	return list()

/obj/al2/tgui_interact(mob/user) // ALLOW(sys_tgui_interact_boilerplate): custom window
	return

/obj/al3/tgui_state(mob/user)
	// ALLOW(sys_tgui_state_override): shared constant on purpose
	return GLOB.default_state

/obj/al4/proc/f(mob/user)
	// ALLOW(sys_tgui_interact_boilerplate): hand opened by design
	ui = new(user, src, "Z")
	// ALLOW(sys_tgui_interact_boilerplate)
	ui = new(user, src, "Y")
	var/a = text2num(params["n"]) // ALLOW(sys_text2num_params): legacy
	// ALLOW(sys_text2num_params): above
	var/b = text2num(params["n"])
	var/c = text2num(params["n"])

/obj/al5/tgui_act(action, list/params) // ALLOW(sys_ui_act_dispatch): last legacy override
	return ..()
