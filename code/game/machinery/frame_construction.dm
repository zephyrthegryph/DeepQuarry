// Native construction graph. Reverse operations are explicit edges: a dismantled
// machine supplies real board/parts but no purchased-transition ledger to refund.
MSG_DEF_SELF(machine_frame/plain_glass, "it needs plain glass")
MSG_DEF_SELF(machine_frame/missing_components, "it is missing components")

STAGE_DEF(machine_frame, loose)
STAGE_DEF(machine_frame, placed)
STAGE_DEF(machine_frame, board_in)
STAGE_DEF(machine_frame, fastened)
STAGE_DEF(machine_frame, wired)
STAGE_DEF(machine_frame, paneled)
STAGE_DEF(machine_frame, finished)

/obj/structure/frame/proc/native_frame_graph()
	return list(start(STAGE_MACHINE_FRAME_LOOSE),
		stage(STAGE_MACHINE_FRAME_PLACED, list(tool(TOOL_WRENCH), label("Wrench into place"), when(cond_not(PROC_REF(native_fitted_board))), begins(/datum/msg/start/interaction/construction/frame/anchor), wait(2 SECONDS), then(PROC_REF(native_anchor))), from = STAGE_MACHINE_FRAME_LOOSE, undo = list(), key = "anchor"),
		stage(STAGE_MACHINE_FRAME_BOARD_IN, list(item(/obj/item/circuitboard), label("Insert circuit board"), when(PROC_REF(native_wants_board)), needs(req(PROC_REF(native_board_fits))), then(PROC_REF(native_insert_board))), from = STAGE_MACHINE_FRAME_PLACED, undo = list(), key = "insert_board"),
		stage(STAGE_MACHINE_FRAME_FASTENED, list(tool(TOOL_SCREWDRIVER), wait(0), label("Fasten circuit board"), when(PROC_REF(native_own_board)), says(/datum/msg/interaction/construction/frame/fasten_board), then(PROC_REF(native_fasten_board))), from = STAGE_MACHINE_FRAME_BOARD_IN, undo = list(), key = "fasten_board"),
		stage(STAGE_MACHINE_FRAME_WIRED, list(stack(/obj/item/stack/cable_coil, 5), label("Add cables"), begins(/datum/msg/start/interaction/construction/frame/wire), wait(2 SECONDS), says(/datum/msg/interaction/construction/frame/wire), then(PROC_REF(native_wire))), from = STAGE_MACHINE_FRAME_FASTENED, undo = list(), key = "wire"),
		stage(STAGE_MACHINE_FRAME_PANELED, list(stack(/obj/item/stack/material, 2), label("Add glass panel"), when(PROC_REF(native_has_screen)), needs(req_bool(PROC_REF(native_plain_glass), because = MSG(machine_frame/plain_glass))), begins(/datum/msg/start/interaction/construction/frame/add_glass), wait(2 SECONDS), says(/datum/msg/interaction/construction/frame/add_glass), then(PROC_REF(native_add_glass))), from = STAGE_MACHINE_FRAME_WIRED, undo = list(), key = "add_glass"),
		stage(STAGE_MACHINE_FRAME_FINISHED, list(tool(TOOL_SCREWDRIVER), wait(0), label("Finish machine"), when(PROC_REF(native_is_machine)), needs(req(PROC_REF(native_has_components), because = MSG(machine_frame/missing_components))), then(PROC_REF(native_finish_machine))), from = STAGE_MACHINE_FRAME_WIRED, undo = list(), key = "finish_machine"),
		stage(STAGE_MACHINE_FRAME_FINISHED, list(tool(TOOL_SCREWDRIVER), wait(0), label("Fasten cover"), when(PROC_REF(native_is_alarm)), when(cond_not(PROC_REF(native_is_machine))), says(/datum/msg/interaction/construction/frame/finish_alarm), then(PROC_REF(native_finish_alarm))), from = STAGE_MACHINE_FRAME_WIRED, undo = list(), key = "finish_alarm"),
		stage(STAGE_MACHINE_FRAME_FINISHED, list(tool(TOOL_SCREWDRIVER), wait(0), label("Connect monitor"), when(PROC_REF(native_has_screen)), says(/datum/msg/interaction/construction/frame/connect_monitor), then(PROC_REF(native_connect_monitor))), from = STAGE_MACHINE_FRAME_PANELED, undo = list(), key = "connect_monitor"),
		stage(STAGE_MACHINE_FRAME_FINISHED, list(tool(TOOL_WELDER), label("Cut frame apart"), wait(2 SECONDS), says(/datum/msg/interaction/construction/frame/cut_apart), then(PROC_REF(native_cut_apart))), from = list(STAGE_MACHINE_FRAME_LOOSE, STAGE_MACHINE_FRAME_PLACED), undo = list(), key = "cut_apart"),
		stage(STAGE_MACHINE_FRAME_LOOSE, list(tool(TOOL_WRENCH), label("Unfasten frame"), wait(2 SECONDS), says(/datum/msg/interaction/construction/frame/unanchor), then(PROC_REF(native_unanchor))), from = STAGE_MACHINE_FRAME_PLACED, undo = list(), key = "unanchor"),
		stage(STAGE_MACHINE_FRAME_PLACED, list(tool(TOOL_CROWBAR), wait(0), label("Remove circuit board"), when(PROC_REF(native_own_board)), says(/datum/msg/interaction/construction/frame/remove_board), then(PROC_REF(native_remove_board))), from = STAGE_MACHINE_FRAME_BOARD_IN, undo = list(), key = "remove_board"),
		stage(STAGE_MACHINE_FRAME_BOARD_IN, list(tool(TOOL_SCREWDRIVER), wait(0), label("Unfasten circuit board"), when(PROC_REF(native_own_board)), when(cond_not(PROC_REF(native_fitted_board))), says(/datum/msg/interaction/construction/frame/unfasten_board), then(PROC_REF(native_unfasten_board))), from = STAGE_MACHINE_FRAME_FASTENED, undo = list(), key = "unfasten_board"),
		stage(STAGE_MACHINE_FRAME_FASTENED, list(tool(TOOL_WRENCH), label("Wrench into place and set cover"), when(PROC_REF(native_fitted_board)), begins(/datum/msg/start/interaction/construction/frame/anchor), wait(2 SECONDS), then(PROC_REF(native_anchor))), from = STAGE_MACHINE_FRAME_LOOSE, undo = list(), key = "anchor_cover"),
		stage(STAGE_MACHINE_FRAME_PLACED, list(tool(TOOL_SCREWDRIVER), wait(0), label("Unfasten outer cover"), when(PROC_REF(native_fitted_board)), says(/datum/msg/interaction/construction/frame/unfasten_cover), then(PROC_REF(native_unfasten_cover))), from = STAGE_MACHINE_FRAME_FASTENED, undo = list(), key = "unfasten_cover"),
		stage(STAGE_MACHINE_FRAME_FASTENED, list(tool(TOOL_WIRECUTTER), wait(0), label("Remove cables"), then(PROC_REF(native_unwire))), from = STAGE_MACHINE_FRAME_WIRED, undo = list(), key = "unwire"),
		stage(STAGE_MACHINE_FRAME_WIRED, list(tool(TOOL_CROWBAR), wait(0), label("Remove components"), when(PROC_REF(native_is_machine)), then(PROC_REF(native_remove_components))), from = STAGE_MACHINE_FRAME_WIRED, undo = list(), key = "remove_components"),
		stage(STAGE_MACHINE_FRAME_WIRED, list(tool(TOOL_CROWBAR), wait(0), label("Remove glass panel"), when(PROC_REF(native_has_screen)), says(/datum/msg/interaction/construction/frame/remove_glass), then(PROC_REF(native_remove_glass))), from = STAGE_MACHINE_FRAME_PANELED, undo = list(), key = "remove_glass")
	)

