/**
 * Machine frame construction graph (doc/rewrite/interactions.md §10).
 *
 * States are the frame's FRAME_* `state`, plus "loose" for a placed frame
 * that isn't wrenched down yet. Which steps a frame offers depends on its
 * frame class (machine, computer, display, alarm): available_on() hides the
 * others. Putting stock parts into a machine frame stays with the part
 * (attackby) until machine internals become data (C6).
 */
/obj/structure/frame
	construction_graph = /datum/construction_graph/frame

/datum/construction_graph/frame
	id = "frame"
	state_var = null
	states = list("loose", FRAME_PLACED, FRAME_UNFASTENED, FRAME_FASTENED, FRAME_WIRED, FRAME_PANELED)
	initial_states = list("loose", FRAME_PLACED)
	edge_types = list(
		/datum/interaction/construction/frame/anchor,
		/datum/interaction/construction/frame/unanchor,
		/datum/interaction/construction/frame/cut_apart,
		/datum/interaction/construction/frame/cut_apart/loose,
		/datum/interaction/construction/frame/insert_board,
		/datum/interaction/construction/frame/remove_board,
		/datum/interaction/construction/frame/fasten_board,
		/datum/interaction/construction/frame/unfasten_board,
		/datum/interaction/construction/frame/unfasten_cover,
		/datum/interaction/construction/frame/wire,
		/datum/interaction/construction/frame/unwire,
		/datum/interaction/construction/frame/remove_components,
		/datum/interaction/construction/frame/finish_machine,
		/datum/interaction/construction/frame/finish_alarm,
		/datum/interaction/construction/frame/add_glass,
		/datum/interaction/construction/frame/remove_glass,
		/datum/interaction/construction/frame/connect_monitor,
	)

/datum/construction_graph/frame/state_of(atom/target)
	var/obj/structure/frame/frame = target
	if(!istype(frame))
		return null
	if(frame.state == FRAME_PLACED && !frame.anchored)
		return "loose"
	return frame.state

/datum/construction_graph/frame/set_state(atom/target, state)
	var/obj/structure/frame/frame = target
	if(!istype(frame) || state == CONSTRUCTION_DONE)
		return
	if(state == "loose")
		frame.state = FRAME_PLACED
		frame.anchored = FALSE
		return
	frame.state = state

/datum/construction_graph/frame/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	if(!QDELETED(target))
		target.update_icon()

/datum/interaction/construction/frame
	/// FRAME_CLASS_* values this step is for; null for every class.
	var/list/classes

/datum/interaction/construction/frame/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return !classes || (frame.frame_type.frame_class in classes)

// ---- Placing ----

/datum/interaction/construction/frame/anchor
	from_state = "loose"
	to_state = FRAME_PLACED
	step_text = "wrench the frame into place"
	tool = TOOL_WRENCH
	duration = 2 SECONDS
	start_self = "You start to wrench the frame into place."

/datum/interaction/construction/frame/anchor/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	frame.anchored = TRUE
	if(!frame.need_circuit && frame.circuit)
		frame.state = FRAME_FASTENED
		frame.check_components()
		frame.update_desc()
		to_chat(actor, span_notice("You wrench the frame into place and set the outer cover."))
	else
		to_chat(actor, span_notice("You wrench the frame into place."))
	return TRUE

/datum/interaction/construction/frame/unanchor
	from_state = FRAME_PLACED
	to_state = "loose"
	step_text = "unfasten the frame"
	tool = TOOL_WRENCH
	duration = 2 SECONDS
	message_self = "You unfasten the frame."

/datum/interaction/construction/frame/cut_apart
	from_state = FRAME_PLACED
	to_state = CONSTRUCTION_DONE
	step_text = "cut the frame apart"
	tool = TOOL_WELDER
	duration = 2 SECONDS
	message_self = "You deconstruct the frame."

/datum/interaction/construction/frame/cut_apart/loose
	from_state = "loose"

/datum/interaction/construction/frame/cut_apart/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	new /obj/item/stack/material/steel(frame.loc, frame.frame_type.frame_size)
	qdel(frame)
	return TRUE

// ---- The circuit board ----

/datum/interaction/construction/frame/insert_board
	from_state = FRAME_PLACED
	to_state = FRAME_UNFASTENED
	step_text = "insert a circuit board"
	item_type = /obj/item/circuitboard
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/accepts_board, null))

/datum/interaction/construction/frame/insert_board/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return frame.need_circuit && !frame.circuit

/datum/interaction/construction/frame/insert_board/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	playsound(frame, 'sound/items/Deconstruct.ogg', 50, 1)
	to_chat(actor, span_notice("You place the circuit board inside the frame."))
	frame.circuit = held
	actor.drop_item()
	held.loc = frame
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		frame.check_components()
		frame.update_desc()
	return TRUE

/// TRUE when `held` is a board for this kind of frame, else why not.
/obj/structure/frame/proc/accepts_board(mob/actor, atom/target, obj/item/held)
	var/obj/item/circuitboard/board = held
	if(!istype(board))
		return "needs a circuit board"
	var/datum/frame/frame_types/board_type = board.board_type
	if(board_type?.name != frame_type.name)
		return "this frame does not accept circuit boards of this type"
	return TRUE

