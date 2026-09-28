/* Windoor (window door) assembly -Nodrak
 * Step 1: Create a windoor out of rglass
 * Step 2: Add r-glass to the assembly to make a secure windoor (Optional)
 * Step 3: Rotate or Flip the assembly to face and open the way you want
 * Step 4: Wrench the assembly in place
 * Step 5: Add cables to the assembly
 * Step 6: Set access for the door.
 * Step 7: Screwdriver the door to complete
 */

/obj/structure/windoor_assembly
	name = "windoor assembly"
	icon = 'icons/obj/doors/windoor.dmi'
	icon_state = "l_windoor_assembly01"
	anchored = FALSE
	density = FALSE
	dir = NORTH
	w_class = ITEMSIZE_NORMAL

	var/obj/item/airlock_electronics/electronics = null
	var/created_name = null

	//Vars to help with the icon's name
	var/facing = "l"	//Does the windoor open to the left or right?
	var/secure = ""		//Whether or not this creates a secure windoor
	var/state = "01"	//How far the door assembly has progressed in terms of sprites
	var/step = null		//How far the door assembly has progressed in terms of steps

/obj/structure/windoor_assembly/secure
	name = "secure windoor assembly"
	secure = "secure_"
	icon_state = "l_secure_windoor_assembly01"

/obj/structure/windoor_assembly/Initialize(mapload, start_dir=NORTH, constructed=0)
	. = ..()
	if(constructed)
		state = "01"
		anchored = FALSE
	switch(start_dir)
		if(NORTH, SOUTH, EAST, WEST)
			set_dir(start_dir)
		else //If the user is facing northeast. northwest, southeast, southwest or north, default to north
			set_dir(NORTH)
	update_state()

	update_nearby_tiles(need_rebuild=1)
	make_rotatable()

/obj/structure/windoor_assembly/update_icon()
	icon_state = "[facing]_[secure]windoor_assembly[state]"

/obj/structure/windoor_assembly/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == GLOB.reverse_dir[dir]) // From elsewhere to here, can't move against our dir
		return !density
	return TRUE

/obj/structure/windoor_assembly/Uncross(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSGLASS))
		return TRUE
	if(get_dir(mover, target) == dir) // From here to elsewhere, can't move in our dir
		return !density
	else
		return TRUE

/obj/structure/windoor_assembly/proc/rename_door(mob/living/user)
	om_ask(user, /datum/om/prompt/text, PROC_REF(windoor_named), title = name, message = "Enter the name for the windoor.", default = created_name, max_length = MAX_NAME_LEN, encode = FALSE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/obj/structure/windoor_assembly/proc/windoor_named(datum/om/prompt/text/ask)
	created_name = sanitizeSafe(ask.text, MAX_NAME_LEN)
	update_state()

/// Old attack_robot: drones and engineering borgs rename the assembly. Never fell through.
/obj/structure/windoor_assembly/proc/windoor_robot_rename(mob/living/silicon/robot/user, obj/item/held, datum/interaction/interaction)
	if(Adjacent(user) && user.module?.names_assemblies) //Only drones and engineering borgs need this.
		rename_door(user)
	return TRUE

/obj/structure/windoor_assembly/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_ROBOT("Rename", PROC_REF(windoor_robot_rename)),
		INTERACT_VERB("Flip Windoor Assembly", PROC_REF(windoor_assembly_flip_effect)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/entry_item/windoor_assembly_item,
	)
	..()

/// Old attackby: rename with a pen, wire, or install electronics.
/datum/interaction/entry_item/windoor_assembly_item
	id = "windoor_assembly_item"
	name = "Use"
	effect = /obj/structure/windoor_assembly/proc/interaction_item

/obj/structure/windoor_assembly/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/pen))
		rename_door(user)
		return TRUE

	if(state == "01")
		//Adding cable to the assembly. Step 5 complete.
		if(istype(W, /obj/item/stack/cable_coil) && anchored)
			user.visible_message("[user] wires the windoor assembly.", "You start to wire the windoor assembly.")

			var/obj/item/stack/cable_coil/CC = W
			om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, CC))

	else if(state == "02")
		//Adding airlock electronics for access. Step 6 complete.
		if(istype(W, /obj/item/airlock_electronics))
			playsound(src, 'sound/items/Screwdriver.ogg', 100, 1)
			user.visible_message("[user] installs the electronics into the airlock assembly.", "You start to install electronics into the airlock assembly.")

			om_task_start(/datum/om/task/timed/windoor_assembly_attackby, user, src, W = W)

	//Update to reflect changes(if applicable)
	update_state()
	return TRUE

