// Construction graphs (roadmap I5): every graph is valid, examine shows the next
// steps, and each converted graph walks its edges forward and back with the
// same tools, times and materials as before.
//
// Helpers for the per-domain walks (dq_construction_*_tests.dm):
//	dq_edge(target, id_suffix)          the edge leaving target's state whose id ends with id_suffix
//	dq_walk(H, target, edge, held)      runs it through perform() with no wait (dq_construction_instant)
//	dq_materials_on(turf)               type -> amount of the items lying on a turf

// ---- Helpers ----

/// Type -> amount (stack units, or a count) of the items on `T`.
/proc/dq_materials_on(turf/T)
	. = list()
	for(var/obj/item/thing in T)
		var/amount = 1
		if(istype(thing, /obj/item/stack))
			var/obj/item/stack/stack = thing
			amount = stack.get_amount()
		.[thing.type] += amount

/// The edge leaving `target`'s current state whose id ends with `suffix` (or equals it). `suffix` may
/// be just the "from>to" transition (e.g. "0>1") or the full "from>to:tool_or_item" tail (e.g.
/// "2>3:spring"): ids are "graph_id:from>to:tool_or_item", so both are checked against the tail.
/datum/unit_test/proc/dq_edge(atom/target, suffix)
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(target))
		var/list/parts = splittext(edge.id, ":")
		var/transition = (length(parts) >= 2) ? parts[2] : null
		var/tail = (length(parts) >= 3) ? "[parts[2]]:[parts[3]]" : transition
		if(edge.id == suffix || transition == suffix || tail == suffix)
			return edge
	return null

/// The edge leaving `target`'s state that `held` would run, by tool or item. Null if none.
/datum/unit_test/proc/dq_edge_for_held(mob/actor, atom/target, obj/item/held)
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(target))
		if(edge.applies_to(target) && !edge.why_not(actor, target, held))
			return edge
	return null

/// Runs `edge` on `target` with no wait. Returns what perform() returned.
/datum/unit_test/proc/dq_walk(mob/actor, atom/target, datum/interaction/construction/edge, obj/item/held)
	GLOB.dq_construction_instant = TRUE
	. = edge.perform(actor, target, held)
	GLOB.dq_construction_instant = FALSE

/// A zero-speed tool of `path` on `T`.
/datum/unit_test/proc/dq_fast_tool(path, turf/T)
	var/obj/item/tool = allocate(path, T)
	tool.toolspeed = 0
	return tool

/// A lit welder with plenty of fuel.
/datum/unit_test/proc/dq_fueled_welder(turf/T)
	var/obj/item/weldingtool/welder = dq_fast_tool(/obj/item/weldingtool, T)
	welder.reagents.add_reagent(REAGENT_ID_FUEL, welder.max_fuel)
	welder.setWelding(TRUE)
	return welder

// ---- Every graph ----

/// Every graph is valid: known states, all reachable, every edge named, every requirement compiles.
/datum/unit_test/dq_construction_graphs_valid

/datum/unit_test/dq_construction_graphs_valid/Run()
	TEST_ASSERT(length(GLOB.construction_graphs), "graphs are registered")
	var/list/seen_ids = list()
	for(var/path in GLOB.construction_graphs)
		var/datum/construction_graph/graph = GLOB.construction_graphs[path]
		TEST_ASSERT(!(graph.id in seen_ids), "graph id [graph.id] is unique")
		seen_ids += graph.id
		var/list/problems = graph.validate()
		TEST_ASSERT(!length(problems), "[graph.id] is valid: [jointext(problems, "; ")]")
		TEST_ASSERT(length(graph.edges), "[graph.id] has edges")
		for(var/datum/interaction/construction/edge as anything in graph.edges)
			TEST_ASSERT_EQUAL(INTERACTION_BY_ID(edge.id), edge, "[edge.id] is found by id")
			TEST_ASSERT(isnull(edge.category) || (edge.category in INTERACTION_CATEGORIES), "[edge.id] has a known category")

/// Every atom type naming a graph names a registered one.
/datum/unit_test/dq_construction_graph_types

