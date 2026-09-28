/obj/item/camera_assembly
	name = "camera assembly"
	desc = "A pre-fabricated security camera kit, ready to be assembled and mounted to a surface."
	icon = 'icons/obj/monitors_vr.dmi' // New Icons
	icon_state = "cameracase"
	w_class = ITEMSIZE_SMALL
	anchored = FALSE

	MATERIAL_MIX(list(MAT_STEEL = 700,MAT_GLASS = 300))

	//	Motion, EMP-Proof, X-Ray
	var/static/list/obj/item/possible_upgrades = list(/obj/item/assembly/prox_sensor, /obj/item/stack/material/osmium, /obj/item/stock_parts/scanning_module)
	var/list/upgrades // Lazy: installed upgrade items.
	var/camera_name
	var/camera_network
	var/state = 0
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
		LAZYADD(upgrades, W)
		user.remove_from_mob(W)
		W.forceMove(src)
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
	weld(tool, user, PROC_REF(welded), list(user))
	return TRUE

/obj/item/camera_assembly/proc/welded(mob/user)
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
	if(!LAZYLEN(upgrades))
		return FALSE
	var/obj/upgrade = locate(/obj) in upgrades
	if(upgrade)
		to_chat(user, span_notice("You unattach an upgrade from the assembly."))
		playsound(src, tool.usesound, 50, TRUE)
		upgrade.forceMove(get_turf(src))
		LAZYREMOVE(upgrades, upgrade)
	return TRUE

/obj/item/camera_assembly/screwdriver_act(mob/user, obj/item/tool)
	if(state != 3)
		return FALSE
	playsound(src, tool.usesound, 50, TRUE)
	om_prompt_sequence(src, user, list(
		list("key" = "networks", "kind" = "text", "message" = "Which networks would you like to connect this camera to? Separate networks with a comma. No Spaces!\nFor example: "+using_map.station_short+",Security,Secret ", "title" = "Set Network", "default" = camera_network ? camera_network : NETWORK_DEFAULT, "max_length" = MAX_MESSAGE_LEN),
		PROC_REF(ask_camera_name),
	), PROC_REF(camera_configured), list("requires" = PROMPT_ADJACENT))
	return TRUE

/obj/item/camera_assembly/proc/ask_camera_name(mob/user, datum/om/prompt/ask)
	var/list/tempnetwork = splittext(ask.get("networks") || "", ",")
	if(!length(tempnetwork))
		return null
	var/area/camera_area = get_area(src)
	var/temptag = "[sanitize(camera_area.name)] ([rand(1, 999)])"
	return list("key" = "name", "kind" = "text", "message" = "How would you like to name the camera?", "title" = "Set Camera Name", "default" = camera_name ? camera_name : temptag, "max_length" = MAX_NAME_LEN, "encode" = FALSE)

/obj/item/camera_assembly/proc/camera_configured(mob/user, datum/om/prompt/ask)
	if(!ask.get("networks"))
		to_chat(user, "No input found please hang up and try your call again.")
		return
	var/list/tempnetwork = splittext(ask.get("networks"), ",")
	if(tempnetwork.len < 1)
		to_chat(user, "No network found please hang up and try your call again.")
		return
	if(state != 3)
		return
	state = 4
	var/obj/machinery/camera/C = new(loc)
	forceMove(C)
	C.assembly = src
	C.auto_turn()
	C.replace_networks(uniqueList(tempnetwork))
	C.c_tag = sanitizeSafe(ask.get("name"), MAX_NAME_LEN)
	ask_camera_direction(user, C, 5)

/// Turns the new camera until the builder is happy, with up to `chances` more tries.
/obj/item/camera_assembly/proc/ask_camera_direction(mob/user, obj/machinery/camera/C, chances)
	om_prompt(C, user, list("kind" = "list", "message" = "Direction?", "title" = "Assembling Camera", "choices" = list("NORTH", "EAST", "SOUTH", "WEST", "LEAVE IT"), "requires" = PROMPT_ADJACENT, "data" = list("assembly" = src, "chances" = chances)), GLOBAL_PROC_REF(camera_direction_chosen))

/proc/camera_direction_chosen(obj/machinery/camera/C, mob/user, direct, datum/om/prompt/ask)
	if(direct != "LEAVE IT")
		C.dir = text2dir(direct)
	var/chances = ask.get("chances")
	if(chances > 0)
		om_prompt_chain(ask, list("message" = "Is this what you want? Chances Remaining: [chances]", "title" = "Confirmation", "choices" = list("Yes", "No")), GLOBAL_PROC_REF(camera_direction_confirmed))

/proc/camera_direction_confirmed(obj/machinery/camera/C, mob/user, answer, datum/om/prompt/ask)
	if(answer == "Yes")
		return
	var/obj/item/camera_assembly/assembly = ask.get("assembly")
	assembly.ask_camera_direction(user, C, ask.get("chances") - 1)

/obj/item/camera_assembly/update_icon()
	if(anchored)
		icon_state = "camera1"
	else
		icon_state = "cameracase"

/obj/item/camera_assembly/attack_hand(mob/user as mob)
	if(!anchored)
		..()

/// Welds (a timed tool job); `on_done` runs on src with `done_args` when it is done. 0 if busy or refused.
/obj/item/camera_assembly/proc/weld(obj/item/weldingtool/WT, mob/user, on_done, list/done_args)
	if(om_busy(src)) // a weld in progress claims it
		return 0
	var/result = use_tool(user, WT, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld the [src]..", receiver = src, on_done = PROC_REF(weld_finished), done_args = list(on_done, done_args), claims = TRUE)
	return result


/obj/item/camera_assembly/proc/weld_finished(on_done, list/done_args)
	if(on_done)
		call(src, on_done)(arglist(done_args))
