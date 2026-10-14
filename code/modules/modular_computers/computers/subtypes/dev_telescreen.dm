/obj/item/modular_computer/telescreen
	name = "telescreen"
	desc = "A wall-mounted touchscreen computer."
	icon = 'icons/obj/modular_telescreen.dmi'
	icon_state = "telescreen"
	layer = ABOVE_WINDOW_LAYER
	icon_state_unpowered = "telescreen"
	icon_state_menu = "menu"
	icon_state_screensaver = "standby"
	hardware_flag = PROGRAM_TELESCREEN
	anchored = TRUE
	density = FALSE
	base_idle_power_usage = 75
	base_active_power_usage = 300
	max_hardware_size = 2
	steel_sheet_cost = 10
	light_strength = 4
	max_integrity = 300
	integrity_failure = 0.5 // Stops working below 150 integrity.
	w_class = ITEMSIZE_HUGE

/// The crowbar asks where to mount a loose telescreen; a mounted one comes off at once.
/obj/item/modular_computer/telescreen/proc/telescreen_loose(datum/act/op/A)
	return !anchored

/// A mounted telescreen is taken down; a loose one is mounted where the answer says.
/obj/item/modular_computer/telescreen/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(anchored)
		shutdown_computer()
		set_anchored(FALSE)
		screen_on = FALSE
		pixel_x = 0
		pixel_y = 0
		to_chat(user, "You unsecure \the [src].")
		return OP_OK
	switch(A.step_value("offset"))
		if("North")
			pixel_y = 32
		if("South")
			pixel_y = -32
		if("West")
			pixel_x = -32
		if("East")
			pixel_x = 32
		if("This tile")
			pixel_x = 0
			pixel_y = 0
		else
			return OP_OK
	set_anchored(TRUE)
	screen_on = TRUE
	to_chat(user, "You secure \the [src].")
	return OP_OK

CAPABILITIES(/obj/item/modular_computer/telescreen)
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0),
		asks(/datum/prompt/choice, fields = list("question" = "Where do you want to place \the [src]?", "title" = "Offset selection", "choices" = list("North", "South", "West", "East", "This tile", "Cancel")), step = "offset", when = PROC_REF(telescreen_loose)),
		then(PROC_REF(crowbar_used)))
