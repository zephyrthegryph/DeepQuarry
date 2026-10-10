TRACKED(/obj/item/camera_assembly, state)
MATERIAL_MIX(/obj/item/camera_assembly, list(MAT_STEEL = 700,MAT_GLASS = 300))
/obj/item/camera_assembly
	name = "camera assembly"
	desc = "A pre-fabricated security camera kit, ready to be assembled and mounted to a surface."
	icon = 'icons/obj/monitors_vr.dmi' // New Icons
	icon_state = "cameracase"
	w_class = ITEMSIZE_SMALL
	anchored = FALSE


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

CAPABILITIES(/obj/item/camera_assembly)
	op("use_welder", lit_welder(fuel = 0), when(PROC_REF(weld_available)), claims(), begins(PROC_REF(weld_start_message)), starts(PROC_REF(weld_started)), wait(PROC_REF(weld_duration)), then(PROC_REF(welded)))
	owns_many(nameof(upgrades))
	op("hand", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_item)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("use_crowbar", tool(TOOL_CROWBAR), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))


/// Old attackby.
/obj/item/camera_assembly/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	switch(state)
		if(2)
			if(istype(W, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = W
				if(C.use(2))
					to_chat(user, span_notice("You add wires to the assembly."))
					set_state(3)
				else
					to_chat(user, span_warning("You need 2 coils of wire to wire the assembly."))
				return OP_PASS

	// Upgrades!
	if(is_type_in_list(W, possible_upgrades) && !is_type_in_list(W, upgrades)) // Is a possible upgrade and isn't in the camera already.
		if(!move_into(src, nameof(upgrades), W, user))
			return OP_PASS
		to_chat(user, "You attach \the [W] into the assembly inner circuits.")
		return OP_PASS

	// Taking out upgrades
	return OP_DECLINE

/obj/item/camera_assembly/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(state == 0 && isturf(loc))
		playsound(src, tool.usesound, 50, TRUE)
		to_chat(user, span_notice("You wrench the assembly into place."))
		set_anchored(TRUE)
		set_state(1)
		auto_turn()
		return OP_OK
	if(state == 1)
		playsound(src, tool.usesound, 50, TRUE)
		to_chat(user, span_notice("You unattach the assembly from its place."))
		set_anchored(FALSE)
		set_state(0)
		return OP_OK
	return OP_DECLINE

/obj/item/camera_assembly/proc/weld_available(datum/act/op/A)
	return state == 1 || state == 2

/obj/item/camera_assembly/proc/weld_start_message(datum/act/op/A)
	return msg_text("You start to weld the [src]..")

/obj/item/camera_assembly/proc/weld_started(datum/act/op/A)
	var/obj/item/W = A.held_provider()
	var/obj/item/weldingtool/welder = W.get_welder()
	welder.eyecheck(A.actor)
	if(W.usesound)
		play_sfx(src, W.usesound, volume = 50, vary = TRUE)
	return OP_OK

/obj/item/camera_assembly/proc/weld_duration(datum/act/op/A)
	var/obj/item/W = A.held_provider()
	return 2 SECONDS * W.toolspeed * tool_skill_factor(A.actor, TOOL_WELDER)

/obj/item/camera_assembly/proc/welded(datum/act/op/A)
	if(state == 1)
		to_chat(A.actor, span_notice("You weld the assembly securely into place."))
		set_state(2)
	else
		to_chat(A.actor, span_notice("You unweld the assembly from its place."))
		set_state(1)
	set_anchored(TRUE)
	return OP_OK

/obj/item/camera_assembly/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(state != 3)
		return OP_DECLINE
	new /obj/item/stack/cable_coil(get_turf(src), 2)
	playsound(src, tool.usesound, 50, TRUE)
	to_chat(user, span_notice("You cut the wires from the circuits."))
	set_state(2)
	return OP_OK

/obj/item/camera_assembly/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!LAZYLEN(upgrades))
		return OP_DECLINE
	var/obj/upgrade = locate_in_list(upgrades, /obj)
	if(upgrade)
		to_chat(user, span_notice("You unattach an upgrade from the assembly."))
		playsound(src, tool.usesound, 50, TRUE)
		rel_take(src, nameof(upgrades), upgrade)
		upgrade.forceMove(get_turf(src))
	return OP_OK

/obj/item/camera_assembly/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(state != 3)
		return OP_DECLINE
	playsound(src, tool.usesound, 50, TRUE)
	ask_camera_networks(user)
	return OP_OK

/// The wired assembly's first configuration question (its networks); the answer asks for the name.
/obj/item/camera_assembly/proc/ask_camera_networks(mob/user)
	open_request(src, /datum/prompt/text, PROC_REF(camera_networks_entered), answerer = user, title = "Set Network", question = "Which networks would you like to connect this camera to? Separate networks with a comma. No Spaces!\nFor example: "+using_map.station_short+",Security,Secret ", default = camera_network ? camera_network : NETWORK_DEFAULT, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/obj/item/camera_assembly/proc/camera_networks_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	if(!A.answer.value)
		to_chat(user, "No input found please hang up and try your call again.")
		return
	var/list/tempnetwork = splittext(A.answer.value, ",")
	if(tempnetwork.len < 1)
		to_chat(user, "No network found please hang up and try your call again.")
		return
	var/area/camera_area = get_area(src)
	var/temptag = "[sanitize(camera_area.name)] ([rand(1, 999)])"
	open_request(src, /datum/prompt/text/camera_name, PROC_REF(camera_configured), valid = PROC_REF(camera_state_ok), answerer = user, title = "Set Camera Name", question = "How would you like to name the camera?", default = camera_name ? camera_name : temptag, max_len = MAX_NAME_LEN, encode = FALSE, networks = tempnetwork, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/// The camera's naming question: the networks chosen so far are kept on it.
/datum/prompt/text/camera_name
	var/list/networks

/// Re-checked on the answer: the assembly is still wired and not yet closed up.
/obj/item/camera_assembly/proc/camera_state_ok(datum/request/R)
	return state == 3

/obj/item/camera_assembly/proc/camera_configured(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/camera_name/R = A.request
	set_state(4)
	var/obj/machinery/camera/C = new(loc)
	forceMove(C)
	rel_set(C, nameof(C.assembly), src)
	C.auto_turn()
	C.replace_networks(uniqueList(R.networks))
	C.c_tag = sanitizeSafe(A.answer.value, MAX_NAME_LEN)
	ask_camera_direction(R.answerer, C, 5)

/// Turns the new camera until the builder is happy, with up to `chances` more tries.
/obj/item/camera_assembly/proc/ask_camera_direction(mob/user, obj/machinery/camera/C, chances)
	open_request(src, /datum/prompt/choice/camera_direction, PROC_REF(camera_direction_chosen), answerer = user, title = "Assembling Camera", question = "Direction?", choices = list("NORTH", "EAST", "SOUTH", "WEST", "LEAVE IT"), camera = C, chances = chances, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/datum/prompt/choice/camera_direction
	var/obj/machinery/camera/camera
	var/chances = 0

CAPABILITIES(/datum/prompt/choice/camera_direction)
	ref_one(nameof(camera), /obj/machinery/camera)

/obj/item/camera_assembly/proc/camera_direction_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/camera_direction/R = A.request
	var/obj/machinery/camera/C = R.camera
	if(A.answer.value != "LEAVE IT")
		C.dir = text2dir(A.answer.value)
	if(R.chances > 0)
		open_request(src, /datum/prompt/yes_no/camera_direction_ok, PROC_REF(camera_direction_confirmed), answerer = R.answerer, title = "Confirmation", question = "Is this what you want? Chances Remaining: [R.chances]", camera = C, chances = R.chances, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)

/datum/prompt/yes_no/camera_direction_ok
	var/obj/machinery/camera/camera
	var/chances = 0

CAPABILITIES(/datum/prompt/yes_no/camera_direction_ok)
	ref_one(nameof(camera), /obj/machinery/camera)

/obj/item/camera_assembly/proc/camera_direction_confirmed(datum/act/request/A)
	var/datum/prompt/yes_no/camera_direction_ok/R = A.request
	if(!A.answer || A.answer.value)
		return
	ask_camera_direction(R.answerer, R.camera, R.chances - 1)

/// The look (the draw sweep: from its layers).
/obj/item/camera_assembly/draw(datum/look/look)
	..()
	switch("[anchored]")
		if("1")
			look.state("camera1")
		else
			look.state("cameracase")

/// Old attack_hand.
/obj/item/camera_assembly/proc/interaction_hand(datum/act/op/A)
	if(!anchored)
		return OP_DECLINE
	return TRUE
