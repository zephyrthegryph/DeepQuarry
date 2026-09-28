/obj/structure/door_assembly
	name = "airlock assembly"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_as_0"
	anchored = FALSE
	density = TRUE
	w_class = ITEMSIZE_HUGE
	var/state = 0
	var/base_icon_state = ""
	var/base_name = "airlock"
	var/obj/item/airlock_electronics/electronics = null
	var/airlock_type = "" //the type path of the airlock once completed
	var/glass_type = "/glass"
	var/glass = 0 // 0 = glass can be installed. -1 = glass can't be installed. 1 = glass is already installed. Text = mineral plating is installed instead.
	var/created_name = null

/obj/structure/door_assembly/Initialize(mapload)
	. = ..()
	update_state()

/obj/structure/door_assembly/door_assembly_com
	base_icon_state = "com"
	base_name = "Command airlock"
	glass_type = "/glass_command"
	airlock_type = "/command"

/obj/structure/door_assembly/door_assembly_sec
	base_icon_state = "sec"
	base_name = "Security airlock"
	glass_type = "/glass_security"
	airlock_type = "/security"

/obj/structure/door_assembly/door_assembly_eng
	base_icon_state = "eng"
	base_name = "Engineering airlock"
	glass_type = "/glass_engineering"
	airlock_type = "/engineering"

/obj/structure/door_assembly/door_assembly_eat
	base_icon_state = "eat"
	base_name = "Engineering atmos airlock"
	glass_type = "/glass_engineeringatmos"
	airlock_type = "/engineering"

/obj/structure/door_assembly/door_assembly_min
	base_icon_state = "min"
	base_name = "Mining airlock"
	glass_type = "/glass_mining"
	airlock_type = "/mining"

/obj/structure/door_assembly/door_assembly_atmo
	base_icon_state = "atmo"
	base_name = "Atmospherics airlock"
	glass_type = "/glass_atmos"
	airlock_type = "/atmos"

/obj/structure/door_assembly/door_assembly_research
	base_icon_state = "res"
	base_name = "Research airlock"
	glass_type = "/glass_research"
	airlock_type = "/research"

/obj/structure/door_assembly/door_assembly_science
	base_icon_state = "sci"
	base_name = "Science airlock"
	glass_type = "/glass_science"
	airlock_type = "/science"

/obj/structure/door_assembly/door_assembly_med
	base_icon_state = "med"
	base_name = "Medical airlock"
	glass_type = "/glass_medical"
	airlock_type = "/medical"

/obj/structure/door_assembly/door_assembly_ext
	base_icon_state = "ext"
	base_name = "External airlock"
	glass_type = "/glass_external"
	airlock_type = "/external"

/obj/structure/door_assembly/door_assembly_mai
	base_icon_state = "mai"
	base_name = "Maintenance airlock"
	airlock_type = "/maintenance"
	glass = -1

/obj/structure/door_assembly/door_assembly_fre
	base_icon_state = "fre"
	base_name = "Freezer airlock"
	airlock_type = "/freezer"
	glass = -1

/obj/structure/door_assembly/door_assembly_hatch
	base_icon_state = "hatch"
	base_name = "airtight hatch"
	airlock_type = "/hatch"
	glass = -1

/obj/structure/door_assembly/door_assembly_mhatch
	base_icon_state = "mhatch"
	base_name = "maintenance hatch"
	airlock_type = "/maintenance_hatch"
	glass = -1

/obj/structure/door_assembly/door_assembly_highsecurity // Borrowing this until WJohnston makes sprites for the assembly
	base_icon_state = "highsec"
	base_name = "high security airlock"
	airlock_type = "/highsecurity"
	glass = -1

/obj/structure/door_assembly/door_assembly_voidcraft
	base_icon_state = "voidcraft"
	base_name = "voidcraft hatch"
	airlock_type = "/voidcraft"
	glass = -1

/obj/structure/door_assembly/door_assembly_voidcraft/vertical
	base_icon_state = "voidcraft_vertical"
	airlock_type = "/voidcraft/vertical"

/obj/structure/door_assembly/door_assembly_alien
	base_icon_state = "alien"
	base_name = "alien airlock"
	airlock_type = "/alien"
	glass = -1

/obj/structure/door_assembly/multi_tile
	icon = 'icons/obj/doors/door_assembly2x1.dmi'
	dir = EAST
	var/width = 1

	base_icon_state = "g" //Remember to delete this line when reverting "glass" var to 1.
	airlock_type = "/multi_tile/glass"
	glass = -1 //To prevent bugs in deconstruction process.

/obj/structure/door_assembly/multi_tile/Initialize(mapload)
	if(dir in list(EAST, WEST))
		bound_width = width * world.icon_size
		bound_height = world.icon_size
	else
		bound_width = world.icon_size
		bound_height = width * world.icon_size
	. = ..()

/obj/structure/door_assembly/multi_tile/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(dir in list(EAST, WEST))
		bound_width = width * world.icon_size
		bound_height = world.icon_size
	else
		bound_width = world.icon_size
		bound_height = width * world.icon_size