/datum/interaction/construction/frame/remove_board
	from_state = FRAME_UNFASTENED
	to_state = FRAME_PLACED
	step_text = "remove the circuit board"
	tool = TOOL_CROWBAR
	message_self = "You remove the circuit board."

/datum/interaction/construction/frame/remove_board/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return frame.need_circuit && frame.circuit

/datum/interaction/construction/frame/remove_board/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	frame.circuit.forceMove(frame.loc)
	frame.circuit = null
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		frame.req_components = null
	frame.update_desc()
	return TRUE

/datum/interaction/construction/frame/fasten_board
	from_state = FRAME_UNFASTENED
	to_state = FRAME_FASTENED
	step_text = "screw the circuit board into place"
	tool = TOOL_SCREWDRIVER
	message_self = "You screw the circuit board into place."

/datum/interaction/construction/frame/fasten_board/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return frame.need_circuit && frame.circuit

/datum/interaction/construction/frame/unfasten_board
	from_state = FRAME_FASTENED
	to_state = FRAME_UNFASTENED
	step_text = "unfasten the circuit board"
	tool = TOOL_SCREWDRIVER
	message_self = "You unfasten the circuit board."

/datum/interaction/construction/frame/unfasten_board/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return frame.need_circuit && frame.circuit

/// Frames that come with their board have an outer cover instead.
/datum/interaction/construction/frame/unfasten_cover
	from_state = FRAME_FASTENED
	to_state = FRAME_PLACED
	step_text = "unfasten the outer cover"
	tool = TOOL_SCREWDRIVER
	message_self = "You unfasten the outer cover."

/datum/interaction/construction/frame/unfasten_cover/available_on(atom/target)
	var/obj/structure/frame/frame = target
	return !frame.need_circuit && frame.circuit

// ---- Wiring ----

/datum/interaction/construction/frame/wire
	from_state = FRAME_FASTENED
	to_state = FRAME_WIRED
	step_text = "add cables"
	item_type = /obj/item/stack/cable_coil
	item_amount = 5
	item_use = CONSTRUCTION_ITEM_USE
	duration = 2 SECONDS
	start_self = "You start to add cables to the frame."
	message_self = "You add cables to the frame."

/datum/interaction/construction/frame/wire/pay_cost(mob/actor, atom/target, obj/item/held)
	playsound(target, 'sound/items/Deconstruct.ogg', 50, 1)
	return ..()

/datum/interaction/construction/frame/wire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	if(frame.frame_type.frame_class == FRAME_CLASS_MACHINE)
		to_chat(actor, frame.desc)
	return TRUE

/datum/interaction/construction/frame/unwire
	from_state = FRAME_WIRED
	to_state = FRAME_FASTENED
	step_text = "remove the cables"
	tool = TOOL_WIRECUTTER
	classes = list(FRAME_CLASS_COMPUTER, FRAME_CLASS_DISPLAY, FRAME_CLASS_ALARM, FRAME_CLASS_MACHINE)
	materials_out = list(/obj/item/stack/cable_coil = 5)

/datum/interaction/construction/frame/unwire/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	if(!length(frame.components))
		to_chat(actor, span_notice("You remove the cables."))
		return TRUE
	to_chat(actor, span_notice("You remove the cables and components."))
	for(var/obj/item/W in frame.components)
		W.forceMove(frame.loc)
	frame.check_components()
	frame.update_desc()
	return TRUE

/// A machine frame's parts come back out; the state doesn't change.
/datum/interaction/construction/frame/remove_components
	from_state = FRAME_WIRED
	to_state = FRAME_WIRED
	step_text = "remove the components"
	tool = TOOL_CROWBAR
	classes = list(FRAME_CLASS_MACHINE)

/datum/interaction/construction/frame/remove_components/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	if(!length(frame.components))
		to_chat(actor, span_notice("There are no components to remove."))
		return TRUE
	to_chat(actor, span_notice("You remove the components."))
	for(var/obj/item/W in frame.components)
		W.forceMove(frame.loc)
	frame.check_components()
	frame.update_desc()
	to_chat(actor, frame.desc)
	return TRUE

// ---- Finishing ----

/datum/interaction/construction/frame/finish_machine
	from_state = FRAME_WIRED
	to_state = CONSTRUCTION_DONE
	step_text = "finish the machine"
	tool = TOOL_SCREWDRIVER
	classes = list(FRAME_CLASS_MACHINE)
	priority = 11
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/structure/frame/proc/has_all_components, "it is missing components"))

/datum/interaction/construction/frame/finish_machine/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	frame.finish_machine()
	return TRUE

/obj/structure/frame/proc/has_all_components(mob/actor, atom/target, obj/item/held)
	for(var/R in req_components)
		if(req_components[R] > 0)
			return FALSE
	return TRUE

