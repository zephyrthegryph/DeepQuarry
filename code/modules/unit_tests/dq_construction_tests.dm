// Taking things apart (walls, floors, girders, windows, exosuit maintenance, wreckage): every step is an op, driven by a click and settled with
// the kernel clock; the tests assert on the state it leaves and on what comes back, not on text.
//
// Helpers for the per-domain files:
//	dq_use(H, target, held)             a click with `held`, then time enough for its longest wait to run out
//	dq_materials_on(turf)               type -> amount of the items lying on a turf

// ---- Helpers ----

/// Type -> amount (stack units, or a count) of the items on `T`.
/proc/dq_materials_on(turf/T)
	. = list()
	for(var/obj/item/thing in turf_contents_of_type(T, /obj/item))
		var/amount = 1
		if(istype(thing, /obj/item/stack))
			var/obj/item/stack/stack = thing
			amount = stack.get_amount()
		.[thing.type] += amount

/// Whether two dq_materials_on() snapshots hold the same types and amounts. DM's list == is a
/// reference comparison (two separately-built lists are never ==, whatever their contents and
/// insertion order), so this checks the assoc contents directly instead.
/proc/dq_materials_equal(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/type in a)
		if(a[type] != b[type])
			return FALSE
	return TRUE

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

/// Clicks `target` with `held` in the actor's hand and lets the longest wait of any step (10 s) run out. The held item is put down after.
/datum/unit_test/proc/dq_use(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.put_in_active_hand(held)
	. = test_click(H, target, held)
	test_time(30 SECONDS)
	H.drop_from_inventory(held)

/// Turns the turf north (or south) of the test floor into a wall of steel (`reinf` the reinforcement, or null) and returns it.
/datum/unit_test/proc/dq_make_wall(turf/T, datum/material/reinf)
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	wall_turf.ChangeTurf(/turf/simulated/wall)
	var/turf/simulated/wall/wall = wall_turf
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	wall.apply_materials(steel, reinf, steel)
	return wall

// ---- Walls ----

/// A reinforced wall walks 6 -> 0 and apart; the reversible steps go back.
/datum/unit_test/dq_construction_wall_reinforced

/datum/unit_test/dq_construction_wall_reinforced/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	var/turf/simulated/wall/wall = dq_make_wall(T, get_material_by_name(MAT_PLASTEEL))
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "a reinforced wall starts at 6")
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	// Forward, one step at a time: the tool and the resulting stage.
	var/list/steps = list(list(cutters, 5), list(screwdriver, 4), list(welder, 3), list(crowbar, 2), list(wrench, 1), list(welder, 0))
	for(var/list/step in steps)
		var/obj/item/tool = step[1]
		var/before = wall.construction_stage
		dq_use(H, wall, tool)
		TEST_ASSERT_EQUAL(wall.construction_stage, step[2], "stage [before] -> [step[2]] with [tool]")

	// Back: 5 -> 6 and 4 -> 5 are the reversible steps.
	wall.set_construction_stage(4)
	dq_use(H, wall, screwdriver)
	TEST_ASSERT_EQUAL(wall.construction_stage, 5, "the screwdriver screws the lines back down")
	dq_use(H, wall, cutters)
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "the wirecutters mend the grille")

	// The last step pries the sheath off: the wall comes down.
	wall.set_construction_stage(0)
	dq_use(H, wall, crowbar)
	TEST_ASSERT(!istype(wall_turf, /turf/simulated/wall), "the wall is gone")
	TEST_ASSERT(locate_on(wall_turf, /obj/structure/girder), "it leaves a girder")
	for(var/atom/movable/thing in turf_contents_of_type(wall_turf, /atom/movable))
		if(!ismob(thing))
			qdel(thing)
	wall_turf.ChangeTurf(old_type)
	test_driver_end()

/// A plain wall is cut apart with a welder, and a plasma cutter does it too.
/datum/unit_test/dq_construction_wall_plain