/obj/structure/windoor_assembly/proc/attackby_timed_done(mob/user, obj/item/stack/cable_coil/CC)
	if (CC.use(1))
		to_chat(user,span_notice("You wire the windoor!"))
		src.state = "02"
		step = 1
/datum/om/task/timed/windoor_assembly_attackby
	duration = 4 SECONDS
	complete_proc = /obj/structure/windoor_assembly/proc/attackby_timed_done2
	cancel_proc = /obj/structure/windoor_assembly/proc/attackby_timed_failed2
	var/obj/item/W

/obj/structure/windoor_assembly/proc/attackby_timed_done2(datum/om/task/timed/windoor_assembly_attackby/task)
	var/obj/item/W = task.W
	var/mob/user = task.actor
	if(!src) return

	user.drop_item()
	W.forceMove(src)
	to_chat(user,span_notice("You've installed the airlock electronics!"))
	step = 2
	src.electronics = W

/obj/structure/windoor_assembly/proc/attackby_timed_failed2(datum/om/task/timed/windoor_assembly_attackby/task)
	var/obj/item/W = task.W
	W.forceMove(src.loc)

/obj/structure/windoor_assembly/welder_act(mob/user, obj/item/W)
	if(state != "01" || anchored)
		update_state()
		return NONE
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to disassemble the windoor assembly.", message_others = "[user] disassembles the windoor assembly.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/windoor_assembly/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You disassembled the windoor assembly!"))
	if(secure)
		new /obj/item/stack/material/glass/reinforced(get_turf(src), 2)
	else
		new /obj/item/stack/material/glass(get_turf(src), 2)
	qdel(src)

/obj/structure/windoor_assembly/wrench_act(mob/user, obj/item/W)
	if(state != "01")
		update_state()
		return NONE
	if(!anchored)
		//Wrenching an unsecure assembly anchors it in place. Step 4 complete
		use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 100, message_self = "You start to secure the windoor assembly to the floor.", message_others = "[user] secures the windoor assembly to the floor.", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	else
		//Unwrenching an unsecure assembly un-anchors it. Step 4 undone
		use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 100, message_self = "You start to unsecure the windoor assembly to the floor.", message_others = "[user] unsecures the windoor assembly to the floor.", receiver = src, on_done = PROC_REF(wrench_act_tool_done2), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/windoor_assembly/proc/wrench_act_tool_done(mob/user)
	to_chat(user,span_notice("You've secured the windoor assembly!"))
	src.anchored = TRUE
	step = 0
/obj/structure/windoor_assembly/proc/wrench_act_tool_done2(mob/user)
	to_chat(user,span_notice("You've unsecured the windoor assembly!"))
	src.anchored = FALSE
	step = null