/datum/msg/start/interaction/construction/frame/anchor
	self = "You start to wrench the frame into place."

/datum/msg/interaction/construction/frame/unanchor
	self = "You unfasten the frame."

/datum/msg/interaction/construction/frame/cut_apart
	self = "You deconstruct the frame."

/datum/msg/interaction/construction/frame/remove_board
	self = "You remove the circuit board."

/datum/msg/interaction/construction/frame/fasten_board
	self = "You screw the circuit board into place."

/datum/msg/interaction/construction/frame/unfasten_board
	self = "You unfasten the circuit board."

/datum/msg/interaction/construction/frame/unfasten_cover
	self = "You unfasten the outer cover."

/datum/msg/interaction/construction/frame/wire
	self = "You add cables to the frame."

/datum/msg/start/interaction/construction/frame/wire
	self = "You start to add cables to the frame."

/datum/msg/interaction/construction/frame/finish_alarm
	self = "You fasten the cover."

/datum/msg/interaction/construction/frame/add_glass
	self = "You put in the glass panel."

/datum/msg/start/interaction/construction/frame/add_glass
	self = "You start to put in the glass panel."

/datum/msg/interaction/construction/frame/remove_glass
	self = "You remove the glass panel."

/datum/msg/interaction/construction/frame/connect_monitor
	self = "You connect the monitor."