/datum/unit_test/dq_construction_graph_types/Run()
	for(var/atom/path as anything in typesof(/atom))
		var/graph_path = initial(path.construction_graph)
		if(!graph_path)
			continue
		TEST_ASSERT(GLOB.construction_graphs[graph_path], "[path] names [graph_path], a registered graph")

/// Examine lists "Next:" lines for the edges leaving the state, with what each needs.
/datum/unit_test/dq_construction_examine_next

/datum/unit_test/dq_construction_examine_next/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	wall.set_material(steel, steel, steel)
	wall.construction_stage = 5
	var/list/lines = construction_examine_lines(H, wall)
	var/text = jointext(lines, "\n")
	TEST_ASSERT(findtext(text, "Next: unscrew the support lines (needs a screwdriver)"), "the screwdriver step: [text]")
	TEST_ASSERT(findtext(text, "Next: mend the outer grille (needs a wirecutter)"), "the step back: [text]")
	TEST_ASSERT_EQUAL(length(lines), 2, "one line per edge leaving stage 5")
	wall_turf.ChangeTurf(old_type)
	TEST_ASSERT_NULL(construction_examine_lines(H, allocate(/obj/item/tool/wrench, T)), "no lines for things without a graph")

// ---- Walls ----

/// A reinforced wall walks 6 -> 0 and apart, with the same tools and times; the reversible steps go back.
/datum/unit_test/dq_construction_wall_reinforced

/datum/unit_test/dq_construction_wall_reinforced/Run()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/datum/material/plasteel = get_material_by_name(MAT_PLASTEEL)
	wall.set_material(steel, plasteel, steel)
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "a reinforced wall starts at 6")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	// Forward, one step at a time: tool, unscaled time, resulting stage.
	var/list/steps = list(
		list(cutters, 0, 5),
		list(screwdriver, 4 SECONDS, 4),
		list(welder, 6 SECONDS, 3),
		list(crowbar, 10 SECONDS, 2),
		list(wrench, 4 SECONDS, 1),
		list(welder, 7 SECONDS, 0),
	)
	for(var/list/step in steps)
		var/obj/item/tool = step[1]
		var/before = wall.construction_stage
		H.put_in_active_hand(tool)
		TEST_ASSERT(wall.tool_interaction(H, tool) & ITEM_INTERACT_SUCCESS, "stage [before]: [tool] runs a step")
		TEST_ASSERT_EQUAL(wall.construction_stage, step[3], "stage [before] -> [step[3]]")
		TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], step[2], "stage [before] takes [step[2]]")
		TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["volume"], 100, "at volume 100")
		H.drop_from_inventory(tool)

	// Back: 5 -> 6 and 4 -> 5 are the reversible steps.
	wall.construction_stage = 4
	H.put_in_active_hand(screwdriver)
	wall.tool_interaction(H, screwdriver)
	TEST_ASSERT_EQUAL(wall.construction_stage, 5, "the screwdriver screws the lines back down")
	H.drop_from_inventory(screwdriver)
	H.put_in_active_hand(cutters)
	wall.tool_interaction(H, cutters)
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "the wirecutters mend the grille")
	H.drop_from_inventory(cutters)

	// The last step pries the sheath off: the wall comes down.
	wall.construction_stage = 0
	H.put_in_active_hand(crowbar)
	wall.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 10 SECONDS, "prying the sheath takes 10 s")
	TEST_ASSERT(!istype(wall_turf, /turf/simulated/wall), "the wall is gone")
	TEST_ASSERT(locate(/obj/structure/girder) in wall_turf, "it leaves a girder")
	for(var/atom/movable/thing in wall_turf)
		if(!ismob(thing))
			qdel(thing)
	wall_turf.ChangeTurf(old_type)

/// A plain wall is cut apart with a welder in 60 - cut_delay, scaled by the tool; a plasma cutter does it too.
/datum/unit_test/dq_construction_wall_plain