/datum/unit_test/dq_construction_wall_plain/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	var/turf/simulated/wall/wall = dq_make_wall(T, null)
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/obj/item/pickaxe/plasmacutter/cutter = dq_fast_tool(/obj/item/pickaxe/plasmacutter, T)

	dq_use(H, wall, welder)
	TEST_ASSERT(!istype(wall_turf, /turf/simulated/wall), "the welder cut the wall down")
	for(var/atom/movable/thing in turf_contents_of_type(wall_turf, /atom/movable))
		if(!ismob(thing))
			qdel(thing)
	wall_turf.ChangeTurf(old_type)

	wall = dq_make_wall(T, null)
	dq_use(H, wall, cutter)
	TEST_ASSERT(!istype(wall_turf, /turf/simulated/wall), "a plasma cutter stands in for the welder")
	for(var/atom/movable/thing in turf_contents_of_type(wall_turf, /atom/movable))
		if(!ismob(thing))
			qdel(thing)
	wall_turf.ChangeTurf(old_type)
	test_driver_end()

/// Welder work that is not taking the wall apart comes first: burning rot, then repair, then thermite.
/datum/unit_test/dq_construction_wall_welder_work

/datum/unit_test/dq_construction_wall_welder_work/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/turf/wall_turf = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = wall_turf.type
	var/turf/simulated/wall/wall = dq_make_wall(T, get_material_by_name(MAT_STEEL))
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	var/obj/effect/overlay/wallrot/rot = new(wall)
	dq_use(H, wall, welder)
	TEST_ASSERT(QDELETED(rot), "the rot is burned away first")
	TEST_ASSERT(istype(wall_turf, /turf/simulated/wall), "and the wall is still there")

	wall.take_damage(50)
	dq_use(H, wall, welder)
	TEST_ASSERT_EQUAL(wall.get_integrity(), wall.max_integrity, "a damaged wall is repaired before it is cut")
	TEST_ASSERT_EQUAL(wall.construction_stage, 6, "repairing does not change the stage")

	wall.set_thermite(TRUE)
	H.set_combat_mode(TRUE) // lighting thermite is a hostile act: it is picked in combat mode
	var/datum/op_result/lit = dq_use(H, wall, welder)
	TEST_ASSERT(test_op_committed(lit), "thermite is lit ahead of the cutting steps")
	H.set_combat_mode(FALSE)
	// lighting it melted the wall: the turf is plating now and carries no coating
	wall_turf.ChangeTurf(old_type)
	own_turf_contents(get_step(T, NORTH) || get_step(T, SOUTH)) // the girder the melted wall left
	test_driver_end()

// ---- Floors ----

/// A carpet pries up to plating (returning its tile), damaged plating welds back, and plating cuts through for 5 fuel.
/datum/unit_test/dq_construction_floor

/datum/unit_test/dq_construction_floor/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/turf/simulated/floor/floor = get_step(T, NORTH) || get_step(T, SOUTH)
	var/old_type = floor.type
	floor = floor.ChangeTurf(/turf/simulated/floor)
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)

	floor.install_flooring(get_flooring_data(/datum/decl/flooring/carpet))
	TEST_ASSERT(!floor.is_plating(), "carpeted")
	dq_use(H, floor, crowbar)
	TEST_ASSERT(floor.is_plating(), "the crowbar pries the carpet up")
	TEST_ASSERT(locate_on(floor, /obj/item/stack/tile/carpet), "the carpet comes back as a tile")

	floor.set_broken(TRUE)
	dq_use(H, floor, welder)
	TEST_ASSERT(!floor.broken, "welded smooth")

	var/fuel_before = welder.get_fuel()
	dq_use(H, floor, welder)
	TEST_ASSERT(fuel_before - welder.get_fuel() >= 5, "the plating is cut through, for 5 fuel")
	for(var/obj/item/thing in turf_contents_of_type(floor, /obj/item))
		qdel(thing)
	floor.ChangeTurf(old_type)
	test_driver_end()

// ---- Exosuit maintenance ----

/// Bolts, hatch and cell: each step forward and back, the cell coming out and going back in.
/datum/unit_test/dq_construction_mecha_maintenance