/obj/structure/windoor_assembly/wirecutter_act(mob/user, obj/item/W)
	if(state != "02" || src.electronics)
		update_state()
		return NONE
	//Removing wire from the assembly. Step 5 undone.
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WIRECUTTER, volume = 100, message_self = "You start to cut the wires from airlock assembly.", message_others = "[user] cuts the wires from the airlock assembly.", receiver = src, on_done = PROC_REF(wirecutter_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/windoor_assembly/proc/wirecutter_act_tool_done(mob/user)
	to_chat(user,span_notice("You cut the windoor wires.!"))
	new/obj/item/stack/cable_coil(get_turf(user), 1)
	src.state = "01"
	step = 0

/obj/structure/windoor_assembly/screwdriver_act(mob/user, obj/item/W)
	if(state != "02" || !src.electronics)
		update_state()
		return NONE
	//Screwdriver to remove airlock electronics. Step 6 undone.
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_SCREWDRIVER, volume = 100, message_self = "You start to uninstall electronics from the airlock assembly.", message_others = "[user] removes the electronics from the airlock assembly.", receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/windoor_assembly/proc/screwdriver_act_tool_done(mob/user)
	if(!src.electronics) return ITEM_INTERACT_SUCCESS
	to_chat(user,span_notice("You've removed the airlock electronics!"))
	step = 1
	var/obj/item/airlock_electronics/ae = electronics
	electronics = null
	ae.forceMove(src.loc)

/obj/structure/windoor_assembly/crowbar_act(mob/user, obj/item/W)
	if(state != "02")
		update_state()
		return NONE
	//Crowbar to complete the assembly, Step 7 complete.
	if(!src.electronics)
		to_chat(user,span_warning("The assembly is missing electronics."))
		return ITEM_INTERACT_SUCCESS
	if(src.electronics && istype(src.electronics, /obj/item/circuitboard/broken))
		to_chat(user,span_warning("The assembly has broken airlock electronics."))
		return ITEM_INTERACT_SUCCESS
	// close TGUI panel (legacy browse(null))
	SStgui.close_uis(src)
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_CROWBAR, volume = 100, message_self = "You start prying the windoor into the frame.", message_others = "[user] pries the windoor into the frame.", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/windoor_assembly/proc/crowbar_act_tool_done(mob/user)
	density = TRUE //Shouldn't matter but just incase
	to_chat(user,span_notice("You finish the windoor!"))

	if(secure)
		var/obj/machinery/door/window/brigdoor/windoor = new /obj/machinery/door/window/brigdoor(src.loc)
		if(src.facing == "l")
			windoor.icon_state = "leftsecureopen"
			windoor.base_state = "leftsecure"
		else
			windoor.icon_state = "rightsecureopen"
			windoor.base_state = "rightsecure"
		windoor.set_dir(src.dir)
		windoor.density = FALSE
		if(created_name)
			windoor.name = created_name
		om_after(windoor, 0, TYPE_PROC_REF(/obj/machinery/door, close))

		if(src.electronics.one_access)
			windoor.req_access = null
			windoor.req_one_access = src.electronics.conf_access
		else
			windoor.req_access = src.electronics.conf_access
		windoor.electronics = src.electronics
		src.electronics.forceMove(windoor)
	else
		var/obj/machinery/door/window/windoor = new /obj/machinery/door/window(src.loc)
		if(src.facing == "l")
			windoor.icon_state = "leftopen"
			windoor.base_state = "left"
		else
			windoor.icon_state = "rightopen"
			windoor.base_state = "right"
		windoor.set_dir(src.dir)
		windoor.density = FALSE
		if(created_name)
			windoor.name = created_name
		om_after(windoor, 0, TYPE_PROC_REF(/obj/machinery/door, close))

		if(src.electronics.one_access)
			windoor.req_access = null
			windoor.req_one_access = src.electronics.conf_access
		else
			windoor.req_access = src.electronics.conf_access
		windoor.electronics = src.electronics
		src.electronics.forceMove(windoor)

	qdel(src)

/obj/structure/windoor_assembly/proc/update_state()
	update_icon()
	name = ""
	switch(step)
		if (0)
			name = "anchored "
		if (1)
			name = "wired "
		if (2)
			name = "near finished "
	name += "[secure ? "secure " : ""]windoor assembly[created_name ? " ([created_name])" : ""]"

/obj/structure/windoor_assembly/handle_rotation_verbs(angle, mob/user)
	if(state != "01")
		update_nearby_tiles(need_rebuild=1) //Compel updates before
	. = ..()
	if(.)
		if(state != "01")
			update_nearby_tiles(need_rebuild=1)
		update_icon()

//Flips the windoor assembly, determines whather the door opens to the left or the right
/obj/structure/windoor_assembly/proc/windoor_assembly_flip_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(src.facing == "l")
		to_chat(user,"The windoor will now slide to the right.")
		src.facing = "r"
	else
		src.facing = "l"
		to_chat(user,"The windoor will now slide to the left.")

	update_icon()
	return

REF_HELD(/obj/structure/windoor_assembly, list("electronics"))
