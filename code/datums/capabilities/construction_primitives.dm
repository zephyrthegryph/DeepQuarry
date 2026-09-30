/**
 * Construction primitives, joints and presets (doc/rewrite/dx_conventions.md §2).
 *
 * A ladder is declared as a short list of what the player does, not as stages with hand-written
 * undo, refund, message, icon and delay data. Everything else is derived:
 *
 *	cap_construction(
 *		build_fit(/obj/item/circuitboard/apc),
 *		build_wire(5),
 *		build_fasten(TOOL_SCREWDRIVER, name = "covered"),
 *		build_weld(),
 *		ladder_options(sprite = "frame", undo_delay = 1 SECONDS),
 *	)
 *
 * Primitives (one stage each):
 *	build_insert(part)		put a part in by hand; the undo takes it out by hand
 *	build_wire(n)				n cable; the undo cuts it out with wirecutters and gives it back
 *	build_fasten(tool)		a tool step; the undo is the tool the fastener table says (ladder_undo_tool())
 *	build_weld()				build_fasten(TOOL_WELDER)
 * Joints (stages that assemble a part and hold it):
 *	build_fit(part)			a part a crowbar pries out again
 *	build_plate(sheets, n)	n sheets welded on; the welder cuts them off and gives the sheets back
 *	build_parts(list)			one build_fit() per part type, in order
 * Presets (lists of stages, ready to pass to cap_construction()):
 *	mech_chassis(result, sprite =, parts =, steps =)
 *	machine_frame(), computer_frame(), wall_frame(board), girder()
 *
 * Derived: the undo (fastener table), the refund (an undo gives back what its build consumed), the
 * messages (the verb table), the stage icons (`sprite` + the stage's position), delays (per-tool
 * defaults; ladder_options(undo_delay =) overrides every undo), and stage names (from the part or the
 * tool, made unique). The stage a holder is on belongs to the ladder (built_past()), not to a holder var.
 * A holder type that defines its own build_weld()/build_insert()/build_wire() proc shadows these inside its own procs:
 * call global.weld() there.
 */

/// The wait of a tool step with no better answer.
#define DEFAULT_LADDER_DELAY (1.5 SECONDS)

/// The wait a step with `tool` takes unless the declaration gives one.
/proc/ladder_tool_delay(tool)
	switch(tool)
		if(TOOL_WRENCH, TOOL_CROWBAR)
			return 2 SECONDS
		if(TOOL_WELDER)
			return 3 SECONDS
	return DEFAULT_LADDER_DELAY

/// The tool that undoes a `tool` fastening: the fastener table. A screw comes out with a screwdriver, a
/// bolt with a wrench, a weld is cut with the welder, a prying with a crowbar.
/proc/ladder_undo_tool(tool)
	return tool

/// The short name of a type: /obj/item/stock_parts/capacitor -> "capacitor".
/proc/ladder_type_word(path)
	var/first = islist(path) ? path[1] : path
	var/text = "[first]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// build_insert(part): the part goes in by hand and comes out by hand. `name`: the stage's name.
/proc/build_insert(part, name, desc, icon, delay = 1 SECONDS, needs, else_say, undo_needs, undo_else_say, on_enter, on_leave)
	return stage(name = name || ladder_type_word(part), build = cap_insert(held_type = part, delay = delay), undo = cap_hand(delay = delay),
		desc = desc, icon = icon, needs = needs, else_say = else_say, undo_needs = undo_needs, undo_else_say = undo_else_say, on_enter = on_enter, on_leave = on_leave)

/// build_wire(n): n cable units go in; wirecutters cut them out and give them back.
/proc/build_wire(amount = 1, name = "wired", desc, icon, needs, else_say, undo_needs, undo_else_say, on_enter, on_leave)
	return stage(name = name, build = cap_use_on(held_type = /obj/item/stack/cable_coil, delay = ladder_tool_delay(TOOL_WIRECUTTER)), uses = amount,
		undo = cap_tool(quality = TOOL_WIRECUTTER, delay = ladder_tool_delay(TOOL_WIRECUTTER)), desc = desc, icon = icon,
		needs = needs, else_say = else_say, undo_needs = undo_needs, undo_else_say = undo_else_say, on_enter = on_enter, on_leave = on_leave)

// DM quirk behind `name = name || ...` in every stage() call here: a positional string equal to the name of
// a named argument in the same call ("anchored" beside `anchored = ...`) is read as that argument's key and
// the positional parameter comes out empty. The name is therefore always passed by name.

/// build_fasten(tool): a tool step. Its undo is ladder_undo_tool(tool). `fuel` is welder fuel.
/proc/build_fasten(tool, name, desc, icon, anchored, fuel = 0, delay, needs, else_say, undo_needs, undo_else_say, on_enter, on_leave)
	var/undo_tool = ladder_undo_tool(tool)
	var/datum/ladder_stage/made = stage(name = name || "fastened with [tool]", build = cap_tool(quality = tool, delay = delay || ladder_tool_delay(tool), fuel = fuel),
		undo = cap_tool(quality = undo_tool, delay = delay || ladder_tool_delay(undo_tool), fuel = fuel),
		desc = desc, icon = icon, anchored = anchored, needs = needs, else_say = else_say, undo_needs = undo_needs, undo_else_say = undo_else_say,
		on_enter = on_enter, on_leave = on_leave)
	return made