/datum/unit_test/dq_construction_mecha_maintenance/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	mech.state = MECHA_OPERATING
	dq_use(H, mech, wrench)
	TEST_ASSERT_EQUAL(mech.state, MECHA_OPERATING, "an operating exosuit offers no steps")
	if(!mech.cell)
		rel_set(mech, nameof(mech.cell), new /obj/item/cell/high(mech))
	var/obj/item/cell/cell = mech.cell
	mech.state = MECHA_BOLTS_SECURED

	var/list/forward = list(list(wrench, MECHA_PANEL_LOOSE), list(crowbar, MECHA_CELL_OPEN), list(screwdriver, MECHA_CELL_OUT))
	for(var/list/step in forward)
		var/obj/item/tool = step[1]
		dq_use(H, mech, tool)
		TEST_ASSERT_EQUAL(mech.state, step[2], "[tool] -> state [step[2]]")
	TEST_ASSERT_NULL(mech.cell, "the cell is out")
	TEST_ASSERT_EQUAL(cell.loc, mech.loc, "on the floor")

	cell.forceMove(mech)
	rel_set(mech, nameof(mech.cell), cell)
	var/list/back = list(list(screwdriver, MECHA_CELL_OPEN), list(crowbar, MECHA_PANEL_LOOSE), list(wrench, MECHA_BOLTS_SECURED))
	for(var/list/step in back)
		var/obj/item/tool = step[1]
		dq_use(H, mech, tool)
		TEST_ASSERT_EQUAL(mech.state, step[2], "[tool] back -> state [step[2]]")

	mech_body_plan().afflict(mech, MECHA_INT_TEMP_CONTROL)
	dq_use(H, mech, screwdriver)
	TEST_ASSERT(!mech_body_plan().has_affliction(mech, MECHA_INT_TEMP_CONTROL), "the screwdriver fixes temperature control first")
	TEST_ASSERT_EQUAL(mech.state, MECHA_BOLTS_SECURED, "without a step")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	mech.take_damage(20)
	var/before = mech.get_integrity()
	dq_use(H, mech, welder)
	TEST_ASSERT_EQUAL(mech.get_integrity(), min(mech.max_integrity, before + 10), "a weld patches 10")
	H.set_combat_mode(TRUE)
	// combat mode answers with the weld strike, not a repair
	var/before_strike = mech.get_integrity()
	dq_use(H, mech, welder)
	TEST_ASSERT(mech.get_integrity() <= before_strike, "a strike does not weld repairs ([mech.get_integrity()] vs [before_strike])")
	H.set_combat_mode(FALSE)
	for(var/obj/effect/effect/sparks/S in range(1, T))
		own(S)
	test_driver_end()

// ---- Wreckage ----

/// Salvage steps leave the wreck as a wreck and use up its salvage.
/datum/unit_test/dq_construction_wreckage

/datum/unit_test/dq_construction_wreckage/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/effect/decal/mecha_wreckage/ripley/wreck = allocate(/obj/effect/decal/mecha_wreckage/ripley, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/obj/item/stack/rods/loot = allocate(/obj/item/stack/rods, wreck)
	rel_clear(wreck, nameof(wreck.crowbar_salvage))
	rel_add(wreck, nameof(wreck.crowbar_salvage), loot)
	dq_use(H, wreck, crowbar)
	TEST_ASSERT_EQUAL(loot.loc, get_turf(H), "the crowbar pries out what the wreck held")
	var/datum/op_result/nothing = dq_use(H, wreck, crowbar)
	TEST_ASSERT(!test_op_committed(nothing), "nothing left to pry")

	wreck.salvage_num = 3
	for(var/i in 1 to 20)
		dq_use(H, wreck, welder)
	TEST_ASSERT_EQUAL(wreck.salvage_num, 0, "the welder cuts until the salvage runs out")
	TEST_ASSERT(!QDELETED(wreck), "still a wreck")
	own_turf_contents(T) // the salvage
	test_driver_end()

// ---- Girders ----

/// Dislodge and secure, struts off (returning the reinforcement), disassemble.
/datum/unit_test/dq_construction_girder

/datum/unit_test/dq_construction_girder/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)

	dq_use(H, girder, crowbar)
	TEST_ASSERT(!girder.anchored, "dislodged")
	dq_use(H, girder, wrench)
	TEST_ASSERT(girder.anchored, "secured again")

	dq_use(H, girder, screwdriver)
	TEST_ASSERT(girder.reinforcing, "the screwdriver readies it for reinforcing")
	dq_use(H, girder, screwdriver)
	TEST_ASSERT(!girder.reinforcing, "and back")

	girder.reinf_material = get_material_by_name(MAT_STEEL)
	girder.reinforce_girder()
	TEST_ASSERT_EQUAL(girder.state, 2, "reinforced")
	var/list/before = dq_materials_on(T)
	dq_use(H, girder, screwdriver)
	TEST_ASSERT_EQUAL(girder.state, 1, "struts unsecured")
	dq_use(H, girder, cutters)
	TEST_ASSERT_EQUAL(girder.state, 0, "struts removed")
	TEST_ASSERT_NULL(girder.reinf_material, "no reinforcement left")
	var/list/after = dq_materials_on(T)
	TEST_ASSERT(after[/obj/item/stack/material/steel] > before[/obj/item/stack/material/steel], "the reinforcement comes back as sheets")

	dq_use(H, girder, wrench)
	TEST_ASSERT(QDELETED(girder), "disassembled")
	own_turf_contents(T) // the returned sheets
	test_driver_end()