/datum/interaction/construction/frame/finish_alarm
	from_state = FRAME_WIRED
	to_state = CONSTRUCTION_DONE
	step_text = "fasten the cover"
	tool = TOOL_SCREWDRIVER
	classes = list(FRAME_CLASS_ALARM)
	message_self = "You fasten the cover."

/datum/interaction/construction/frame/finish_alarm/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	frame.finish_simple(TRUE)
	return TRUE

/datum/interaction/construction/frame/add_glass
	from_state = FRAME_WIRED
	to_state = FRAME_PANELED
	step_text = "put in the glass panel"
	item_type = /obj/item/stack/material/glass
	item_name = "glass sheets"
	item_amount = 2
	item_use = CONSTRUCTION_ITEM_USE
	duration = 2 SECONDS
	classes = list(FRAME_CLASS_COMPUTER, FRAME_CLASS_DISPLAY)
	start_self = "You start to put in the glass panel."
	message_self = "You put in the glass panel."

/// Plain glass only, not its reinforced or phoron kinds.
/datum/interaction/construction/frame/add_glass/item_matches(obj/item/held)
	return istype(held, /obj/item/stack/material) && held.get_material_name() == MAT_GLASS

/datum/interaction/construction/frame/add_glass/pay_cost(mob/actor, atom/target, obj/item/held)
	playsound(target, 'sound/items/Deconstruct.ogg', 50, 1)
	return ..()

/datum/interaction/construction/frame/remove_glass
	from_state = FRAME_PANELED
	to_state = FRAME_WIRED
	step_text = "remove the glass panel"
	tool = TOOL_CROWBAR
	classes = list(FRAME_CLASS_COMPUTER, FRAME_CLASS_DISPLAY)
	message_self = "You remove the glass panel."
	materials_out = list(/obj/item/stack/material/glass = 2)

/datum/interaction/construction/frame/connect_monitor
	from_state = FRAME_PANELED
	to_state = CONSTRUCTION_DONE
	step_text = "connect the monitor"
	tool = TOOL_SCREWDRIVER
	classes = list(FRAME_CLASS_COMPUTER, FRAME_CLASS_DISPLAY)
	message_self = "You connect the monitor."

/datum/interaction/construction/frame/connect_monitor/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	var/obj/structure/frame/frame = target
	if(frame.frame_type.frame_class == FRAME_CLASS_COMPUTER)
		frame.finish_computer()
	else
		frame.finish_simple(FALSE)
	return TRUE

/// Builds the machine from the board, moving the installed parts into it.
/obj/structure/frame/proc/finish_machine()
	var/obj/machinery/new_machine = new circuit.build_path(src.loc, dir)
	new_machine.copy_material_construction_from(src)
	// Handle machines that have allocated default parts in thier constructor.
	if(new_machine.component_parts)
		for(var/CP in new_machine.component_parts)
			qdel(CP)
		new_machine.component_parts.Cut()
	else
		new_machine.component_parts = list()

	circuit.construct(new_machine)

	// new_machine's own default board+parts (latent_generator(), roadmap C6)
	// already resolved into entries the moment its Initialize() first asked
	// the ledger a question (RefreshParts, typically). The frame's real,
	// player-installed parts replace them, not add to them.
	dq_ledger(new_machine)?.latent_clear()

	// The frame's installed parts are real physical items the player put in;
	// move_into() keeps the new machine's ledger (roadmap C6) current, so
	// RefreshParts() and get_part_rating() see them straight away.
	for(var/obj/O in components)
		if(circuit.contain_parts)
			O.move_into(new_machine, CONTAINER_SLOT_INTERNALS)
		else
			O.loc = null
		new_machine.component_parts += O

	circuit.loc = null
	circuit.move_into(new_machine, CONTAINER_SLOT_INTERNALS)
	new_machine.circuit = circuit

	new_machine.RefreshParts()
	new_machine.finalize_material_assembly()

	new_machine.pixel_x = pixel_x
	new_machine.pixel_y = pixel_y
	qdel(src)

/// Builds an alarm (facing the frame's way first) or a display from the board.
/obj/structure/frame/proc/finish_simple(alarm)
	var/obj/machinery/B = new circuit.build_path(src.loc)
	B.pixel_x = pixel_x
	B.pixel_y = pixel_y
	B.set_dir(dir)
	circuit.construct(B)
	circuit.loc = null
	B.circuit = circuit
	if(!alarm)
		B.update_icon()
	qdel(src)

/// Builds a computer, and redraws the consoles beside it.
/obj/structure/frame/proc/finish_computer()
	var/obj/machinery/B = new circuit.build_path(src.loc)
	B.pixel_x = pixel_x
	B.pixel_y = pixel_y
	B.set_dir(dir)
	circuit.construct(B)
	circuit.loc = null
	B.circuit = circuit
	var/obj/machinery/computer/LC = locate() in get_step(B, turn(B.dir, 90))
	var/obj/machinery/computer/RC = locate() in get_step(B, turn(B.dir, -90))
	if(LC)
		LC.update_icon()
	if(RC)
		RC.update_icon()
	qdel(src)