/// build_weld(): build_fasten(TOOL_WELDER) with the welder's usual fuel.
/proc/build_weld(name = "welded", desc, icon, fuel = 1)
	return build_fasten(TOOL_WELDER, name = name, desc = desc, icon = icon, fuel = fuel)

/// build_fit(part): a part that is fitted and held: a crowbar pries it out again.
/proc/build_fit(part, name, desc, icon)
	return stage(name = name || ladder_type_word(part), build = cap_insert(held_type = part, delay = 1 SECONDS),
		undo = cap_tool(quality = TOOL_CROWBAR, delay = ladder_tool_delay(TOOL_CROWBAR)), desc = desc, icon = icon)

/// build_plate(sheets, n, name =): n sheets welded on; the welder cuts them off and gives the sheets back.
/proc/build_plate(sheets, amount = 2, name, desc, icon)
	return stage(name = name || "[ladder_type_word(sheets)] plated", build = cap_use_on(held_type = sheets, delay = ladder_tool_delay(TOOL_WELDER)), uses = amount,
		undo = cap_tool(quality = TOOL_WELDER, delay = ladder_tool_delay(TOOL_WELDER), fuel = 1), desc = desc, icon = icon)

/// build_parts(list): one build_fit() per part type, in order.
/proc/build_parts(list/part_types)
	. = list()
	for(var/path in part_types)
		. += build_fit(path)

// ---- Presets: lists of ladder elements for cap_construction() ----

/**
 * A mech's chassis: the frame comes together in order and the finished ladder turns into `result`
 * (the holder is replaced). `parts`: part types fitted after the frame; `steps`: extra stages
 * (primitives) before the last fastening.
 */
/proc/mech_chassis(result, sprite, list/parts, list/steps)
	. = list(ladder_options(sprite = sprite), stage("frame", desc = "An unfinished mech chassis."))
	. += build_fasten(TOOL_WRENCH, name = "anchored", anchored = TRUE)
	if(length(parts))
		. += build_parts(parts)
	if(length(steps))
		. += steps
	. += build_wire(4)
	var/datum/ladder_stage/finished = build_fasten(TOOL_SCREWDRIVER, name = "finished")
	finished.also = list(branch(LADDER_DONE, cap_tool(quality = TOOL_WELDER, delay = ladder_tool_delay(TOOL_WELDER)), say = "weld %T% into a mech", become = result))
	. += finished

/// A machine frame: anchored, a circuit board fitted, cable, then closed up.
/proc/machine_frame(board = /obj/item/circuitboard)
	. = list(ladder_options(sprite = "box_"), stage("loose", desc = "A loose frame."))
	. += build_fasten(TOOL_WRENCH, name = "anchored", anchored = TRUE)
	. += build_fit(board, name = "board in")
	. += build_wire(5)
	. += build_fasten(TOOL_SCREWDRIVER, name = "closed")

/// A computer frame: anchored, board, cable, glass, then closed up.
/proc/computer_frame(board = /obj/item/circuitboard)
	. = list(ladder_options(sprite = "comp_"), stage("loose", desc = "A loose frame."))
	. += build_fasten(TOOL_WRENCH, name = "anchored", anchored = TRUE)
	. += build_fit(board, name = "board in")
	. += build_wire(5)
	. += build_plate(/obj/item/stack/material/glass, 2, name = "glazed")
	. += build_fasten(TOOL_SCREWDRIVER, name = "closed")

/// A wall-mounted frame: fastened to the wall, its board fitted, cable, then closed up.
/proc/wall_frame(board = /obj/item/circuitboard)
	. = list(ladder_options(sprite = "wall_"), stage("loose", desc = "A frame that is not yet fastened to the wall."))
	. += build_fasten(TOOL_SCREWDRIVER, name = "fastened", anchored = TRUE)
	. += build_fit(board, name = "board in")
	. += build_wire(3)
	. += build_fasten(TOOL_SCREWDRIVER, name = "closed")

/// A girder: anchored, plated, then welded.
/proc/girder(sheets = /obj/item/stack/material/steel)
	. = list(ladder_options(sprite = "girder_"), stage("displaced", desc = "A girder that is not anchored."))
	. += build_fasten(TOOL_WRENCH, name = "anchored", anchored = TRUE)
	. += build_plate(sheets, 2, name = "plated")
	. += build_weld(name = "finished")

// ---- Reading the ladder's state ----

/**
 * Whether `target`'s stage is after `stage_name` in its ladder: a holder asks its ladder, it keeps no
 * stage var of its own. FALSE for a holder with no ladder or a name the ladder has no stage of.
 */
/proc/built_past(atom/target, stage_name)
	var/datum/construction_ladder/ladder = ladder_of(target)
	if(!ladder)
		return FALSE
	var/mark = ladder.states.Find("[stage_name]")
	var/here = ladder.states.Find("[ladder.state_of(target)]")
	return mark && here && here > mark

/// Flattens lists inside a declaration (presets return lists) and makes stage names unique (a ladder
/// may fit two like parts: "capacitor", "capacitor 2").
/proc/ladder_flatten_declaration(list/declared)
	. = list()
	for(var/entry in declared)
		if(islist(entry))
			. += ladder_flatten_declaration(entry)
		else if(!isnull(entry))
			. += entry
	var/list/seen = list()
	for(var/entry in .)
		if(!istype(entry, /datum/ladder_stage))
			continue
		var/datum/ladder_stage/S = entry
		var/count = ++seen["[S.name]"]
		if(count > 1)
			S.name = "[S.name] [count]"
