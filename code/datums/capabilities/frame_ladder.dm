/**
 * The standard machine frame ladder and the deconstruct capability (doc/rewrite/dx_conventions.md §2).
 *
 * A board-built machine carries cap_deconstruct(board): with its maintenance panel open, a crowbar
 * takes it apart into a frame holding its board, and the frame's standard ladder builds it back:
 *
 *	/obj/structure/frame/capabilities()
 *		. = ..()
 *		. += cap_frame_ladder()	// a proc on the frame
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

CAPABILITIES(/datum/capability/deconstruct)
	owns_one(nameof(dismantle), /datum/interaction/capability)

/**
 * cap_deconstruct(board = /obj/item/circuitboard/x, needs = req_set(PANEL)): with the panel open, a crowbar
 * dismantles the machine into its frame. Works broken and unpowered.
 */
/proc/cap_deconstruct(board, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/deconstruct/made = new
	made.board = board
	return cap_gating(made, needs = needs,
		else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/// One crowbar entry; its gating comes from the capability (cap_apply_gating()).
/datum/capability/deconstruct/interactions(atom/holder)
	if(!dismantle)
		var/datum/interaction/capability/entry = new
		entry.name = "Dismantle"
		entry.id = "deconstruct:[board]"
		entry.handler = TYPE_PROC_REF(/obj/machinery, cap_dismantle)
		entry.tool = TOOL_CROWBAR
		entry.category = INTERACTION_CAT_MAINTAIN
		entry.default_action = INPUT_ACTION_USE
		entry.works_broken = TRUE
		entry.works_unpowered = TRUE
		entry.apply_stance_tags()
		// A real op (the router ranks it): the crowbar that takes the machine apart, a structural part op.
		op_attach(entry, "dismantle", ACT_USE, OP_PRIORITY_NORMAL, OP_STRUCTURAL)
		rel_set(src, nameof(src.dismantle), entry)
	return list(dismantle)

/datum/capability/deconstruct/examine(atom/holder, mob/user)
	if(behind && (behind & ~capability_bits(holder)))
		return null
	return list(span_notice("It could be pried apart into its frame with a crowbar."))

/// The dismantle entry's handler: the machine comes apart into its frame, board and parts.
/obj/machinery/proc/cap_dismantle(mob/user, obj/item/held)
	return dismantle()


// ---- The standard frame ladder ----

/**
 * cap_frame_ladder(): the frame's ladder. Its stage is the frame's `state` (FRAME_*), plus "loose"
 * for a placed frame that isn't wrenched down; frame_ladder_stage() names them. It is a proc on the
 * frame, the only holder its hooks exist on, so they are plain PROC_REFs (it reads no instance var).
 */
/obj/structure/frame/proc/cap_frame_ladder()
	return cap_construction(
		ladder_options(state = PROC_REF(frame_ladder_stage), store = PROC_REF(set_frame_ladder_stage), starts = list("placed")),
		stage("loose", also = list(frame_ladder_cut_branch(),
			branch("board fastened", cap_tool(quality = TOOL_WRENCH, delay = 2 SECONDS), say = "wrench %T% into place and set its cover",
				when = PROC_REF(frame_ladder_fitted_board), on_enter = PROC_REF(frame_ladder_cover_set)))),
		stage("placed", build = cap_tool(quality = TOOL_WRENCH, delay = 2 SECONDS), undo = cap_tool(quality = TOOL_WRENCH, delay = 2 SECONDS), anchored = TRUE,
			when = PROC_REF(frame_ladder_no_fitted_board), also = list(frame_ladder_cut_branch())),
		stage("board in", build = cap_insert(held_type = /obj/item/circuitboard, needs = PROC_REF(frame_ladder_board_fits)),
			sfx = SFX_ITEMS_DECONSTRUCT, when = PROC_REF(frame_ladder_wants_board),
			undo = cap_tool(quality = TOOL_CROWBAR), undo_say = "pry the circuit board out of %T%", undo_when = PROC_REF(frame_ladder_own_board),
			on_enter = PROC_REF(frame_ladder_board_in), on_leave = PROC_REF(frame_ladder_board_out)),
		stage("board fastened", build = cap_tool(quality = TOOL_SCREWDRIVER), say = "screw the circuit board into %T%",
			undo = cap_tool(quality = TOOL_SCREWDRIVER), undo_say = "unscrew the circuit board in %T%", undo_when = PROC_REF(frame_ladder_own_board),
			also = list(branch("placed", cap_tool(quality = TOOL_SCREWDRIVER), say = "unfasten %T%'s outer cover",
				when = PROC_REF(frame_ladder_fitted_board)))),
		stage("wired", build = cap_use_on(held_type = /obj/item/stack/cable_coil, delay = 2 SECONDS), uses = 5, sfx = SFX_ITEMS_DECONSTRUCT,
			undo = cap_tool(quality = TOOL_WIRECUTTER),
			on_enter = PROC_REF(frame_ladder_wired), on_leave = PROC_REF(frame_ladder_unwired),
			also = list(
				branch("wired", cap_tool(quality = TOOL_CROWBAR), say = "pry the components out of %T%",
					when = PROC_REF(frame_ladder_is_machine), on_enter = PROC_REF(frame_ladder_components_out)),
				branch(LADDER_DONE, cap_tool(quality = TOOL_SCREWDRIVER), say = "finish %T%", priority = 11,
					when = PROC_REF(frame_ladder_is_machine), on_enter = PROC_REF(frame_ladder_finish_machine),
					needs = PROC_REF(frame_ladder_has_components), else_say = "it is missing components"),
				branch(LADDER_DONE, cap_tool(quality = TOOL_SCREWDRIVER), say = "fasten %T%'s cover",
					when = PROC_REF(frame_ladder_is_alarm), on_enter = PROC_REF(frame_ladder_finish_alarm)))),
		stage("paneled", build = cap_use_on("glass sheets", /obj/item/stack/material/glass, delay = 2 SECONDS,
				needs = PROC_REF(frame_ladder_plain_glass), else_say = "it needs plain glass"),
			uses = 2, sfx = SFX_ITEMS_DECONSTRUCT, when = PROC_REF(frame_ladder_has_screen),
			undo = cap_tool(quality = TOOL_CROWBAR), undo_say = "pry the glass panel out of %T%", undo_when = PROC_REF(frame_ladder_has_screen),
			also = list(branch(LADDER_DONE, cap_tool(quality = TOOL_SCREWDRIVER), say = "connect %T%'s monitor",
				when = PROC_REF(frame_ladder_has_screen), on_enter = PROC_REF(frame_ladder_finish_screen)))),
	)

/// Welding the frame apart, from a loose or placed frame (each stage owns its own branch).
/obj/structure/frame/proc/frame_ladder_cut_branch()
	return branch(LADDER_DONE, cap_tool(quality = TOOL_WELDER, delay = 2 SECONDS), say = "cut %T% apart",
		on_enter = PROC_REF(frame_ladder_cut_apart))

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
/obj/structure/frame/proc/frame_ladder_plain_glass(mob/user, obj/item/held)
	return held.get_material_name() == MAT_GLASS

/obj/structure/frame/proc/frame_ladder_cover_set(mob/user, obj/item/held, from)
	check_components()
	update_desc()

/obj/structure/frame/proc/frame_ladder_cut_apart(mob/user, obj/item/held, from)
	replace_with(src, /obj/item/stack/material/steel, frame_type.frame_size)

/// The board went in (the cap_insert() cost moved it into the frame).
/obj/structure/frame/proc/frame_ladder_board_in(mob/user, obj/item/held, from)
	rel_set(src, nameof(src.circuit), held)
	if(frame_type.frame_class == FRAME_CLASS_MACHINE)
		check_components()
		update_desc()

/// The board is coming back out (the undo then moves it to the floor).
/obj/structure/frame/proc/frame_ladder_board_out(mob/user, obj/item/held, destination)
	rel_take(src, nameof(src.circuit))
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
	finish_machine(user)

/obj/structure/frame/proc/frame_ladder_finish_alarm(mob/user, obj/item/held, from)
	finish_simple(TRUE, user)

/obj/structure/frame/proc/frame_ladder_finish_screen(mob/user, obj/item/held, from)
	if(frame_type.frame_class == FRAME_CLASS_COMPUTER)
		finish_computer(user)
	else
		finish_simple(FALSE, user)
