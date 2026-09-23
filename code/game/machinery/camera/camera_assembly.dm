/obj/item/camera_assembly
	name = "camera assembly"
	desc = "A pre-fabricated security camera kit, ready to be assembled and mounted to a surface."
	icon = 'icons/obj/monitors_vr.dmi' // New Icons
	icon_state = "cameracase"
	w_class = ITEMSIZE_SMALL
	anchored = FALSE

	matter = list(MAT_STEEL = 700,MAT_GLASS = 300)

	//	Motion, EMP-Proof, X-Ray
	var/list/obj/item/possible_upgrades = list(/obj/item/assembly/prox_sensor, /obj/item/stack/material/osmium, /obj/item/stock_parts/scanning_module)
	var/list/upgrades = list()
	var/camera_name
	var/camera_network
	var/state = 0
	var/busy = 0
	/*
				0 = Nothing done to it
				1 = Wrenched in place
				2 = Welded in place
				3 = Wires attached to it (you can now attach/dettach upgrades)
				4 = Screwdriver panel closed and is fully built (you cannot attach upgrades)
	*/


/obj/item/camera_assembly/attackby(obj/item/W as obj, mob/living/user as mob)
	switch(state)
		if(2)
			if(istype(W, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = W
				if(C.use(2))
					to_chat(user, span_notice("You add wires to the assembly."))
					state = 3
				else
					to_chat(user, span_warning("You need 2 coils of wire to wire the assembly."))
				return

	// Upgrades!
	if(is_type_in_list(W, possible_upgrades) && !is_type_in_list(W, upgrades)) // Is a possible upgrade and isn't in the camera already.
		to_chat(user, "You attach \the [W] into the assembly inner circuits.")
		upgrades += W
		user.remove_from_mob(W)
		W.loc = src
		return

	// Taking out upgrades
	..()

/obj/item/camera_assembly/wrench_act(mob/user, obj/item/tool)
	if(state == 0 && isturf(loc))
		playsound(src, tool.usesound, 50, TRUE)
		to_chat(user, span_notice("You wrench the assembly into place."))
		anchored = TRUE
		state = 1
		update_icon()
		auto_turn()
		return TRUE
	if(state == 1)
		playsound(src, tool.usesound, 50, TRUE)
		to_chat(user, span_notice("You unattach the assembly from its place."))
		anchored = FALSE
		state = 0
		update_icon()
		return TRUE
	return FALSE

/obj/item/camera_assembly/welder_act(mob/user, obj/item/tool)
	if(state != 1 && state != 2)
		return FALSE
	if(!weld(tool, user))
		return TRUE
	if(state == 1)
		to_chat(user, span_notice("You weld the assembly securely into place."))
		state = 2
	else
		to_chat(user, span_notice("You unweld the assembly from its place."))
		state = 1
	anchored = TRUE
	return TRUE

/obj/item/camera_assembly/wirecutter_act(mob/user, obj/item/tool)
	if(state != 3)
		return FALSE
	new /obj/item/stack/cable_coil(get_turf(src), 2)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You cut the wires from the circuits."))
	state = 2
	return TRUE

/obj/item/camera_assembly/crowbar_act(mob/user, obj/item/tool)
	if(!upgrades.len)
		return FALSE
	var/obj/upgrade = locate(/obj) in upgrades
	if(upgrade)
		to_chat(user, span_notice("You unattach an upgrade from the assembly."))
		playsound(src, tool.usesound, 50, TRUE)
		upgrade.loc = get_turf(src)
		upgrades -= upgrade
	return TRUE

/obj/item/camera_assembly/screwdriver_act(mob/user, obj/item/tool)
	if(state != 3)
		return FALSE
	playsound(src, tool.usesound, 50, TRUE)
	var/input = tgui_input_text(user, "Which networks would you like to connect this camera to? Separate networks with a comma. No Spaces!\nFor example: "+using_map.station_short+",Security,Secret ", "Set Network", camera_network ? camera_network : NETWORK_DEFAULT, MAX_MESSAGE_LEN)
	if(!input)
		to_chat(user, "No input found please hang up and try your call again.")
		return TRUE
	var/list/tempnetwork = splittext(input, ",")
	if(tempnetwork.len < 1)
		to_chat(user, "No network found please hang up and try your call again.")
		return TRUE
	var/area/camera_area = get_area(src)
	var/temptag = "[sanitize(camera_area.name)] ([rand(1, 999)])"
	input = sanitizeSafe(tgui_input_text(user, "How would you like to name the camera?", "Set Camera Name", camera_name ? camera_name : temptag, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
	state = 4
	var/obj/machinery/camera/C = new(loc)
	loc = C
	C.assembly = src
	C.auto_turn()
	C.replace_networks(uniqueList(tempnetwork))
	C.c_tag = input
	for(var/i = 5; i >= 0; i -= 1)
		var/direct = tgui_input_list(user, "Direction?", "Assembling Camera", list("NORTH", "EAST", "SOUTH", "WEST", "LEAVE IT"))
		if(direct != "LEAVE IT")
			C.dir = text2dir(direct)
		if(i != 0 && tgui_alert(user, "Is this what you want? Chances Remaining: [i]", "Confirmation", list("Yes", "No")) == "Yes")
			break
	return TRUE

/obj/item/camera_assembly/update_icon()
	if(anchored)
		icon_state = "camera1"
	else
		icon_state = "cameracase"

/obj/item/camera_assembly/attack_hand(mob/user as mob)
	if(!anchored)
		..()

/obj/item/camera_assembly/proc/weld(obj/item/weldingtool/WT, mob/user)
	if(busy)
		return 0
	busy = 1
	var/result = use_tool(user, WT, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld the [src]..")
	busy = 0
	return result