/datum/unit_test/dq_construction_wall_plain/Run()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	wall.set_material(steel, null, steel)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	welder.toolspeed = 1

	var/datum/interaction/construction/cut = dq_edge(wall, "plain>done:welder")
	TEST_ASSERT(cut, "a plain wall offers the welder cut")
	TEST_ASSERT_EQUAL(cut.duration_for(H, wall, welder), max(0, 60 - steel.cut_delay), "cutting takes 60 - cut_delay")
	var/obj/item/pickaxe/plasmacutter/cutter = allocate(/obj/item/pickaxe/plasmacutter, T)
	TEST_ASSERT(cut.is_alt_item(cutter), "a plasma cutter stands in for the welder")
	TEST_ASSERT_EQUAL(cut.alt_delay(H, wall, cutter), max(0, 60 - steel.cut_delay - cutter.digspeed), "a plasma cutter takes digspeed off")
	TEST_ASSERT_NULL(cut.why_not(H, wall, cutter), "the plasma cutter's step is available")

	welder.toolspeed = 0
	H.put_in_active_hand(welder)
	wall.tool_interaction(H, welder)
	TEST_ASSERT(!istype(wall_turf, /turf/simulated/wall), "the welder cut the wall down")
	for(var/atom/movable/thing in wall_turf)
		if(!ismob(thing))
			qdel(thing)
	wall_turf.ChangeTurf(old_type)

/// Welder work that isn't construction comes first: burning rot, then thermite, then repair.
/datum/unit_test/dq_construction_wall_welder_work

/datum/unit_test/dq_construction_wall_welder_work/Run()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	wall.set_material(steel, steel, steel)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	H.put_in_active_hand(welder)

	var/obj/effect/overlay/wallrot/rot = new(wall)
	var/datum/interaction_resolution/resolution = interactions_for(H, wall, welder)
	var/list/best = resolution.best_for_action(INPUT_ACTION_USE)
	TEST_ASSERT_EQUAL(best[1], INTERACTION(/datum/interaction/wall_burn_rot), "rot is burned first")
	wall.tool_interaction(H, welder)
	TEST_ASSERT(QDELETED(rot), "the rot is gone")

	wall.take_damage(50)
	resolution = interactions_for(H, wall, welder)
	best = resolution.best_for_action(INPUT_ACTION_USE)
	TEST_ASSERT_EQUAL(best[1], INTERACTION(/datum/interaction/wall_repair), "a damaged wall is repaired before it is cut")
	var/datum/interaction/repair = INTERACTION(/datum/interaction/wall_repair)
	TEST_ASSERT_EQUAL(repair.duration_for(H, wall, welder), 0, "zero-speed welder")
	wall.tool_interaction(H, welder)
	TEST_ASSERT_EQUAL(wall.get_integrity(), wall.max_integrity, "repaired")
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "repairing doesn't change the stage")

	wall.thermite = TRUE
	resolution = interactions_for(H, wall, welder)
	best = resolution.best_for_action(INPUT_ACTION_USE)
	TEST_ASSERT_EQUAL(best[1], INTERACTION(/datum/interaction/wall_light_thermite), "thermite is lit ahead of the graph")
	wall.thermite = FALSE
	wall_turf.ChangeTurf(old_type)

// ---- Floors ----

/// A carpet pries up to plating (returning its tile), damaged plating welds back, and plating cuts through in 10 s for 5 fuel.
/datum/unit_test/dq_construction_floor

/datum/unit_test/dq_construction_floor/Run()
	var/turf/T = test_floor()
	var/turf/simulated/floor/floor = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = floor.type
	floor = floor.ChangeTurf(/turf/simulated/floor)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	floor.set_flooring(get_flooring_data(/datum/decl/flooring/carpet))
	var/datum/construction_graph/graph = construction_graph_of(floor)
	TEST_ASSERT_EQUAL(graph.state_of(floor), "floored", "carpeted")
	H.put_in_active_hand(crowbar)
	floor.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(graph.state_of(floor), "plating", "the crowbar pries the carpet up")
	TEST_ASSERT(locate(/obj/item/stack/tile/carpet) in floor, "the carpet comes back as a tile")
	H.drop_from_inventory(crowbar)

	floor.broken = TRUE
	TEST_ASSERT_EQUAL(graph.state_of(floor), "damaged", "broken plating")
	H.put_in_active_hand(welder)
	floor.tool_interaction(H, welder)
	TEST_ASSERT_EQUAL(graph.state_of(floor), "plating", "welded smooth")

	var/datum/interaction/construction/cut = dq_edge(floor, "plating>done:welder")
	TEST_ASSERT(cut, "plating offers the cut")
	TEST_ASSERT_EQUAL(cut.duration, 10 SECONDS, "cutting takes 10 s")
	TEST_ASSERT(!cut.tool_scaled, "whatever the welder")
	TEST_ASSERT_EQUAL(cut.tool_amount, 5, "and 5 fuel")
	H.drop_from_inventory(welder)
	for(var/obj/item/thing in floor)
		qdel(thing)
	floor.ChangeTurf(old_type)

