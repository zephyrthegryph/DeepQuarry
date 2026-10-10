/obj/structure/door_assembly
	name = "airlock assembly"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_as_0"
	anchored = FALSE
	density = TRUE
	w_class = ITEMSIZE_HUGE
	var/base_icon_state = ""
	var/base_name = "airlock"
	var/obj/item/airlock_electronics/electronics = null
	var/airlock_type = "" //the type path of the airlock once completed
	var/glass_type = "/glass"
	var/glass = 0 // 0 = glass can be installed. -1 = glass can't be installed. 1 = glass is already installed. Text = mineral plating is installed instead.
	var/created_name = null

/obj/structure/door_assembly/proc/init_update_state(datum/act/timer/A)
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

TRACKED(/obj/structure/door_assembly, glass)

// ---- what an airlock assembly is, declared ----
//
// The build ladder is a state graph: a loose frame, bolted down (a wrench), wired (a length of cable), with its electronics in, finished (a screwdriver:
// the airlock the assembly stands for takes its place). Plating and windows are the assembly's own ops beside the ladder: reinforced glass makes a
// window, a few minerals plate it, a welder takes either back off or, from a loose bare frame, takes the whole assembly down into steel. The name
// and picture of the assembly follow its stage and what is fitted (update_state()).

STAGE_DEF(door_assembly, frame)
STAGE_DEF(door_assembly, secured)
STAGE_DEF(door_assembly, wired)
STAGE_DEF(door_assembly, boarded)
STAGE_DEF(door_assembly, finished)

MSG_DEF_SELF(stage/door_assembly/frame, "It is a bare frame.")
MSG_DEF_SELF(stage/door_assembly/secured, "It is bolted to the floor.")
MSG_DEF_SELF(stage/door_assembly/wired, "It is wired.")
MSG_DEF_SELF(stage/door_assembly/boarded, "Its electronics are in.")
MSG_DEF_SELF(stage/door_assembly/finished, "It is finished.")

MSG_DEF_SELF(door_assembly/bad_plating, "You cannot make an airlock out of that material.")
MSG_DEF_SELF(door_assembly/more_sheets, "You need more sheets than that.")
MSG_DEF_SELF(door_assembly/bolted_down, "Unbolt it from the floor first.")
MSG_DEF_SELF(door_assembly/plated, "Take the plating off first.")

CAPABILITIES(/obj/structure/door_assembly)
	after_init(0, then(PROC_REF(init_update_state)))
	construction(start(STAGE_DOOR_ASSEMBLY_FRAME),
		stage(STAGE_DOOR_ASSEMBLY_SECURED, tool(TOOL_WRENCH), wait(4 SECONDS), then(PROC_REF(secured_down)), undone(PROC_REF(unsecured)), undo = list(tool(TOOL_WRENCH), wait(4 SECONDS))),
		stage(STAGE_DOOR_ASSEMBLY_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), then(PROC_REF(wired_up)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(4 SECONDS))),
		stage(STAGE_DOOR_ASSEMBLY_BOARDED, item(/obj/item/airlock_electronics), wait(4 SECONDS), then(PROC_REF(board_seated)), undone(PROC_REF(board_taken)), undo = list(tool(TOOL_CROWBAR), wait(4 SECONDS))),
		stage(STAGE_DOOR_ASSEMBLY_FINISHED, tool(TOOL_SCREWDRIVER), wait(4 SECONDS), then(PROC_REF(finish_airlock)), undo = NO_UNDO),
		dismantle(tool(TOOL_WELDER), wait(4 SECONDS), then(PROC_REF(disassembled))))
	owns_one(nameof(electronics), /obj/item/airlock_electronics)
	op("rename", item(/obj/item/pen), label("Rename"), wait(0), asks(/datum/prompt/text, fields = list("question" = "Enter the name for the airlock.")), then(PROC_REF(renamed)))
	op("rename_robot", hand(), label("Rename"), when(req(PROC_REF(robot_may_rename))), wait(0), asks(/datum/prompt/text, fields = list("question" = "Enter the name for the airlock.")), then(PROC_REF(renamed)))
	op("plate_glass", stack(/obj/item/stack/material/glass/reinforced, 1), label("Install windows"), when(PROC_REF(unplated)), wait(4 SECONDS), then(PROC_REF(glass_in)))
	op("plate", inputs(stack(/obj/item/stack/material/gold, 2), stack(/obj/item/stack/material/silver, 2), stack(/obj/item/stack/material/diamond, 2), stack(/obj/item/stack/material/uranium, 2), stack(/obj/item/stack/material/phoron, 2), stack(/obj/item/stack/material/sandstone, 2)), label("Install plating"), when(PROC_REF(unplated)), wait(4 SECONDS), then(PROC_REF(plated_in)))
	op("plate_bad", item(/obj/item/stack/material), label("Install plating"), when(PROC_REF(unplated)), when(cond_not(req(/obj/item/stack/material/glass/reinforced))), when(cond_not(req(/obj/item/stack/material/gold))), when(cond_not(req(/obj/item/stack/material/silver))), when(cond_not(req(/obj/item/stack/material/diamond))), when(cond_not(req(/obj/item/stack/material/uranium))), when(cond_not(req(/obj/item/stack/material/phoron))), when(cond_not(req(/obj/item/stack/material/sandstone))), priority(OP_PRIORITY_NORMAL), wait(0), then(PROC_REF(plating_refused)))
	op("unplate", tool(TOOL_WELDER), label("Take the plating off"), when(PROC_REF(plated)), priority(above("construction.dismantle")), wait(4 SECONDS), then(PROC_REF(plating_off)))
	extend("construction.dismantle", needs(req_not(req_built(STAGE_DOOR_ASSEMBLY_SECURED, because = MSG(door_assembly/bolted_down)), because = MSG(door_assembly/bolted_down))))