/obj/structure/door_assembly/proc/rename_door(mob/living/user)
	om_ask(user, /datum/om/prompt/text, PROC_REF(door_named), title = name, message = "Enter the name for the [base_name].", default = created_name, max_length = MAX_NAME_LEN, encode = FALSE, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/obj/structure/door_assembly/proc/door_named(datum/om/prompt/text/ask)
	created_name = sanitizeSafe(ask.text, MAX_NAME_LEN)
	update_state()

/// Old attack_robot: drones and engineering borgs next to it rename it.
/obj/structure/door_assembly/proc/door_assembly_robot_rename(mob/living/silicon/robot/user, obj/item/held, datum/interaction/interaction)
	if(istype(user) && Adjacent(user) && user.module?.names_assemblies) //Only drones and engineering borgs need this.
		rename_door(user)
	return TRUE

/obj/structure/door_assembly/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/door_assembly_item,
	)
	into += dq_interaction_from_spec(type, INTERACT_ROBOT("Rename", PROC_REF(door_assembly_robot_rename)))
	..()

/// Old attackby: rename with a pen, wire, install electronics, or plate the assembly.
/datum/interaction/entry_item/door_assembly_item
	id = "door_assembly_item"
	name = "Use"
	effect = /obj/structure/door_assembly/proc/interaction_item

/obj/structure/door_assembly/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/pen))
		rename_door(user)
		return TRUE

	if(istype(W, /obj/item/stack/cable_coil) && state == 0 && anchored)
		var/obj/item/stack/cable_coil/C = W
		if (C.get_amount() < 1)
			to_chat(user, span_warning("You need one length of coil to wire the airlock assembly."))
			return TRUE
		user.visible_message("[user] wires the airlock assembly.", "You start to wire the airlock assembly.")
		om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, C))

	else if(istype(W, /obj/item/airlock_electronics) && state == 1)
		playsound(src, W.usesound, 100, 1)
		user.visible_message("[user] installs the electronics into the airlock assembly.", "You start to install electronics into the airlock assembly.")

		om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done2), done_args = list(W, user))

	else if(istype(W, /obj/item/stack/material) && !glass)
		var/obj/item/stack/S = W
		var/material_name = S.get_material_name()
		if (S)
			if (S.get_amount() >= 1)
				if(material_name == MAT_RGLASS)
					play_sfx(src, SFX_ITEMS_CROWBAR, 2)
					user.visible_message("[user] adds [S.name] to the airlock assembly.", "You start to install [S.name] into the airlock assembly.")
					om_task_timed(user, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done3), done_args = list(user, S))
				else if(material_name)
					// Ugly hack, will suffice for now. Need to fix it upstream as well, may rewrite mineral walls. ~Z
					if(!(material_name in list(MAT_GOLD, MAT_SILVER, MAT_DIAMOND, MAT_URANIUM, MAT_PHORON, MAT_SANDSTONE)))
						to_chat(user, "You cannot make an airlock out of that material.")
						return TRUE
					if(S.get_amount() >= 2)
						play_sfx(src, SFX_ITEMS_CROWBAR, 2)
						user.visible_message("[user] adds [S.name] to the airlock assembly.", "You start to install [S.name] into the airlock assembly.")
						om_task_start(/datum/om/task/timed/door_assembly_attackby, user, src, S = S, material_name = material_name)

	update_state()
	return TRUE

/obj/structure/door_assembly/proc/attackby_timed_done(mob/user, obj/item/stack/cable_coil/C)
	if(!(state == 0 && anchored))
		return
	if (C.use(1))
		src.state = 1
		to_chat(user, span_notice("You wire the airlock."))
/obj/structure/door_assembly/proc/attackby_timed_done2(obj/item/W, mob/user)
	if(!src) return
	user.drop_item()
	W.forceMove(src)
	to_chat(user, span_notice("You installed the airlock electronics!"))
	src.state = 2
	src.electronics = W
/obj/structure/door_assembly/proc/attackby_timed_done3(mob/user, obj/item/stack/S)
	if(!(!glass))
		return
	if (S.use(1))
		to_chat(user, span_notice("You installed reinforced glass windows into the airlock assembly."))
		glass = 1
/datum/om/task/timed/door_assembly_attackby
	duration = 4 SECONDS
	complete_proc = /obj/structure/door_assembly/proc/attackby_timed_done4
	var/obj/item/stack/S
	var/material_name

/obj/structure/door_assembly/proc/attackby_timed_done4(datum/om/task/timed/door_assembly_attackby/task)
	var/mob/user = task.actor
	var/obj/item/stack/S = task.S
	var/material_name = task.material_name
	if(!(!glass))
		return
	if (S.use(2))
		to_chat(user, span_notice("You installed [material_display_name(material_name)] plating into the airlock assembly."))
		glass = material_name

