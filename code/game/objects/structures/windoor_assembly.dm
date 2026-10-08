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

	var/obj/item/airlock_electronics/electronics = null // may hold an /obj/item/circuitboard/broken (see board_whole)
	var/created_name = null

	//Vars to help with the icon's name
	var/facing = "l"	//Does the windoor open to the left or right?
	var/secure = ""		//Whether or not this creates a secure windoor

/obj/structure/windoor_assembly/secure
	name = "secure windoor assembly"
	secure = "secure_"
	icon_state = "l_secure_windoor_assembly01"

/// The facing and whether a player built it (its constructor params).
/obj/structure/windoor_assembly/var/start_dir = NORTH
/obj/structure/windoor_assembly/var/constructed = FALSE

// ALLOW(init/INSTANCE_STATE): an assembly faces a cardinal way, starts loose when built, and updates its tiles
/obj/structure/windoor_assembly/Initialize(mapload)
	. = ..()
	if(constructed)
		set_anchored(FALSE)
	switch(start_dir)
		if(NORTH, SOUTH, EAST, WEST)
			set_dir(start_dir)
		else //If the user is facing northeast. northwest, southeast, southwest or north, default to north
			set_dir(NORTH)
	update_state()

	update_nearby_tiles(need_rebuild=1)
	make_rotatable()


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

// ---- what a windoor assembly is, declared ----
//
// The build ladder is a state graph: a loose frame, bolted to the floor (a wrench), wired (a length of cable), with its electronics in, finished (a
// crowbar pries the windoor into the frame: the real door takes its place, open for a moment and then closing). A screwdriver takes the electronics
// out, wirecutters the wiring, a wrench frees it again; a welder takes a loose frame apart into its glass. A pen names it, and any of its steps shows
// in its name and picture (update_state()).

STAGE_DEF(windoor_assembly, frame)
STAGE_DEF(windoor_assembly, secured)
STAGE_DEF(windoor_assembly, wired)
STAGE_DEF(windoor_assembly, boarded)
STAGE_DEF(windoor_assembly, finished)

MSG_DEF_SELF(stage/windoor_assembly/frame, "It is a bare frame.")
MSG_DEF_SELF(stage/windoor_assembly/secured, "It is bolted to the floor.")
MSG_DEF_SELF(stage/windoor_assembly/wired, "It is wired.")
MSG_DEF_SELF(stage/windoor_assembly/boarded, "Its electronics are in.")
MSG_DEF_SELF(stage/windoor_assembly/finished, "It is finished.")

MSG_DEF_SELF(windoor_assembly/bolted_down, "Unbolt it from the floor first.")
MSG_DEF_SELF(windoor_assembly/broken_board, "The assembly has broken airlock electronics.")

CAPABILITIES(/obj/structure/windoor_assembly)
	construction(start(STAGE_WINDOOR_ASSEMBLY_FRAME),
		stage(STAGE_WINDOOR_ASSEMBLY_SECURED, tool(TOOL_WRENCH), wait(4 SECONDS), then(PROC_REF(secured_down)), undone(PROC_REF(unsecured)), undo = list(tool(TOOL_WRENCH), wait(4 SECONDS))),
		stage(STAGE_WINDOOR_ASSEMBLY_WIRED, stack(/obj/item/stack/cable_coil, 1), wait(4 SECONDS), then(PROC_REF(wired_up)), undone(PROC_REF(unwired)), undo = list(tool(TOOL_WIRECUTTER), wait(4 SECONDS))),
		stage(STAGE_WINDOOR_ASSEMBLY_BOARDED, item(/obj/item/airlock_electronics), wait(4 SECONDS), then(PROC_REF(board_seated)), undone(PROC_REF(board_taken)), undo = list(tool(TOOL_SCREWDRIVER), wait(4 SECONDS))),
		stage(STAGE_WINDOOR_ASSEMBLY_FINISHED, tool(TOOL_CROWBAR), wait(4 SECONDS), needs(req(PROC_REF(board_whole), because = MSG(windoor_assembly/broken_board))), then(PROC_REF(finish_windoor)), undo = null),
		dismantle(tool(TOOL_WELDER), wait(4 SECONDS), then(PROC_REF(disassembled))))
	owns_one(nameof(electronics), /obj/item)
	op("rename", item(/obj/item/pen), label("Rename"), wait(0), asks(/datum/prompt/text, fields = list("question" = "Enter the name for the windoor.")), then(PROC_REF(renamed)))
	op("rename_robot", hand(), label("Rename"), when(req(PROC_REF(robot_may_rename))), wait(0), asks(/datum/prompt/text, fields = list("question" = "Enter the name for the windoor.")), then(PROC_REF(renamed)))
	op("flip", menu(), label("Flip Windoor Assembly"), wait(0), then(PROC_REF(flipped)))
	extend("construction.dismantle", needs(req_not(req_built(STAGE_WINDOOR_ASSEMBLY_SECURED, because = MSG(windoor_assembly/bolted_down)), because = MSG(windoor_assembly/bolted_down))))
	param(nameof(start_dir), pos = 1)
	param(nameof(constructed), pos = 2)

/obj/structure/windoor_assembly/proc/renamed(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!isnull(R?.value))
		created_name = sanitizeSafe(R.value, MAX_NAME_LEN)
		update_state()
	return OP_OK

/// Drones and engineering borgs next to it rename it.
/obj/structure/windoor_assembly/proc/robot_may_rename(datum/act/op/A)
	var/mob/living/silicon/robot/user = A.actor
	return istype(user) && user.module?.names_assemblies