/// Neither windows nor plating are fitted, and the type takes them (glass is -1 for the ones that do not).
/obj/structure/door_assembly/proc/unplated(datum/act/A)
	return !glass

/// Windows or plating are fitted.
/obj/structure/door_assembly/proc/plated(datum/act/A)
	return istext(glass) || glass == 1

/// A material that is no plating: the assembly says so and keeps the sheets.
/obj/structure/door_assembly/proc/plating_refused(datum/act/op/A)
	to_chat(A.actor, span_warning("You cannot make an airlock out of that material."))
	return OP_OK

/obj/structure/door_assembly/proc/renamed(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/new_name = sanitizeSafe(R?.value, MAX_NAME_LEN)
	if(!isnull(R?.value))
		created_name = new_name
		update_state()
	return OP_OK

/// Drones and engineering borgs next to it rename it.
/obj/structure/door_assembly/proc/robot_may_rename(datum/act/op/A)
	var/mob/living/silicon/robot/user = A.actor
	return (istype(user) && user.module?.names_assemblies) ? null : MSG(req_failed)

/obj/structure/door_assembly/proc/secured_down(datum/act/op/A)
	to_chat(A.actor, span_notice("You secured the airlock assembly!"))
	set_anchored(TRUE)
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/unsecured(datum/act/op/A)
	to_chat(A.actor, span_notice("You unsecured the airlock assembly!"))
	set_anchored(FALSE)
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/wired_up(datum/act/op/A)
	to_chat(A.actor, span_notice("You wire the airlock."))
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/unwired(datum/act/op/A)
	to_chat(A.actor, span_notice("You cut the airlock wires.!"))
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/board_seated(datum/act/op/A)
	var/obj/item/W = A.held
	to_chat(A.actor, span_notice("You installed the airlock electronics!"))
	playsound(src, W.usesound, 100, 1)
	move_into(src, nameof(electronics), W, A.actor)
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/board_taken(datum/act/op/A)
	to_chat(A.actor, span_notice("You removed the airlock electronics!"))
	if(electronics)
		electronics.forceMove(loc)
		rel_take(src, nameof(electronics))
	update_state()
	return OP_OK

/// The finished airlock takes the assembly's place.
/obj/structure/door_assembly/proc/finish_airlock(datum/act/op/A)
	to_chat(A.actor, span_notice("You finish the airlock!"))
	var/path
	if(istext(glass))
		path = text2path("/obj/machinery/door/airlock/[glass]")
	else if (glass == 1)
		path = text2path("/obj/machinery/door/airlock[glass_type]")
	else
		path = text2path("/obj/machinery/door/airlock[airlock_type]")
	replace_with(src, path, src)
	return OP_OK

/// A loose bare frame comes apart into its steel.
/obj/structure/door_assembly/proc/disassembled(datum/act/op/A)
	to_chat(A.actor, span_notice("You dissasembled the airlock assembly!"))
	replace_with(src, /obj/item/stack/material/steel, 4)
	return OP_OK

/obj/structure/door_assembly/proc/glass_in(datum/act/op/A)
	if(glass)
		return OP_REFUSED
	to_chat(A.actor, span_notice("You installed reinforced glass windows into the airlock assembly."))
	set_glass(1)
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/plated_in(datum/act/op/A)
	var/obj/item/stack/material/S = A.held
	if(glass || !istype(S))
		return OP_REFUSED
	var/material_name = S.get_material_name()
	to_chat(A.actor, span_notice("You installed [material_display_name(material_name)] plating into the airlock assembly."))
	set_glass(material_name)
	update_state()
	return OP_OK

/obj/structure/door_assembly/proc/plating_off(datum/act/op/A)
	var/mob/user = A.actor
	if(istext(glass))
		to_chat(user, span_notice("You welded the [glass] plating off!"))
		var/M = text2path("/obj/item/stack/material/[glass]")
		new M(loc, 2)
	else
		to_chat(user, span_notice("You welded the glass panel out!"))
		new /obj/item/stack/material/glass/reinforced(loc)
	set_glass(0)
	update_state()
	return OP_OK

/// How far the assembly is built, as the number its picture and name are made from: 0 bare (bolted down or not), 1 wired, 2 with its electronics in.
/obj/structure/door_assembly/proc/assembly_state()
	if(built(src, STAGE_DOOR_ASSEMBLY_BOARDED))
		return 2
	if(built(src, STAGE_DOOR_ASSEMBLY_WIRED))
		return 1
	return 0

/obj/structure/door_assembly/proc/update_state()
	var/state = assembly_state()
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