/obj/structure/frame/proc/native_anchor(datum/act/op/A)
	state = FRAME_PLACED
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	frame.set_anchored(TRUE)
	if(!frame.need_circuit && frame.circuit)
		frame.state = FRAME_FASTENED
		frame.check_components()
		frame.update_desc()
		to_chat(actor, span_notice("You wrench the frame into place and set the outer cover."))
	else
		to_chat(actor, span_notice("You wrench the frame into place."))
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_cut_apart(datum/act/op/A)
	var/obj/structure/frame/frame = src
	replace_with(frame, /obj/item/stack/material/steel, frame.frame_type.frame_size)
	return OP_OK


/obj/structure/frame/proc/native_insert_board(datum/act/op/A)
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	var/obj/item/held = A.held
	if(!move_into(frame, nameof(frame.circuit), held, actor))
		return OP_FAILED
	state = FRAME_UNFASTENED
	play_sfx(frame, SFX_ITEMS_DECONSTRUCT)
	to_chat(actor, span_notice("You place the circuit board inside the frame."))
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		frame.check_components()
		frame.update_desc()
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_remove_board(datum/act/op/A)
	state = FRAME_PLACED
	var/obj/structure/frame/frame = src
	frame.circuit.forceMove(frame.loc)
	rel_take(frame, nameof(frame.circuit))
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		frame.req_components = null
	frame.update_desc()
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_wire(datum/act/op/A)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	state = FRAME_WIRED
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		to_chat(actor, frame.desc)
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_unwire(datum/act/op/A)
	new /obj/item/stack/cable_coil(loc, 5)
	state = FRAME_FASTENED
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	if(!length(frame.components))
		to_chat(actor, span_notice("You remove the cables."))
		update_icon()
		return OP_OK
	to_chat(actor, span_notice("You remove the cables and components."))
	for(var/obj/item/W in frame.components)
		W.forceMove(frame.loc)
	frame.check_components()
	frame.update_desc()
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_remove_components(datum/act/op/A)
	state = FRAME_WIRED
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	if(!length(frame.components))
		to_chat(actor, span_notice("There are no components to remove."))
		update_icon()
		return OP_OK
	to_chat(actor, span_notice("You remove the components."))
	for(var/obj/item/W in frame.components)
		W.forceMove(frame.loc)
	frame.check_components()
	frame.update_desc()
	to_chat(actor, frame.desc)
	update_icon()
	return OP_OK


/obj/structure/frame/proc/native_finish_machine(datum/act/op/A)
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	frame.finish_machine(actor)
	return OP_OK