// ---- Exosuit maintenance ----

/// Bolts, hatch and cell: each step forward and back, the cell coming out and going back in.
/datum/unit_test/dq_construction_mecha_maintenance

/datum/unit_test/dq_construction_mecha_maintenance/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(!length(construction_edges_for(mech)), "an operating exosuit offers no steps")
	if(!mech.cell)
		mech.cell = new /obj/item/cell/high(mech)
	var/obj/item/cell/cell = mech.cell
	mech.state = MECHA_BOLTS_SECURED

	var/list/forward = list(list(wrench, MECHA_PANEL_LOOSE), list(crowbar, MECHA_CELL_OPEN), list(screwdriver, MECHA_CELL_OUT))
	for(var/list/step in forward)
		var/obj/item/tool = step[1]
		H.put_in_active_hand(tool)
		mech.tool_interaction(H, tool)
		TEST_ASSERT_EQUAL(mech.state, step[2], "[tool] -> state [step[2]]")
		H.drop_from_inventory(tool)
	TEST_ASSERT_NULL(mech.cell, "the cell is out")
	TEST_ASSERT_EQUAL(cell.loc, mech.loc, "on the floor")

	cell.forceMove(mech)
	mech.cell = cell
	var/list/back = list(list(screwdriver, MECHA_CELL_OPEN), list(crowbar, MECHA_PANEL_LOOSE), list(wrench, MECHA_BOLTS_SECURED))
	for(var/list/step in back)
		var/obj/item/tool = step[1]
		H.put_in_active_hand(tool)
		mech.tool_interaction(H, tool)
		TEST_ASSERT_EQUAL(mech.state, step[2], "[tool] back -> state [step[2]]")
		H.drop_from_inventory(tool)

	mech.setInternalDamage(MECHA_INT_TEMP_CONTROL)
	H.put_in_active_hand(screwdriver)
	mech.tool_interaction(H, screwdriver)
	TEST_ASSERT(!mech.hasInternalDamage(MECHA_INT_TEMP_CONTROL), "the screwdriver fixes temperature control first")
	TEST_ASSERT_EQUAL(mech.state, MECHA_BOLTS_SECURED, "without a step")
	H.drop_from_inventory(screwdriver)

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	mech.take_damage(20)
	var/before = mech.get_integrity()
	H.set_combat_mode(FALSE)
	H.put_in_active_hand(welder)
	mech.tool_interaction(H, welder)
	TEST_ASSERT_EQUAL(mech.get_integrity(), min(mech.max_integrity, before + 10), "a weld patches 10")
	H.set_combat_mode(TRUE)
	TEST_ASSERT(mech.tool_interaction(H, welder) & ITEM_INTERACT_SKIP_TO_ATTACK, "on harm intent the welder attacks")
	H.set_combat_mode(FALSE)

// ---- Wreckage ----

/// Salvage steps leave the wreck in its one state and use up its salvage.
/datum/unit_test/dq_construction_wreckage

