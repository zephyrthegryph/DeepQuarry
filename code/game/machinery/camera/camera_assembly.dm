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


/// Old attackby.
/obj/item/camera_assembly/proc/interaction_item(mob/living/user, obj/item/W, datum/interaction/interaction)
	switch(state)
		if(2)
			if(istype(W, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = W
				if(C.use(2))
					to_chat(user, span_notice("You add wires to the assembly."))
					state = 3
				else
					to_chat(user, span_warning("You need 2 coils of wire to wire the assembly."))
				return INTERACTION_HANDLED_PASS

	// Upgrades!
	if(is_type_in_list(W, possible_upgrades) && !is_type_in_list(W, upgrades)) // Is a possible upgrade and isn't in the camera already.
		to_chat(user, "You attach \the [W] into the assembly inner circuits.")
		rel_add(src, "upgrades", W)
		user.remove_from_mob(W)
		W.forceMove(src)
		return INTERACTION_HANDLED_PASS

	// Taking out upgrades
	return FALSE

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
	var/obj/upgrade = locate_in_list(upgrades, /obj)
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
	om_ask(user, /datum/om/prompt/text, PROC_REF(camera_networks_entered), message = "Which networks would you like to connect this camera to? Separate networks with a comma. No Spaces!\nFor example: "+using_map.station_short+",Security,Secret ", default = camera_network ? camera_network : NETWORK_DEFAULT, title = "Set Network", requires = PROMPT_ADJACENT)
	return TRUE

/obj/item/camera_assembly/proc/camera_networks_entered(datum/om/prompt/text/ask)
	if(!ask.text)
		to_chat(ask.answerer, "No input found please hang up and try your call again.")
		return
	var/list/tempnetwork = splittext(ask.text, ",")
	if(tempnetwork.len < 1)
		to_chat(ask.answerer, "No network found please hang up and try your call again.")
		return
	var/area/camera_area = get_area(src)
	var/temptag = "[sanitize(camera_area.name)] ([rand(1, 999)])"
	om_ask(ask.answerer, /datum/om/prompt/text/camera_name, PROC_REF(camera_configured), default = camera_name ? camera_name : temptag, networks = tempnetwork)

/datum/om/prompt/text/camera_name
	title = "Set Camera Name"
	message = "How would you like to name the camera?"
	max_length = MAX_NAME_LEN
	encode = FALSE
	requires = PROMPT_ADJACENT
	var/list/networks

/datum/om/prompt/text/camera_name/valid()
	var/obj/item/camera_assembly/A = subject
	return A.state == 3 ? null : "wrong state"

/obj/item/camera_assembly/proc/camera_configured(datum/om/prompt/text/camera_name/ask)
	state = 4
	var/obj/machinery/camera/C = new(loc)
	forceMove(C)
	own_set(C, "assembly", src)
	C.auto_turn()
	C.replace_networks(uniqueList(ask.networks))
	C.c_tag = sanitizeSafe(ask.text, MAX_NAME_LEN)
	ask_camera_direction(ask.answerer, C, 5)

/// Turns the new camera until the builder is happy, with up to `chances` more tries.
/obj/item/camera_assembly/proc/ask_camera_direction(mob/user, obj/machinery/camera/C, chances)
	om_ask(user, /datum/om/prompt/choice/camera_direction, PROC_REF(camera_direction_chosen), subject = C, camera = C, chances = chances)

/datum/om/prompt/choice/camera_direction
	title = "Assembling Camera"
	message = "Direction?"
	choices = list("NORTH", "EAST", "SOUTH", "WEST", "LEAVE IT")
	requires = PROMPT_ADJACENT
	var/obj/machinery/camera/camera
	var/chances = 0

/obj/item/camera_assembly/proc/camera_direction_chosen(datum/om/prompt/choice/camera_direction/ask)
	var/obj/machinery/camera/C = ask.camera
	if(ask.choice != "LEAVE IT")
		C.dir = text2dir(ask.choice)
	if(ask.chances > 0)
		om_ask(ask.answerer, /datum/om/prompt/confirm/camera_direction_ok, PROC_REF(camera_direction_confirmed), subject = C, camera = C, chances = ask.chances)

/datum/om/prompt/confirm/camera_direction_ok
	title = "Confirmation"
	answer_on_no = TRUE
	var/obj/machinery/camera/camera
	var/chances = 0

/datum/om/prompt/confirm/camera_direction_ok/prepare()
	message = "Is this what you want? Chances Remaining: [chances]"
	return TRUE

/obj/item/camera_assembly/proc/camera_direction_confirmed(datum/om/prompt/confirm/camera_direction_ok/ask)
	if(ask.yes)
		return
	ask_camera_direction(ask.answerer, ask.camera, ask.chances - 1)

/obj/item/camera_assembly/update_icon()
	if(anchored)
		icon_state = "camera1"
	else
		icon_state = "cameracase"

DECLARE_INTERACTIONS(/obj/item/camera_assembly, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_hand.
/obj/item/camera_assembly/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(!anchored)
		return FALSE
	return TRUE

/// Welds (a timed tool job); `on_done` runs on src with `done_args` when it is done. 0 if busy or refused.
/obj/item/camera_assembly/proc/weld(obj/item/weldingtool/WT, mob/user, on_done, list/done_args)
	if(om_busy(src)) // a weld in progress claims it
		return 0
	var/result = use_tool(user, WT, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld the [src]..", receiver = src, on_done = PROC_REF(weld_finished), done_args = list(on_done, done_args), claims = TRUE)
	return result


/obj/item/camera_assembly/proc/weld_finished(on_done, list/done_args)
	if(on_done)
		call(src, on_done)(arglist(done_args))