/obj/structure/frame/proc/native_finish_alarm(datum/act/op/A)
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	frame.finish_simple(TRUE, actor)
	return OP_OK


/obj/structure/frame/proc/native_connect_monitor(datum/act/op/A)
	var/obj/structure/frame/frame = src
	var/mob/actor = A.actor
	if(frame.frame_type.frame_class == FRAME_CLASS_COMPUTER)
		frame.finish_computer(actor)
	else
		frame.finish_simple(FALSE, actor)
	return OP_OK


/obj/structure/frame/proc/native_unanchor(datum/act/op/A)
	state = FRAME_PLACED
	set_anchored(FALSE)
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_fasten_board(datum/act/op/A)
	state = FRAME_FASTENED
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_unfasten_board(datum/act/op/A)
	state = FRAME_UNFASTENED
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_unfasten_cover(datum/act/op/A)
	state = FRAME_PLACED
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_add_glass(datum/act/op/A)
	state = FRAME_PANELED
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_remove_glass(datum/act/op/A)
	state = FRAME_WIRED
	new /obj/item/stack/material/glass(loc, 2)
	update_icon()
	return OP_OK

/obj/structure/frame/proc/native_is_machine(datum/act/op/A)
	var/datum/frame/frame_types/F = read_once(frame_type)
	return read_once(F.frame_class) == FRAME_CLASS_MACHINE

/obj/structure/frame/proc/native_is_alarm(datum/act/op/A)
	var/datum/frame/frame_types/F = read_once(frame_type)
	return read_once(F.frame_class) == FRAME_CLASS_ALARM

/obj/structure/frame/proc/native_has_screen(datum/act/op/A)
	var/datum/frame/frame_types/F = read_once(frame_type)
	return read_once(F.frame_class) in list(FRAME_CLASS_COMPUTER, FRAME_CLASS_DISPLAY)

/obj/structure/frame/proc/native_wants_board(datum/act/op/A)
	return read_once(need_circuit) && !read_once(circuit)

/obj/structure/frame/proc/native_own_board(datum/act/op/A)
	return read_once(need_circuit) && !!read_once(circuit)

/obj/structure/frame/proc/native_fitted_board(datum/act/op/A)
	return !read_once(need_circuit) && !!read_once(circuit)

/obj/structure/frame/proc/native_board_fits(datum/act/op/A)
	var/obj/item/circuitboard/board = A.held
	if(!istype(board))
		return "needs a circuit board"
	var/datum/frame/frame_types/board_type = read_once(board.board_type)
	if(read_once(board_type?.name) != read_once(frame_type.name))
		return "this frame does not accept circuit boards of this type"
	return read_once(board.loc?.release_refusal(board, A.actor))

/obj/structure/frame/proc/native_plain_glass(datum/act/op/A)
	return read_once(A.held.get_material_name()) == MAT_GLASS

/obj/structure/frame/proc/native_has_components(datum/act/op/A)
	for(var/R in read_once(req_components))
		if(read_once(req_components[R]) > 0)
			return MSG(machine_frame/missing_components)
	return null

/// Board compatibility and custody; retained for the shared frame bundle too.
/obj/structure/frame/proc/accepts_board(mob/actor, atom/target, obj/item/held)
	var/obj/item/circuitboard/board = held
	if(!istype(board))
		return "needs a circuit board"
	var/datum/frame/frame_types/board_type = board.board_type
	if(board_type?.name != frame_type.name)
		return "this frame does not accept circuit boards of this type"
	var/refusal = board.loc?.release_refusal(board, actor)
	if(refusal)
		return refusal
	return TRUE

/obj/structure/frame/proc/has_all_components(mob/actor, atom/target, obj/item/held)
	for(var/R in req_components)
		if(req_components[R] > 0)
			return FALSE
	return TRUE