/obj/structure/windoor_assembly/proc/secured_down(datum/act/op/A)
	to_chat(A.actor, span_notice("You've secured the windoor assembly!"))
	set_anchored(TRUE)
	update_state()
	return OP_OK

/obj/structure/windoor_assembly/proc/unsecured(datum/act/op/A)
	to_chat(A.actor, span_notice("You've unsecured the windoor assembly!"))
	set_anchored(FALSE)
	update_state()
	return OP_OK

/obj/structure/windoor_assembly/proc/wired_up(datum/act/op/A)
	to_chat(A.actor, span_notice("You wire the windoor!"))
	update_state()
	return OP_OK

/obj/structure/windoor_assembly/proc/unwired(datum/act/op/A)
	to_chat(A.actor, span_notice("You cut the windoor wires.!"))
	new /obj/item/stack/cable_coil(get_turf(A.actor), 1)
	update_state()
	return OP_OK

/obj/structure/windoor_assembly/proc/board_seated(datum/act/op/A)
	to_chat(A.actor, span_notice("You've installed the airlock electronics!"))
	move_into(src, nameof(electronics), A.held, A.actor)
	update_state()
	return OP_OK

/obj/structure/windoor_assembly/proc/board_taken(datum/act/op/A)
	to_chat(A.actor, span_notice("You've removed the airlock electronics!"))
	if(electronics)
		var/obj/item/airlock_electronics/ae = electronics
		rel_take(src, nameof(electronics))
		ae.forceMove(loc)
	update_state()
	return OP_OK

/// The electronics in it are not a burnt out board.
/obj/structure/windoor_assembly/proc/board_whole(datum/act/A)
	return !istype(electronics, /obj/item/circuitboard/broken)

/// A loose bare frame comes apart into its glass.
/obj/structure/windoor_assembly/proc/disassembled(datum/act/op/A)
	to_chat(A.actor, span_notice("You disassembled the windoor assembly!"))
	if(secure)
		new /obj/item/stack/material/glass/reinforced(get_turf(src), 2)
	else
		new /obj/item/stack/material/glass(get_turf(src), 2)
	consume(src, A.actor)
	return OP_OK

/// The crowbar pries the windoor into the frame: the door takes the assembly's place, open, and closes at once.
/obj/structure/windoor_assembly/proc/finish_windoor(datum/act/op/A)
	to_chat(A.actor, span_notice("You finish the windoor!"))
	SStgui.close_uis(src)
	set_density(TRUE) //Shouldn't matter but just incase
	var/obj/machinery/door/window/windoor = secure ? new /obj/machinery/door/window/brigdoor(loc) : new /obj/machinery/door/window(loc)
	var/side = facing == "l" ? "left" : "right"
	var/open_state = secure ? "[side]secure" : side
	windoor.icon_state = "[open_state]open"
	windoor.base_state = open_state
	windoor.set_dir(dir)
	windoor.set_density(FALSE)
	if(created_name)
		windoor.name = created_name
	after(windoor, 0, TYPE_PROC_REF(/obj/machinery/door, close), key = "autoclose", clock = CLOCK_WORLD)
	if(electronics.one_access)
		windoor.req_access = null
		windoor.req_one_access = electronics.conf_access
	else
		windoor.req_access = electronics.conf_access
	electronics.forceMove(windoor)
	rel_move(src, nameof(electronics), windoor, nameof(windoor.electronics))
	replace_with(src, windoor)
	return OP_OK

/// How far the assembly is built, as the number its picture is made from: 01 loose or bolted down, 02 wired or beyond.
/obj/structure/windoor_assembly/proc/sprite_state()
	return (built(src, STAGE_WINDOOR_ASSEMBLY_WIRED) || built(src, STAGE_WINDOOR_ASSEMBLY_BOARDED)) ? "02" : "01"

/// The name follows the step: anchored, wired, near finished.
/obj/structure/windoor_assembly/proc/update_state()
	update_icon()
	name = ""
	if(built(src, STAGE_WINDOOR_ASSEMBLY_BOARDED))
		name = "near finished "
	else if(built(src, STAGE_WINDOOR_ASSEMBLY_WIRED))
		name = "wired "
	else if(built(src, STAGE_WINDOOR_ASSEMBLY_SECURED))
		name = "anchored "
	name += "[secure ? "secure " : ""]windoor assembly[created_name ? " ([created_name])" : ""]"

// The assembly's own template does not apply: draw() below is the look, and update_icon() marks it for it.
APPEARANCE_NONE(/obj/structure/windoor_assembly)

// ALLOW(sys_update_icon): bridge only; it draws nothing, it marks the assembly so draw() runs
/obj/structure/windoor_assembly/update_icon()
	changed(src)

/obj/structure/windoor_assembly/draw(datum/look/look)
	..()
	look.state("[facing]_[secure]windoor_assembly[sprite_state()]")

/obj/structure/windoor_assembly/handle_rotation_verbs(angle, mob/user)
	var/wired = sprite_state() == "02"
	if(wired)
		update_nearby_tiles(need_rebuild=1) //Compel updates before
	. = ..()
	if(.)
		if(wired)
			update_nearby_tiles(need_rebuild=1)
		update_icon()

/// Flips the windoor assembly: whether the door opens to the left or the right.
/obj/structure/windoor_assembly/proc/flipped(datum/act/op/A)
	if(facing == "l")
		to_chat(A.actor, "The windoor will now slide to the right.")
		facing = "r"
	else
		facing = "l"
		to_chat(A.actor, "The windoor will now slide to the left.")
	update_icon()
	return OP_OK