// ---- Windows ----

/// A reinforced window: unfasten, pry out, unscrew, dismantle into its sheet; and each step back.
/datum/unit_test/dq_construction_window

/datum/unit_test/dq_construction_window/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.set_combat_mode(FALSE)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/structure/window/reinforced/window = allocate(/obj/structure/window/reinforced, T)
	TEST_ASSERT(window.anchored && window.state == 2, "mapped: anchored and fastened")

	// the tool, the anchored flag and the frame state each step leaves
	var/list/walk = list(list(screwdriver, TRUE, 1), list(crowbar, TRUE, 0), list(screwdriver, FALSE, 0))
	for(var/list/step in walk)
		dq_use(H, window, step[1])
		TEST_ASSERT_EQUAL(window.anchored, step[2], "[step[1]] -> anchored [step[2]]")
		TEST_ASSERT_EQUAL(window.state, step[3], "[step[1]] -> frame state [step[3]]")
	var/list/back = list(list(screwdriver, TRUE, 0), list(crowbar, TRUE, 1), list(screwdriver, TRUE, 2))
	for(var/list/step in back)
		dq_use(H, window, step[1])
		TEST_ASSERT_EQUAL(window.anchored, step[2], "back [step[1]] -> anchored [step[2]]")
		TEST_ASSERT_EQUAL(window.state, step[3], "back [step[1]] -> frame state [step[3]]")
	for(var/list/step in walk)
		dq_use(H, window, step[1])
	var/turf/where = window.loc
	dq_use(H, window, wrench)
	TEST_ASSERT(QDELETED(window), "dismantled")
	var/obj/item/stack/material/glass/reinforced/sheet = own(locate_on(where, /obj/item/stack/material/glass/reinforced))
	TEST_ASSERT(sheet, "into reinforced glass")
	TEST_ASSERT_EQUAL(sheet?.get_amount(), 1, "one sheet for a border window")

	// weld repair is the window's op: 4 s for 1 fuel, in the help stance
	var/obj/structure/window/basic/plain = allocate(/obj/structure/window/basic, T)
	plain.take_damage(5)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	H.put_in_active_hand(welder)
	var/fuel_before = welder.get_fuel()
	test_click(H, plain, welder)
	test_time(3 SECONDS)
	TEST_ASSERT(plain.get_integrity() < plain.max_integrity, "not yet after 3 s")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(plain.get_integrity(), plain.max_integrity, "the welder repairs a window in 4 s")
	TEST_ASSERT_EQUAL(fuel_before - welder.get_fuel(), 1, "for 1 fuel")
	test_driver_end()

// ---- Machine frames ----

/// A computer frame: anchor, board, screw, wire (5 cable), glass (2), and every step back returning its materials.
/datum/unit_test/dq_construction_frame