/// Seed a physically supplied, part-built frame using the graph's real path.
/// No effects or costs run: the caller already supplied its board and parts.
/obj/structure/frame/proc/seed_native_frame_graph()
	var/wanted = state
	if(anchored || wanted != FRAME_PLACED)
		if(graph_current(src) == STAGE_MACHINE_FRAME_LOOSE)
			graph_advance(src, STAGE_MACHINE_FRAME_PLACED, "anchor")
	if(wanted >= FRAME_UNFASTENED && graph_current(src) == STAGE_MACHINE_FRAME_PLACED)
		graph_advance(src, STAGE_MACHINE_FRAME_BOARD_IN, "insert_board")
	if(wanted >= FRAME_FASTENED && graph_current(src) == STAGE_MACHINE_FRAME_BOARD_IN)
		graph_advance(src, STAGE_MACHINE_FRAME_FASTENED, "fasten_board")
	if(wanted >= FRAME_WIRED && graph_current(src) == STAGE_MACHINE_FRAME_FASTENED)
		graph_advance(src, STAGE_MACHINE_FRAME_WIRED, "wire")
	if(wanted >= FRAME_PANELED && graph_current(src) == STAGE_MACHINE_FRAME_WIRED)
		graph_advance(src, STAGE_MACHINE_FRAME_PANELED, "add_glass")

/// Builds the machine from the board, moving the installed parts into it.
/obj/structure/frame/proc/finish_machine(mob/user = null)
	var/obj/machinery/new_machine = new circuit.build_path(src.loc, dir)
	new_machine.copy_material_construction_from(src)
	// Handle machines that have allocated default parts in thier constructor.
	if(new_machine.component_parts)
		for(var/CP in new_machine.component_parts)
			spent(CP, user)
		rel_take_all(new_machine, nameof(new_machine.component_parts))
	else
		rel_take_all(new_machine, nameof(new_machine.component_parts))

	circuit.construct(new_machine, user)

	// new_machine's own default board+parts (latent_generator(), roadmap C6)
	// already resolved into entries the moment its Initialize() first asked
	// the ledger a question (RefreshParts, typically). The frame's real,
	// player-installed parts replace them, not add to them.
	var/datum/ledger/new_machine_ledger = dq_ledger(new_machine)
	new_machine_ledger?.latent_clear()

	// The frame's installed parts are real physical items the player put in;
	// move_into() keeps the new machine's ledger (roadmap C6) current, so
	// RefreshParts() and get_part_rating() see them straight away.
	for(var/obj/O in rel_take_all(src, nameof(components)))
		if(circuit.contain_parts)
			move_into(new_machine, CONTAINER_SLOT_INTERNALS, O)
		else
			O.moveToNullspace()
		rel_add(new_machine, nameof(new_machine.component_parts), O)

	circuit.moveToNullspace()
	move_into(new_machine, CONTAINER_SLOT_INTERNALS, circuit)
	rel_move(src, nameof(circuit), new_machine, nameof(new_machine.circuit))

	new_machine.RefreshParts()
	new_machine.finalize_material_assembly()

	new_machine.pixel_x = pixel_x
	new_machine.pixel_y = pixel_y
	replace_with(src, new_machine)

/// Builds an alarm (facing the frame's way first) or a display from the board.
/obj/structure/frame/proc/finish_simple(alarm, mob/user = null)
	var/obj/machinery/B = new circuit.build_path(src.loc)
	B.pixel_x = pixel_x
	B.pixel_y = pixel_y
	B.set_dir(dir)
	circuit.construct(B, user)
	circuit.moveToNullspace()
	rel_move(src, nameof(circuit), B, nameof(B.circuit))
	if(!alarm)
		B.update_icon()
	replace_with(src, B)

/// Builds a computer.
/obj/structure/frame/proc/finish_computer(mob/user = null)
	var/obj/machinery/B = new circuit.build_path(src.loc)
	B.pixel_x = pixel_x
	B.pixel_y = pixel_y
	B.set_dir(dir)
	circuit.construct(B, user)
	circuit.moveToNullspace()
	rel_move(src, nameof(circuit), B, nameof(B.circuit))
	replace_with(src, B)