/datum/unit_test/dq_construction_wreckage/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/effect/decal/mecha_wreckage/ripley/wreck = allocate(/obj/effect/decal/mecha_wreckage/ripley, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/obj/item/stack/rods/loot = allocate(/obj/item/stack/rods, wreck)
	wreck.crowbar_salvage = list(loot)
	H.put_in_active_hand(crowbar)
	wreck.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(loot.loc, get_turf(H), "the crowbar pries out what the wreck held")
	H.drop_from_inventory(crowbar)
	var/datum/interaction/construction/pry = dq_edge(wreck, "wreck>wreck:crowbar")
	TEST_ASSERT_EQUAL(pry.why_not(H, wreck, crowbar), "you don't see anything that can be pried out", "nothing left to pry")

	wreck.salvage_num = 3
	H.put_in_active_hand(welder)
	for(var/i in 1 to 20)
		wreck.tool_interaction(H, welder)
	TEST_ASSERT_EQUAL(wreck.salvage_num, 0, "the welder cuts until the salvage runs out")
	var/datum/interaction/construction/cut = dq_edge(wreck, "wreck>wreck:welder")
	TEST_ASSERT(cut.why_not(H, wreck, welder), "and then can't cut any more")
	TEST_ASSERT_EQUAL(construction_graph_of(wreck).state_of(wreck), "wreck", "still a wreck")

// ---- Girders ----

/// Dislodge and secure (4 s each), struts off (4 s + 4 s, returning the reinforcement), disassemble (35 + integrity/50).
/datum/unit_test/dq_construction_girder

/datum/unit_test/dq_construction_girder/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/datum/construction_graph/graph = construction_graph_of(girder)

	girder.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(graph.state_of(girder), "displaced", "dislodged")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 4 SECONDS, "in 4 s")
	girder.tool_interaction(H, wrench)
	TEST_ASSERT_EQUAL(graph.state_of(girder), "anchored", "secured again")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 4 SECONDS, "in 4 s")

	girder.tool_interaction(H, screwdriver)
	TEST_ASSERT(girder.reinforcing, "the screwdriver readies it for reinforcing")
	girder.tool_interaction(H, screwdriver)
	TEST_ASSERT(!girder.reinforcing, "and back")

	girder.reinf_material = get_material_by_name(MAT_STEEL)
	girder.reinforce_girder()
	TEST_ASSERT_EQUAL(graph.state_of(girder), "reinforced", "reinforced")
	var/list/before = dq_materials_on(T)
	girder.tool_interaction(H, screwdriver)
	TEST_ASSERT_EQUAL(graph.state_of(girder), "struts_loose", "struts unsecured")
	girder.tool_interaction(H, cutters)
	TEST_ASSERT_EQUAL(graph.state_of(girder), "anchored", "struts removed")
	TEST_ASSERT_NULL(girder.reinf_material, "no reinforcement left")
	var/list/after = dq_materials_on(T)
	TEST_ASSERT(after[/obj/item/stack/material/steel] > before[/obj/item/stack/material/steel], "the reinforcement comes back as sheets")

	var/expected = 35 + round(girder.max_integrity / 50)
	girder.tool_interaction(H, wrench)
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], expected, "disassembling takes 35 + integrity/50")
	TEST_ASSERT(QDELETED(girder), "disassembled")

// ---- Windows ----

/// A reinforced window: unfasten, pry out, unscrew, dismantle into its sheet; and each step back.
/datum/unit_test/dq_construction_window

/datum/unit_test/dq_construction_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/structure/window/reinforced/window = allocate(/obj/structure/window/reinforced, T)
	var/datum/construction_graph/graph = construction_graph_of(window)
	TEST_ASSERT_EQUAL(graph.state_of(window), "a2", "mapped: anchored and fastened")

	var/list/walk = list(list(screwdriver, "a1"), list(crowbar, "a0"), list(screwdriver, "u0"))
	for(var/list/step in walk)
		window.tool_interaction(H, step[1])
		TEST_ASSERT_EQUAL(graph.state_of(window), step[2], "-> [step[2]]")
	var/list/back = list(list(screwdriver, "a0"), list(crowbar, "a1"), list(screwdriver, "a2"))
	for(var/list/step in back)
		window.tool_interaction(H, step[1])
		TEST_ASSERT_EQUAL(graph.state_of(window), step[2], "back -> [step[2]]")
	for(var/list/step in walk)
		window.tool_interaction(H, step[1])
	var/turf/where = window.loc
	window.tool_interaction(H, wrench)
	TEST_ASSERT(QDELETED(window), "dismantled")
	var/obj/item/stack/material/glass/reinforced/sheet = locate() in where
	TEST_ASSERT(sheet, "into reinforced glass")
	TEST_ASSERT_EQUAL(sheet?.get_amount(), 1, "one sheet for a border window")

	var/obj/structure/window/basic/plain = allocate(/obj/structure/window/basic, T)
	plain.take_damage(5)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	plain.tool_interaction(H, welder)
	TEST_ASSERT_EQUAL(plain.get_integrity(), plain.max_integrity, "the welder repairs a window")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 4 SECONDS, "in 4 s")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["amount"], 1, "for 1 fuel")