/obj/structure/door_assembly/welder_act(mob/user, obj/item/W)
	if(!(istext(glass) || glass == 1 || !anchored))
		update_state()
		return NONE
	if(istext(glass))
		use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld the [glass] plating off the airlock assembly.", message_others = "[user] welds the [glass] plating off the airlock assembly.", receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	else if(glass == 1)
		use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to weld the glass panel out of the airlock assembly.", message_others = "[user] welds the glass panel out of the airlock assembly.", receiver = src, on_done = PROC_REF(welder_act_tool_done2), done_args = list(user))
	else if(!anchored)
		use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WELDER, volume = 50, message_self = "You start to dissassemble the airlock assembly.", message_others = "[user] dissassembles the airlock assembly.", receiver = src, on_done = PROC_REF(welder_act_tool_done3), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/door_assembly/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You welded the [glass] plating off!"))
	var/M = text2path("/obj/item/stack/material/[glass]")
	new M(src.loc, 2)
	glass = 0
/obj/structure/door_assembly/proc/welder_act_tool_done2(mob/user)
	to_chat(user, span_notice("You welded the glass panel out!"))
	new /obj/item/stack/material/glass/reinforced(src.loc)
	glass = 0
/obj/structure/door_assembly/proc/welder_act_tool_done3(mob/user)
	to_chat(user, span_notice("You dissasembled the airlock assembly!"))
	replace_with(src, /obj/item/stack/material/steel, 4)

/obj/structure/door_assembly/wrench_act(mob/user, obj/item/W)
	if(state != 0)
		update_state()
		return NONE
	var/was_anchored = anchored
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 100, message_self = "You starts [was_anchored ? "un" : ""]securing the airlock assembly [was_anchored ? "from" : "to"] the floor.", message_others = "[user] begins [was_anchored ? "un" : ""]securing the airlock assembly [was_anchored ? "from" : "to"] the floor.", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user, was_anchored))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/door_assembly/proc/wrench_act_tool_done(mob/user, was_anchored)
	to_chat(user, span_notice("You [was_anchored ? "un" : ""]secured the airlock assembly!"))
	anchored = !anchored

/obj/structure/door_assembly/wirecutter_act(mob/user, obj/item/W)
	if(state != 1)
		update_state()
		return NONE
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_WIRECUTTER, volume = 100, message_self = "You start to cut the wires from airlock assembly.", message_others = "[user] cuts the wires from the airlock assembly.", receiver = src, on_done = PROC_REF(wirecutter_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/door_assembly/proc/wirecutter_act_tool_done(mob/user)
	to_chat(user, span_notice("You cut the airlock wires.!"))
	new/obj/item/stack/cable_coil(src.loc, 1)
	src.state = 0

/obj/structure/door_assembly/crowbar_act(mob/user, obj/item/W)
	if(state != 2)
		update_state()
		return NONE
	if(!electronics)
		to_chat(user, span_notice("There was nothing to remove."))
		src.state = 1
		update_state()
		return ITEM_INTERACT_SUCCESS

	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_CROWBAR, volume = 100, message_self = "You start removing the electronics from the airlock assembly.", message_others = "\The [user] starts removing the electronics from the airlock assembly.", receiver = src, on_done = PROC_REF(crowbar_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/door_assembly/proc/crowbar_act_tool_done(mob/user)
	to_chat(user, span_notice("You removed the airlock electronics!"))
	src.state = 1
	electronics.forceMove(src.loc)
	electronics = null

/obj/structure/door_assembly/screwdriver_act(mob/user, obj/item/W)
	if(state != 2)
		update_state()
		return NONE
	to_chat(user, span_notice("Now finishing the airlock."))
	use_tool(user, W, src, delay = 4 SECONDS, quality = TOOL_SCREWDRIVER, volume = 100, receiver = src, on_done = PROC_REF(screwdriver_act_tool_done), done_args = list(user))
	update_state()
	return ITEM_INTERACT_SUCCESS

/obj/structure/door_assembly/proc/screwdriver_act_tool_done(mob/user)
	to_chat(user, span_notice("You finish the airlock!"))
	var/path
	if(istext(glass))
		path = text2path("/obj/machinery/door/airlock/[glass]")
	else if (glass == 1)
		path = text2path("/obj/machinery/door/airlock[glass_type]")
	else
		path = text2path("/obj/machinery/door/airlock[airlock_type]")

	replace_with(src, path, src)

/obj/structure/door_assembly/proc/update_state()
	icon_state = "door_as_[glass == 1 ? "g" : ""][istext(glass) ? glass : base_icon_state][state]"
	name = ""
	switch (state)
		if(0)
			if (anchored)
				name = "secured "
		if(1)
			name = "wired "
		if(2)
			name = "near finished "
	name += "[glass == 1 ? "window " : ""][istext(glass) ? "[glass] airlock" : base_name] assembly ([created_name])"

// Airlock frames are indestructable, so bullets hitting them would always be stopped.
// To fix this, airlock assemblies will sometimes let bullets pass through, since generally the sprite shows them partially open.
/obj/structure/door_assembly/bullet_act(obj/item/projectile/P)
	if(prob(40)) // Chance for the frame to let the bullet keep going.
		return PROJECTILE_CONTINUE
	return ..()

DECLARE_REF(/obj/structure/door_assembly, "electronics", HELD, null)
