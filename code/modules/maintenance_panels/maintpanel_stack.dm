// Maintenance panel sheets
/obj/item/stack/tile/maintenance_panel
	name = "maintenance panel"
	desc = "A maintenance panel"
	singular_name = "panel"
	icon_state = "maintpanel"
	force = 6.0
	MATERIAL_BULK(DEFAULT_WALL_MATERIAL, SHEET_MATERIAL_AMOUNT / 4)
	throwforce = 15.0
	throw_speed = 5
	throw_range = 20
	can_weld = TRUE
	no_variants = FALSE

MSG_DEF_SELF(maintenance_panel/clumsy, "this task is too complex for your clumsy hands")

CAPABILITIES(/obj/item/stack/tile/maintenance_panel)
	without("ui_open")
	op("maintenance_panel_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Build panel"), needs(req(PROC_REF(actor_dexterous_holds), because = MSG(maintenance_panel/clumsy))), then(PROC_REF(maintenance_panel_self)))

/// Requirement: the actor can use tools.
/obj/item/stack/tile/maintenance_panel/proc/actor_dexterous_holds(datum/act/op/A)
	return !!A.actor.IsAdvancedToolUser()

/// Old attack_self: build a panel.
/obj/item/stack/tile/maintenance_panel/proc/maintenance_panel_self(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = user.loc
	if(!user || user.stat || user.loc != T)
		return OP_DECLINE

	// Get data for building windows here.
	var/list/possible_directions = GLOB.cardinal.Copy()
	var/window_count = 0
	for (var/obj/structure/window/check_window in user.loc)
		window_count++
		possible_directions  -= check_window.dir
	for (var/obj/structure/windoor_assembly/check_assembly in user.loc)
		window_count++
		possible_directions -= check_assembly.dir
	for (var/obj/machinery/door/window/check_windoor in user.loc)
		window_count++
		possible_directions -= check_windoor.dir

	// Get the closest available dir to the user's current facing.
	var/build_dir = SOUTHWEST //Default to southwest for fulltile windows.
	var/failed_to_build
	if(window_count >= 4)
		failed_to_build = 1
	else
		if(possible_directions.len)
			for(var/direction in list(user.dir, turn(user.dir,90), turn(user.dir,270), turn(user.dir,180)))
				if(direction in possible_directions)
					build_dir = direction
					break
		else
			failed_to_build = 1
	if(failed_to_build)
		to_chat(user, span_warning("There is no room in this location."))
		return OP_OK

	var/sheets_needed = 1
	if(get_amount() < sheets_needed)
		to_chat(user, span_warning("You need at least [sheets_needed] sheets to build this."))
		return OP_OK
	if(build_dir == SOUTHWEST)
		to_chat(user, span_warning("A maintenance panel cannot be built like that!"))
		return OP_OK

	// Build the structure and update sheet count etc.
	use(sheets_needed)
	new /obj/structure/window/maintenance_panel(T, build_dir, 1)
	return OP_OK

// Spawner
/obj/fiftyspawner/maintenance_panel
	name = "stack of maintenance panels"
	type_to_spawn = /obj/item/stack/tile/maintenance_panel