// ---- Machine frames ----

/// A computer frame: anchor, board, screw, wire (5 cable), glass (2), and every step back returning its materials.
/datum/unit_test/dq_construction_frame

/datum/unit_test/dq_construction_frame/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T, SOUTH, TRUE, new /datum/frame/frame_types/computer)
	var/datum/construction_graph/graph = construction_graph_of(frame)
	TEST_ASSERT_EQUAL(graph.state_of(frame), "loose", "a new frame is loose")

	frame.tool_interaction(H, wrench)
	TEST_ASSERT_EQUAL(graph.state_of(frame), FRAME_PLACED, "wrenched down")
	TEST_ASSERT_EQUAL(GLOB.dq_tool_last_use["delay"], 2 SECONDS, "in 2 s")

	var/obj/item/circuitboard/board = allocate(/obj/item/circuitboard/crew, T)
	TEST_ASSERT(board, "found a computer board")
	H.put_in_active_hand(board)
	var/datum/interaction/construction/insert = dq_edge_for_held(H, frame, board)
	TEST_ASSERT(insert, "the board goes in")
	dq_walk(H, frame, insert, board)
	TEST_ASSERT_EQUAL(frame.state, FRAME_UNFASTENED, "board placed")
	TEST_ASSERT_EQUAL(board.loc, frame, "inside the frame")
	frame.tool_interaction(H, screwdriver)
	TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "board screwed in")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 10)
	H.put_in_active_hand(coil)
	var/datum/interaction/construction/wire = dq_edge_for_held(H, frame, coil)
	TEST_ASSERT_EQUAL(wire?.duration, 2 SECONDS, "wiring takes 2 s")
	dq_walk(H, frame, wire, coil)
	TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "wired")
	TEST_ASSERT_EQUAL(coil.get_amount(), 5, "for 5 cable")

	var/obj/item/stack/material/glass/glass = allocate(/obj/item/stack/material/glass, T, 5)
	H.put_in_active_hand(glass)
	var/datum/interaction/construction/add_glass = dq_edge_for_held(H, frame, glass)
	dq_walk(H, frame, add_glass, glass)
	TEST_ASSERT_EQUAL(frame.state, FRAME_PANELED, "paneled")
	TEST_ASSERT_EQUAL(glass.get_amount(), 3, "for 2 glass")

	// Back down, and the materials come back.
	var/list/before = dq_materials_on(T)
	frame.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "glass out")
	frame.tool_interaction(H, cutters)
	TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "cables out")
	var/list/after = dq_materials_on(T)
	TEST_ASSERT_EQUAL(after[/obj/item/stack/material/glass] - before[/obj/item/stack/material/glass], 2, "2 glass back")
	TEST_ASSERT_EQUAL(after[/obj/item/stack/cable_coil] - before[/obj/item/stack/cable_coil], 5, "5 cable back")
	frame.tool_interaction(H, screwdriver)
	TEST_ASSERT_EQUAL(frame.state, FRAME_UNFASTENED, "board unfastened")
	frame.tool_interaction(H, crowbar)
	TEST_ASSERT_EQUAL(frame.state, FRAME_PLACED, "board out")
	TEST_ASSERT_EQUAL(board.loc, frame.loc, "on the floor")
	frame.tool_interaction(H, wrench)
	TEST_ASSERT_EQUAL(graph.state_of(frame), "loose", "unfastened from the floor")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	before = dq_materials_on(T)
	frame.tool_interaction(H, welder)
	TEST_ASSERT(QDELETED(frame), "cut apart")
	after = dq_materials_on(T)
	TEST_ASSERT_EQUAL(after[/obj/item/stack/material/steel] - before[/obj/item/stack/material/steel], 5, "into its 5 sheets")
