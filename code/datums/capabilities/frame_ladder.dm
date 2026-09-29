/**
 * The standard machine frame ladder and the deconstruct capability (doc/rewrite/dx_conventions.md §2).
 *
 * A board-built machine carries cap_deconstruct(board): with its maintenance panel open, a crowbar
 * takes it apart into a frame holding its board, and the frame's standard ladder builds it back:
 *
 *	/obj/structure/frame/capabilities()
 *		. = ..()
 *		. += cap_frame_ladder()
 *
 * Which of the frame's steps are offered depends on its frame class (machine, computer, display,
 * alarm) and on whether it came with its board (then it has an outer cover instead of a board to
 * insert). Putting stock parts into a machine frame stays with the frame's item interaction until
 * machine internals become data (C6).
 */

// ---- The deconstruct capability ----

/// Taking a board-built machine apart into its frame, board and parts.
/datum/capability/deconstruct
	/// The circuit board type the machine is built from (what its frame's ladder takes back).
	var/board
	/// The dismantle entry, built once.
	var/tmp/datum/interaction/capability/dismantle

/**
 * cap_deconstruct(board = /obj/item/circuitboard/x): with the panel open (`behind`), a crowbar
 * dismantles the machine into its frame. Works broken and unpowered.
 */
/proc/cap_deconstruct(board, behind = PANEL, locked_by = NONE, needs, else_say, log = LOG_GAME)
	var/datum/capability/deconstruct/made = new
	made.board = board
	made.behind = behind
	made.locked_by = locked_by
	made.needs = needs
	made.else_say = else_say
	made.log = log
	made.works_broken = TRUE
	made.works_unpowered = TRUE
	return made

/datum/capability/deconstruct/interactions(atom/holder)
	if(!dismantle)
		var/datum/interaction/capability/entry = new
		entry.name = "Dismantle"
		entry.id = "deconstruct:[board]"
		entry.handler = TYPE_PROC_REF(/obj/machinery, cap_dismantle)
		entry.tool = TOOL_CROWBAR
		entry.category = INTERACTION_CAT_MAINTAIN
		entry.default_action = INPUT_ACTION_USE
		entry.behind = behind
		entry.locked_by = locked_by
		entry.needs = needs
		entry.else_say = else_say
		entry.works_broken = TRUE
		entry.works_unpowered = TRUE
		entry.log = log
		entry.cap = src
		entry.apply_stance_tags()
		dismantle = entry
	return list(dismantle)

/datum/capability/deconstruct/examine(atom/holder, mob/user)
	if(behind && (behind & ~holder.cap_state))
		return null
	return list(span_notice("It could be pried apart into its frame with a crowbar."))

/// The dismantle entry's handler: the machine comes apart into its frame, board and parts.
/obj/machinery/proc/cap_dismantle(mob/user, obj/item/held)
	return dismantle()


// ---- The standard frame ladder ----

/**
 * The frame's ladder. Its stage is the frame's `state` (FRAME_*), plus "loose" for a placed frame
 * that isn't wrenched down; frame_ladder_stage() names them.
 */
/proc/cap_frame_ladder()
	return cap_construction(
		ladder_options(state = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_stage), store = TYPE_PROC_REF(/obj/structure/frame, set_frame_ladder_stage), starts = list("placed")),
		stage("loose",
			also = list(
				branch("board fastened", with_tool(TOOL_WRENCH, 2 SECONDS), say = "wrench %T% into place and set its cover",
					when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_fitted_board), on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_cover_set)),
				branch(LADDER_DONE, with_tool(TOOL_WELDER, 2 SECONDS), say = "cut %T% apart", on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_cut_apart)))),
		stage("placed", build = with_tool(TOOL_WRENCH, 2 SECONDS), undo = with_tool(TOOL_WRENCH, 2 SECONDS), anchored = TRUE,
			when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_no_fitted_board),
			also = list(branch(LADDER_DONE, with_tool(TOOL_WELDER, 2 SECONDS), say = "cut %T% apart", on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_cut_apart)))),
		stage("board in", build = inserting(/obj/item/circuitboard, sfx = SFX_ITEMS_DECONSTRUCT), undo = with_tool(TOOL_CROWBAR), undo_say = "pry the circuit board out of %T%",
			when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_wants_board), undo_when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_own_board),
			needs = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_board_fits),
			on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_board_in), on_leave = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_board_out)),
		stage("board fastened", build = with_tool(TOOL_SCREWDRIVER), undo = with_tool(TOOL_SCREWDRIVER), say = "screw the circuit board into %T%", undo_say = "unscrew the circuit board in %T%",
			undo_when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_own_board),
			also = list(branch("placed", with_tool(TOOL_SCREWDRIVER), say = "unfasten %T%'s outer cover", when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_fitted_board)))),
		stage("wired", build = using(/obj/item/stack/cable_coil, amount = 5, delay = 2 SECONDS, sfx = SFX_ITEMS_DECONSTRUCT), undo = with_tool(TOOL_WIRECUTTER),
			on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_wired), on_leave = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_unwired),
			also = list(
				branch("wired", with_tool(TOOL_CROWBAR), say = "pry the components out of %T%", when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_is_machine),
					on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_components_out)),
				branch(LADDER_DONE, with_tool(TOOL_SCREWDRIVER), say = "finish %T%", when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_is_machine), priority = 11,
					needs = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_has_components), else_say = "it is missing components",
					on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_finish_machine)),
				branch(LADDER_DONE, with_tool(TOOL_SCREWDRIVER), say = "fasten %T%'s cover", when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_is_alarm),
					on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_finish_alarm)))),
		stage("paneled", build = using(/obj/item/stack/material/glass, amount = 2, delay = 2 SECONDS, match = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_plain_glass), name = "glass sheets", sfx = SFX_ITEMS_DECONSTRUCT),
			undo = with_tool(TOOL_CROWBAR), undo_say = "pry the glass panel out of %T%",
			when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_has_screen), undo_when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_has_screen),
			also = list(branch(LADDER_DONE, with_tool(TOOL_SCREWDRIVER), say = "connect %T%'s monitor", when = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_has_screen),
				on_enter = TYPE_PROC_REF(/obj/structure/frame, frame_ladder_finish_screen)))),
	)