/datum/unit_test/dq_construction_frame/Run()
	test_driver_begin()
	defer_cleanup(src, PROC_REF(interim_native_frame_driver_end))
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	H.enable_godmode()
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	var/obj/item/tool/screwdriver/screwdriver = allocate(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = allocate(/obj/item/tool/wirecutters, T)
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T, SOUTH, TRUE, new /datum/frame/frame_types/computer)
	TEST_ASSERT_EQUAL(graph_current(frame), STAGE_MACHINE_FRAME_LOOSE, "a new frame is loose in its actual native graph")
	var/datum/op_result/anchoring = interim_native_frame_begin(frame, H, "construction.build:machine_frame_placed.anchor", wrench)
	TEST_ASSERT_EQUAL(anchoring?.key, "construction.build:machine_frame_placed.anchor", "public menu dispatch resolves the actual anchoring edge")
	TEST_ASSERT_NULL(anchoring?.outcome, "anchoring waits for its actual duration")
	test_time(1 SECOND)
	TEST_ASSERT(!frame.anchored, "one second does not complete the two-second anchoring wait")
	test_time(1 SECOND)
	TEST_ASSERT(test_op_committed(anchoring), "two seconds completes the actual anchoring edge")
	TEST_ASSERT_EQUAL(graph_current(frame), STAGE_MACHINE_FRAME_PLACED, "wrenched down")

	var/obj/item/circuitboard/board = allocate(/obj/item/circuitboard/crew, T)
	TEST_ASSERT(board, "found a computer board")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_board_in.insert_board", board), "the actual compatible board insertion commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_UNFASTENED, "board placed")
	TEST_ASSERT_EQUAL(board.loc, frame, "inside the frame")
	TEST_ASSERT_EQUAL(frame.circuit, board, "the actual relation contains the original inserted board")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_fastened.fasten_board", screwdriver), "the actual board fastening commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "board screwed in")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 10)
	var/datum/op_result/wiring = interim_native_frame_begin(frame, H, "construction.build:machine_frame_wired.wire", coil)
	TEST_ASSERT_NULL(wiring?.outcome, "wiring waits for its real duration")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "wiring remains incomplete after one second")
	TEST_ASSERT_EQUAL(coil.get_amount(), 10, "no cable units are spent before the wait finishes")
	test_time(1 SECOND)
	TEST_ASSERT(test_op_committed(wiring), "wiring commits after its two seconds")
	TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "wired")
	TEST_ASSERT_EQUAL(coil.get_amount(), 5, "for 5 cable")

	var/obj/item/stack/material/glass/glass = allocate(/obj/item/stack/material/glass, T, 5)
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_paneled.add_glass", glass), "the actual glass panel edge commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_PANELED, "paneled")
	TEST_ASSERT_EQUAL(glass.get_amount(), 3, "for 2 glass")

	// Back down, and the actual materials come back through reverse graph operations.
	H.drop_item() // Include the unused glass before later tool swaps change actual hand custody.
	var/list/before = dq_materials_on(T)
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_wired.remove_glass", crowbar), "the actual panel removal commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "glass out")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_fastened.unwire", cutters), "the actual cable removal commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "cables out")
	var/list/after = dq_materials_on(T)
	TEST_ASSERT_EQUAL(after[/obj/item/stack/material/glass] - before[/obj/item/stack/material/glass], 2, "2 glass back")
	TEST_ASSERT_EQUAL(after[/obj/item/stack/cable_coil] - before[/obj/item/stack/cable_coil], 5, "5 cable back")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_board_in.unfasten_board", screwdriver), "the actual board unfastening commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_UNFASTENED, "board unfastened")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_placed.remove_board", crowbar), "the actual board removal commits")
	TEST_ASSERT_EQUAL(frame.state, FRAME_PLACED, "board out")
	TEST_ASSERT_EQUAL(board.loc, frame.loc, "the original board is on the floor")
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_loose.unanchor", wrench), "the actual unanchoring commits")
	TEST_ASSERT_EQUAL(graph_current(frame), STAGE_MACHINE_FRAME_LOOSE, "unfastened from the floor")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	before = dq_materials_on(T)
	TEST_ASSERT(interim_native_frame_step(frame, H, "construction.build:machine_frame_finished.cut_apart", welder), "actual cutting commits")
	TEST_ASSERT(QDELETED(frame), "cut apart")
	after = dq_materials_on(T)
	TEST_ASSERT_EQUAL(after[/obj/item/stack/material/steel] - before[/obj/item/stack/material/steel], 5, "into its 5 sheets")
	own_turf_contents(T)
