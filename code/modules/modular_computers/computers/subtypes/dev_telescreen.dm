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

/obj/item/modular_computer/telescreen/crowbar_act(mob/user, obj/item/tool)
	if(anchored)
		shutdown_computer()
		anchored = FALSE
		screen_on = FALSE
		pixel_x = 0
		pixel_y = 0
		to_chat(user, "You unsecure \the [src].")
		return ITEM_INTERACT_SUCCESS
	var/choice = tgui_input_list(user, "Where do you want to place \the [src]?", "Offset selection", list("North", "South", "West", "East", "This tile", "Cancel"))
	switch(choice)
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
			return ITEM_INTERACT_BLOCKING
	anchored = TRUE
	screen_on = TRUE
	to_chat(user, "You secure \the [src].")
	return ITEM_INTERACT_SUCCESS