/// The frame's stage name, from its FRAME_* `state` and whether it is wrenched down.
/obj/structure/frame/proc/frame_ladder_stage()
	switch(state)
		if(FRAME_PLACED)
			return anchored ? "placed" : "loose"
		if(FRAME_UNFASTENED)
			return "board in"
		if(FRAME_FASTENED)
			return "board fastened"
		if(FRAME_WIRED)
			return "wired"
		if(FRAME_PANELED)
			return "paneled"
	return null

/obj/structure/frame/proc/set_frame_ladder_stage(stage_name)
	switch(stage_name)
		if("loose", "placed")
			state = FRAME_PLACED
		if("board in")
			state = FRAME_UNFASTENED
		if("board fastened")
			state = FRAME_FASTENED
		if("wired")
			state = FRAME_WIRED
		if("paneled")
			state = FRAME_PANELED

/obj/structure/frame/proc/frame_ladder_is_machine()
	return frame_type.frame_class == FRAME_CLASS_MACHINE

/obj/structure/frame/proc/frame_ladder_is_alarm()
	return frame_type.frame_class == FRAME_CLASS_ALARM

/obj/structure/frame/proc/frame_ladder_has_screen()
	return frame_type.frame_class == FRAME_CLASS_COMPUTER || frame_type.frame_class == FRAME_CLASS_DISPLAY

/// Needs a board and has none yet.
/obj/structure/frame/proc/frame_ladder_wants_board()
	return need_circuit && !circuit

/// Has a board a player put in.
/obj/structure/frame/proc/frame_ladder_own_board()
	return need_circuit && circuit

/// Came with its board: it has an outer cover instead.
/obj/structure/frame/proc/frame_ladder_fitted_board()
	return !need_circuit && circuit

/obj/structure/frame/proc/frame_ladder_no_fitted_board()
	return !frame_ladder_fitted_board()

/// TRUE when `held` is a board for this kind of frame, else why not.
/obj/structure/frame/proc/frame_ladder_board_fits(mob/user, obj/item/held)
	return accepts_board(user, src, held)

/obj/structure/frame/proc/frame_ladder_has_components(mob/user, obj/item/held)
	return has_all_components(user, src, held)

/// Plain glass only, not its reinforced or phoron kinds.
/obj/structure/frame/proc/frame_ladder_plain_glass(obj/item/held)
	return held.get_material_name() == MAT_GLASS

/obj/structure/frame/proc/frame_ladder_cover_set(mob/user, obj/item/held, from)
	check_components()
	update_desc()

/obj/structure/frame/proc/frame_ladder_cut_apart(mob/user, obj/item/held, from)
	replace_with(src, /obj/item/stack/material/steel, frame_type.frame_size)

/// The board went in (inserting() moved it into the frame).
/obj/structure/frame/proc/frame_ladder_board_in(mob/user, obj/item/held, from)
	own_set(src, nameof(circuit), held)
	if(frame_type.frame_class == FRAME_CLASS_MACHINE)
		check_components()
		update_desc()

/// The board is coming back out (the undo then moves it to the floor).
/obj/structure/frame/proc/frame_ladder_board_out(mob/user, obj/item/held, destination)
	own_take(src, nameof(circuit))
	if(frame_type.frame_class == FRAME_CLASS_MACHINE)
		req_components = null
	update_desc()

/obj/structure/frame/proc/frame_ladder_wired(mob/user, obj/item/held, from)
	if(from == "board fastened" && frame_type.frame_class == FRAME_CLASS_MACHINE)
		to_chat(user, desc)

/// Unwired, a machine frame's parts come out with the cable.
/obj/structure/frame/proc/frame_ladder_unwired(mob/user, obj/item/held, destination)
	if(destination != "board fastened" || !length(components))
		return
	for(var/obj/item/W in components)
		W.forceMove(loc)
	check_components()
	update_desc()

/// A machine frame's parts come back out; the stage doesn't change.
/obj/structure/frame/proc/frame_ladder_components_out(mob/user, obj/item/held, from)
	if(!length(components))
		to_chat(user, span_notice("There are no components to remove."))
		return
	for(var/obj/item/W in components)
		W.forceMove(loc)
	check_components()
	update_desc()
	to_chat(user, desc)

/obj/structure/frame/proc/frame_ladder_finish_machine(mob/user, obj/item/held, from)
	finish_machine()

/obj/structure/frame/proc/frame_ladder_finish_alarm(mob/user, obj/item/held, from)
	finish_simple(TRUE)

/obj/structure/frame/proc/frame_ladder_finish_screen(mob/user, obj/item/held, from)
	if(frame_type.frame_class == FRAME_CLASS_COMPUTER)
		finish_computer()
	else
		finish_simple(FALSE)
