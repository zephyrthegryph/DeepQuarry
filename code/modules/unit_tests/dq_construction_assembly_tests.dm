// Vehicle and secbot assembly construction graphs (roadmap I5): each graph walks
// forward, one edge at a time, from its initial state to the finished product,
// with the same items/tools/amounts/durations as the old focused_tool_stage
// attackby ladders. These assemblies are forward-only: no edge ever leads back
// to an earlier state.

/// No assembly graph has an edge that leads to a numerically earlier state
/// (or back into a non-final state once done): construction only goes forward.
/datum/unit_test/dq_construction_assembly_forward_only

/datum/unit_test/dq_construction_assembly_forward_only/Run()
	var/list/assembly_graph_ids = list("quadbike", "quadtrailer", "spacebike", "snowmobile", "secbot_assembly", "ed209_assembly", "ed209_assembly_slime", "edCLN_assembly")
	var/list/checked = list()
	for(var/path in GLOB.construction_graphs)
		var/datum/construction_graph/graph = GLOB.construction_graphs[path]
		if(!(graph.id in assembly_graph_ids))
			continue
		checked += graph.id
		for(var/datum/interaction/construction/edge as anything in graph.edges)
			if(edge.to_state == CONSTRUCTION_DONE)
				continue
			TEST_ASSERT(isnum(edge.from_state) && isnum(edge.to_state), "[edge.id]: numeric states")
			TEST_ASSERT(edge.to_state > edge.from_state, "[edge.id]: [edge.from_state] -> [edge.to_state] moves forward")
	TEST_ASSERT_EQUAL(length(checked), length(assembly_graph_ids), "every assembly graph was found: [jointext(checked, ", ")]")

// ---- Quadbike ----

/// The quadbike assembly walks tires -> lights -> controls -> wire -> power -> motor -> reinforce -> finish.
/datum/unit_test/dq_construction_quadbike

/datum/unit_test/dq_construction_quadbike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/quadbike/assembly = allocate(/obj/item/vehicle_assembly/quadbike, T)
	TEST_ASSERT_EQUAL(assembly.build_stage, 0, "starts at stage 0")

	var/obj/item/stack/material/plastic/plastic = allocate(/obj/item/stack/material/plastic, T, 8)
	var/datum/interaction/construction/tires = dq_edge(assembly, "0>1")
	TEST_ASSERT(tires, "a tires edge leaves stage 0")
	TEST_ASSERT(dq_walk(H, assembly, tires, plastic), "adding tires succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 1, "stage 0 -> 1")
	TEST_ASSERT_EQUAL(plastic.get_amount(), 0, "all eight plastic sheets were used")

	var/obj/item/stock_parts/console_screen/screen = allocate(/obj/item/stock_parts/console_screen, T)
	var/datum/interaction/construction/lights = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, lights, screen), "adding lights succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 2, "stage 1 -> 2")
	TEST_ASSERT(QDELETED(screen), "the console screen is consumed")

	var/obj/item/stock_parts/spring/spring = allocate(/obj/item/stock_parts/spring, T)
	var/datum/interaction/construction/controls = dq_edge(assembly, "2>3:spring")
	TEST_ASSERT(dq_walk(H, assembly, controls, spring), "adding controls succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 3, "stage 2 -> 3")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	var/datum/interaction/construction/wire = dq_edge(assembly, "3>4")
	TEST_ASSERT(dq_walk(H, assembly, wire, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 4, "stage 3 -> 4")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/power = dq_edge(assembly, "4>5")
	TEST_ASSERT(dq_walk(H, assembly, power, cell), "adding the cell succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 5, "stage 4 -> 5")
	TEST_ASSERT_EQUAL(assembly.cell, cell, "the cell is stored on the assembly")
	TEST_ASSERT_EQUAL(cell.loc, assembly, "the cell moved onto the assembly")

	var/obj/item/stock_parts/motor/motor = allocate(/obj/item/stock_parts/motor, T)
	var/datum/interaction/construction/motor_edge = dq_edge(assembly, "5>6")
	TEST_ASSERT(dq_walk(H, assembly, motor_edge, motor), "adding the motor succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 6, "stage 5 -> 6")

	var/obj/item/stack/material/plasteel/plasteel = allocate(/obj/item/stack/material/plasteel, T, 2)
	var/datum/interaction/construction/reinforce = dq_edge(assembly, "6>7")
	TEST_ASSERT(dq_walk(H, assembly, reinforce, plasteel), "reinforcing succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 7, "stage 6 -> 7")
	TEST_ASSERT_EQUAL(plasteel.get_amount(), 0, "both plasteel sheets were used")

	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/datum/interaction/construction/finish = dq_edge(assembly, "7>done:wrench")
	TEST_ASSERT(finish, "a finishing edge leaves stage 7")
	TEST_ASSERT(dq_walk(H, assembly, finish, wrench), "finishing succeeds")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/train/engine/quadbike/built/product = locate() in T
	TEST_ASSERT(product, "the finished quadbike is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")
	TEST_ASSERT_EQUAL(cell.loc, product, "the cell physically moved to the product")

/// At stage 2, five sheets of steel convert a quadbike straight into a framed trailer.
/datum/unit_test/dq_construction_quadbike_to_trailer

/datum/unit_test/dq_construction_quadbike_to_trailer/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/quadbike/assembly = allocate(/obj/item/vehicle_assembly/quadbike, T)
	assembly.build_stage = 2

	var/obj/item/stack/material/steel/steel = allocate(/obj/item/stack/material/steel, T, 5)
	var/datum/interaction/construction/to_trailer = dq_edge(assembly, "2>done:steel")
	TEST_ASSERT(to_trailer, "a trailer-conversion edge leaves stage 2")
	TEST_ASSERT(dq_walk(H, assembly, to_trailer, steel), "converting to a trailer succeeds")
	TEST_ASSERT_EQUAL(steel.get_amount(), 0, "all five steel sheets were used")
	TEST_ASSERT(QDELETED(assembly), "the quadbike assembly is gone")
	var/obj/item/vehicle_assembly/quadtrailer/trailer = locate() in T
	TEST_ASSERT(trailer, "a trailer assembly appears")
	TEST_ASSERT_EQUAL(trailer.build_stage, 1, "the trailer starts framed (stage 1)")

// ---- Quadtrailer ----

/// The quadtrailer assembly is framed from a spare quadbike frame, wired, then closed up.
/datum/unit_test/dq_construction_quadtrailer

/datum/unit_test/dq_construction_quadtrailer/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = allocate(/obj/item/vehicle_assembly/quadtrailer, T)
	TEST_ASSERT_EQUAL(trailer.build_stage, 0, "starts at stage 0")

	var/obj/item/vehicle_assembly/quadbike/spare = allocate(/obj/item/vehicle_assembly/quadbike, T)
	var/datum/interaction/construction/frame = dq_edge(trailer, "0>1")
	TEST_ASSERT(dq_walk(H, trailer, frame, spare), "framing from a spare quadbike succeeds")
	TEST_ASSERT_EQUAL(trailer.build_stage, 1, "stage 0 -> 1")
	TEST_ASSERT(QDELETED(spare), "the spare quadbike frame is consumed")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	var/datum/interaction/construction/wire = dq_edge(trailer, "1>2")
	TEST_ASSERT(dq_walk(H, trailer, wire, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(trailer.build_stage, 2, "stage 1 -> 2")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/finish = dq_edge(trailer, "2>done:screwdriver")
	TEST_ASSERT(dq_walk(H, trailer, finish, screwdriver), "closing it up succeeds")
	TEST_ASSERT(QDELETED(trailer), "the trailer assembly is gone")
	TEST_ASSERT(locate(/obj/vehicle/train/trolley/trailer) in T, "the finished trailer is on the turf")

/// A quadbike too advanced (past stage 2) can't be turned into a trailer frame.
/datum/unit_test/dq_construction_quadtrailer_rejects_advanced_quadbike

/datum/unit_test/dq_construction_quadtrailer_rejects_advanced_quadbike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = allocate(/obj/item/vehicle_assembly/quadtrailer, T)
	var/obj/item/vehicle_assembly/quadbike/advanced = allocate(/obj/item/vehicle_assembly/quadbike, T)
	advanced.build_stage = 3
	var/datum/interaction/construction/frame = dq_edge(trailer, "0>1")
	TEST_ASSERT(!dq_walk(H, trailer, frame, advanced), "an advanced quadbike is rejected")
	TEST_ASSERT_EQUAL(trailer.build_stage, 0, "the trailer stays at stage 0")
	TEST_ASSERT(!QDELETED(advanced), "the advanced quadbike is not consumed")

// ---- Spacebike ----

/// The spacebike assembly walks jetpack -> wire -> seat -> lights -> controls -> power -> finish.
/datum/unit_test/dq_construction_spacebike

/datum/unit_test/dq_construction_spacebike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/spacebike/assembly = allocate(/obj/item/vehicle_assembly/spacebike, T)

	var/obj/item/tank/jetpack/jetpack = allocate(/obj/item/tank/jetpack, T)
	var/datum/interaction/construction/jetpack_edge = dq_edge(assembly, "0>1")
	TEST_ASSERT(dq_walk(H, assembly, jetpack_edge, jetpack), "adding a jetpack succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 1, "stage 0 -> 1")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	var/datum/interaction/construction/wire = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, wire, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 2, "stage 1 -> 2")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	var/obj/item/stack/material/plastic/plastic = allocate(/obj/item/stack/material/plastic, T, 3)
	var/datum/interaction/construction/seat = dq_edge(assembly, "2>3")
	TEST_ASSERT(dq_walk(H, assembly, seat, plastic), "adding a seat succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 3, "stage 2 -> 3")
	TEST_ASSERT_EQUAL(plastic.get_amount(), 0, "all three plastic sheets were used")

	var/obj/item/stock_parts/console_screen/screen = allocate(/obj/item/stock_parts/console_screen, T)
	var/datum/interaction/construction/lights = dq_edge(assembly, "3>4")
	TEST_ASSERT(dq_walk(H, assembly, lights, screen), "adding lights succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 4, "stage 3 -> 4")

	var/obj/item/stock_parts/spring/spring = allocate(/obj/item/stock_parts/spring, T)
	var/datum/interaction/construction/controls = dq_edge(assembly, "4>5")
	TEST_ASSERT(dq_walk(H, assembly, controls, spring), "adding controls succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 5, "stage 4 -> 5")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/power = dq_edge(assembly, "5>6")
	TEST_ASSERT(dq_walk(H, assembly, power, cell), "adding the cell succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 6, "stage 5 -> 6")
	TEST_ASSERT_EQUAL(assembly.cell, cell, "the cell is stored on the assembly")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/finish = dq_edge(assembly, "6>done:screwdriver")
	TEST_ASSERT(dq_walk(H, assembly, finish, screwdriver), "finishing succeeds")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/bike/built/product = locate() in T
	TEST_ASSERT(product, "the finished bike is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")

// ---- Snowmobile ----

/// The snowmobile assembly walks treads -> lights -> controls -> wire -> power -> motor -> reinforce -> finish.
/datum/unit_test/dq_construction_snowmobile

/datum/unit_test/dq_construction_snowmobile/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/vehicle_assembly/snowmobile/assembly = allocate(/obj/item/vehicle_assembly/snowmobile, T)

	var/obj/item/stack/material/steel/steel = allocate(/obj/item/stack/material/steel, T, 6)
	var/datum/interaction/construction/treads = dq_edge(assembly, "0>1")
	TEST_ASSERT(dq_walk(H, assembly, treads, steel), "adding treads succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 1, "stage 0 -> 1")
	TEST_ASSERT_EQUAL(steel.get_amount(), 0, "all six steel sheets were used")

	var/obj/item/stock_parts/console_screen/screen = allocate(/obj/item/stock_parts/console_screen, T)
	var/datum/interaction/construction/lights = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, lights, screen), "adding lights succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 2, "stage 1 -> 2")

	var/obj/item/stock_parts/spring/spring = allocate(/obj/item/stock_parts/spring, T)
	var/datum/interaction/construction/controls = dq_edge(assembly, "2>3")
	TEST_ASSERT(dq_walk(H, assembly, controls, spring), "adding controls succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 3, "stage 2 -> 3")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	var/datum/interaction/construction/wire = dq_edge(assembly, "3>4")
	TEST_ASSERT(dq_walk(H, assembly, wire, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 4, "stage 3 -> 4")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/power = dq_edge(assembly, "4>5")
	TEST_ASSERT(dq_walk(H, assembly, power, cell), "adding the cell succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 5, "stage 4 -> 5")

	var/obj/item/stock_parts/motor/motor = allocate(/obj/item/stock_parts/motor, T)
	var/datum/interaction/construction/motor_edge = dq_edge(assembly, "5>6")
	TEST_ASSERT(dq_walk(H, assembly, motor_edge, motor), "adding the motor succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 6, "stage 5 -> 6")

	var/obj/item/stack/material/plasteel/plasteel = allocate(/obj/item/stack/material/plasteel, T, 2)
	var/datum/interaction/construction/reinforce = dq_edge(assembly, "6>7")
	TEST_ASSERT(dq_walk(H, assembly, reinforce, plasteel), "reinforcing succeeds")
	TEST_ASSERT_EQUAL(assembly.build_stage, 7, "stage 6 -> 7")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/finish = dq_edge(assembly, "7>done:screwdriver")
	TEST_ASSERT(dq_walk(H, assembly, finish, screwdriver), "finishing succeeds")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/train/engine/quadbike/snowmobile/built/product = locate() in T
	TEST_ASSERT(product, "the finished snowmobile is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")

// ---- Secbot (helmet/signaler) assembly ----

/// The secbot assembly walds a hole, adds a prox sensor, a robot arm, then a baton.
/datum/unit_test/dq_construction_secbot_assembly

/datum/unit_test/dq_construction_secbot_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/assembly = allocate(/obj/item/secbot_assembly, T)

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/datum/interaction/construction/weld = dq_edge(assembly, "0>1")
	TEST_ASSERT(dq_walk(H, assembly, weld, welder), "welding the hole succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 1, "step 0 -> 1")

	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor, T)
	var/datum/interaction/construction/prox_edge = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, prox_edge, prox), "adding the prox sensor succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 2, "step 1 -> 2")
	TEST_ASSERT(QDELETED(prox), "the prox sensor is consumed")

	var/obj/item/robot_parts/l_arm/arm = allocate(/obj/item/robot_parts/l_arm, T)
	var/datum/interaction/construction/arm_edge = dq_edge(assembly, "2>3")
	TEST_ASSERT(dq_walk(H, assembly, arm_edge, arm), "adding the robot arm succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 3, "step 2 -> 3")

	assembly.created_name = "Test Securitron"
	var/obj/item/melee/baton/baton = allocate(/obj/item/melee/baton, T)
	var/datum/interaction/construction/baton_edge = dq_edge(assembly, "3>done")
	TEST_ASSERT(dq_walk(H, assembly, baton_edge, baton), "attaching the baton finishes it")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/bot = locate() in T
	TEST_ASSERT(bot, "the finished Securitron is on the turf")
	TEST_ASSERT(!istype(bot, /mob/living/bot/secbot/slime), "a plain baton makes a plain secbot")
	TEST_ASSERT_EQUAL(bot.name, "Test Securitron", "the custom name carried over")

/// A slime baton on the last step makes a slime secbot instead.
/datum/unit_test/dq_construction_secbot_assembly_slime_baton

/datum/unit_test/dq_construction_secbot_assembly_slime_baton/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/assembly = allocate(/obj/item/secbot_assembly, T)
	assembly.build_step = 3

	var/obj/item/melee/baton/slime/baton = allocate(/obj/item/melee/baton/slime, T)
	var/datum/interaction/construction/baton_edge = dq_edge(assembly, "3>done")
	TEST_ASSERT(dq_walk(H, assembly, baton_edge, baton), "attaching the slime baton finishes it")
	var/mob/living/bot/secbot/slime/bot = locate() in T
	TEST_ASSERT(bot, "a slime secbot is on the turf")

// ---- ED-209 assembly ----

/// The ED-209 assembly walks two robot legs, a vest, welding, a helmet, a prox
/// sensor, wiring, a taser, attaching the gun and a cell.
/datum/unit_test/dq_construction_ed209_assembly

/datum/unit_test/dq_construction_ed209_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly, T)
	assembly.created_name = "Test ED-209"

	var/obj/item/robot_parts/l_leg/leg1 = allocate(/obj/item/robot_parts/l_leg, T)
	var/datum/interaction/construction/leg0 = dq_edge(assembly, "0>1")
	TEST_ASSERT(dq_walk(H, assembly, leg0, leg1), "the first leg attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 1, "step 0 -> 1")
	TEST_ASSERT_EQUAL(assembly.icon_state, "ed209_leg", "one leg on")

	var/obj/item/robot_parts/r_leg/leg2 = allocate(/obj/item/robot_parts/r_leg, T)
	var/datum/interaction/construction/leg1_edge = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, leg1_edge, leg2), "the second leg attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 2, "step 1 -> 2")
	TEST_ASSERT_EQUAL(assembly.icon_state, "ed209_legs", "two legs on")

	var/obj/item/clothing/suit/storage/vest/vest = allocate(/obj/item/clothing/suit/storage/vest, T)
	var/datum/interaction/construction/vest_edge = dq_edge(assembly, "2>3")
	TEST_ASSERT(dq_walk(H, assembly, vest_edge, vest), "the vest attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 3, "step 2 -> 3")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/datum/interaction/construction/weld_edge = dq_edge(assembly, "3>4")
	TEST_ASSERT(dq_walk(H, assembly, weld_edge, welder), "welding the vest succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 4, "step 3 -> 4")

	var/obj/item/clothing/head/helmet/helmet = allocate(/obj/item/clothing/head/helmet, T)
	var/datum/interaction/construction/helmet_edge = dq_edge(assembly, "4>5")
	TEST_ASSERT(dq_walk(H, assembly, helmet_edge, helmet), "the helmet attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 5, "step 4 -> 5")

	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor, T)
	var/datum/interaction/construction/prox_edge = dq_edge(assembly, "5>6")
	TEST_ASSERT(dq_walk(H, assembly, prox_edge, prox), "the prox sensor attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 6, "step 5 -> 6")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 1)
	var/datum/interaction/construction/wire_edge = dq_edge(assembly, "6>7")
	TEST_ASSERT(dq_walk(H, assembly, wire_edge, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 7, "step 6 -> 7")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "the cable coil was used")

	var/obj/item/gun/energy/taser/taser = allocate(/obj/item/gun/energy/taser, T)
	var/datum/interaction/construction/taser_edge = dq_edge(assembly, "7>8:taser")
	TEST_ASSERT(taser_edge, "a plain-taser edge leaves step 7")
	TEST_ASSERT(dq_walk(H, assembly, taser_edge, taser), "the taser attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 8, "step 7 -> 8")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/attach_edge = dq_edge(assembly, "8>9")
	TEST_ASSERT(dq_walk(H, assembly, attach_edge, screwdriver), "attaching the gun succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 9, "step 8 -> 9")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/finish_edge = dq_edge(assembly, "9>done")
	TEST_ASSERT(dq_walk(H, assembly, finish_edge, cell), "installing the cell finishes it")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/ed209/bot = locate() in T
	TEST_ASSERT(bot, "the finished ED-209 is on the turf")
	TEST_ASSERT(!istype(bot, /mob/living/bot/secbot/ed209/slime), "a plain taser makes a plain ED-209")
	TEST_ASSERT_EQUAL(bot.name, "Test ED-209", "the custom name carried over")

/// A xenotaser at step 7 swaps the assembly for the SL-ED-209 kind instead of arming it directly.
/datum/unit_test/dq_construction_ed209_assembly_xeno_taser_swap

/datum/unit_test/dq_construction_ed209_assembly_xeno_taser_swap/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly, T)
	assembly.build_step = 7
	assembly.created_name = "Test SL-ED-209"

	var/obj/item/gun/energy/taser/xeno/xeno_taser = allocate(/obj/item/gun/energy/taser/xeno, T)
	var/datum/interaction/construction/taser_xeno_edge = dq_edge(assembly, "7>done:xeno")
	TEST_ASSERT(taser_xeno_edge, "a xenotaser edge leaves step 7")
	TEST_ASSERT(dq_walk(H, assembly, taser_xeno_edge, xeno_taser), "the xenotaser swaps the assembly")
	TEST_ASSERT(QDELETED(assembly), "the ED-209 assembly is gone")
	var/obj/item/secbot_assembly/ed209_assembly/slime/slime_assembly = locate() in T
	TEST_ASSERT(slime_assembly, "a slime assembly appears")
	TEST_ASSERT_EQUAL(slime_assembly.build_step, 8, "the slime assembly picks up at step 8")
	TEST_ASSERT_EQUAL(slime_assembly.created_name, "Test SL-ED-209", "the custom name carried over")

// ---- SL-ED-209 assembly (standalone) ----

/// A directly-placed SL-ED-209 assembly (e.g. in a PoI) walks the same steps
/// on its own graph, taking only a xenotaser at the taser step.
/datum/unit_test/dq_construction_sled209_assembly

/datum/unit_test/dq_construction_sled209_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly/slime, T)
	assembly.build_step = 6
	assembly.created_name = "Test Standalone SL-ED-209"

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 1)
	var/datum/interaction/construction/wire_edge = dq_edge(assembly, "6>7")
	TEST_ASSERT(dq_walk(H, assembly, wire_edge, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 7, "step 6 -> 7")

	var/obj/item/gun/energy/taser/plain_taser = allocate(/obj/item/gun/energy/taser, T)
	var/datum/interaction/construction/taser_edge = dq_edge(assembly, "7>8")
	TEST_ASSERT(!dq_edge_for_held(H, assembly, plain_taser), "a plain taser doesn't fit the slime assembly")

	var/obj/item/gun/energy/taser/xeno/xeno_taser = allocate(/obj/item/gun/energy/taser/xeno, T)
	TEST_ASSERT(dq_walk(H, assembly, taser_edge, xeno_taser), "the xenotaser attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 8, "step 7 -> 8")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/attach_edge = dq_edge(assembly, "8>9")
	TEST_ASSERT(dq_walk(H, assembly, attach_edge, screwdriver), "attaching the gun succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 9, "step 8 -> 9")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/finish_edge = dq_edge(assembly, "9>done")
	TEST_ASSERT(dq_walk(H, assembly, finish_edge, cell), "installing the cell finishes it")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/ed209/slime/bot = locate() in T
	TEST_ASSERT(bot, "the finished SL-ED-209 is on the turf")

// ---- ED-CLN assembly ----

/// The ED-CLN assembly walks two robot legs, a bucket, welding, a prox sensor,
/// wiring, a mop, attaching the mop and a cell.
/datum/unit_test/dq_construction_edCLN_assembly

/datum/unit_test/dq_construction_edCLN_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = allocate(/obj/item/secbot_assembly/edCLN_assembly, T)
	assembly.created_name = "Test ED-CLN"

	var/obj/item/robot_parts/l_leg/leg1 = allocate(/obj/item/robot_parts/l_leg, T)
	var/datum/interaction/construction/leg0 = dq_edge(assembly, "0>1")
	TEST_ASSERT(dq_walk(H, assembly, leg0, leg1), "the first leg attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 1, "step 0 -> 1")

	var/obj/item/robot_parts/r_leg/leg2 = allocate(/obj/item/robot_parts/r_leg, T)
	var/datum/interaction/construction/leg1_edge = dq_edge(assembly, "1>2")
	TEST_ASSERT(dq_walk(H, assembly, leg1_edge, leg2), "the second leg attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 2, "step 1 -> 2")

	var/obj/item/reagent_containers/glass/bucket/bucket = allocate(/obj/item/reagent_containers/glass/bucket, T)
	var/datum/interaction/construction/bucket_edge = dq_edge(assembly, "2>3")
	TEST_ASSERT(dq_walk(H, assembly, bucket_edge, bucket), "the bucket attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 3, "step 2 -> 3")

	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/datum/interaction/construction/weld_edge = dq_edge(assembly, "3>4")
	TEST_ASSERT(dq_walk(H, assembly, weld_edge, welder), "welding the bucket succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 4, "step 3 -> 4")

	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor, T)
	var/datum/interaction/construction/prox_edge = dq_edge(assembly, "4>5")
	TEST_ASSERT(dq_walk(H, assembly, prox_edge, prox), "the prox sensor attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 5, "step 4 -> 5")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 1)
	var/datum/interaction/construction/wire_edge = dq_edge(assembly, "5>6")
	TEST_ASSERT(dq_walk(H, assembly, wire_edge, coil), "wiring succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 6, "step 5 -> 6")

	var/obj/item/mop/mop = allocate(/obj/item/mop, T)
	var/datum/interaction/construction/mop_edge = dq_edge(assembly, "6>7")
	TEST_ASSERT(dq_walk(H, assembly, mop_edge, mop), "the mop attaches")
	TEST_ASSERT_EQUAL(assembly.build_step, 7, "step 6 -> 7")

	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/datum/interaction/construction/attach_edge = dq_edge(assembly, "7>8")
	TEST_ASSERT(dq_walk(H, assembly, attach_edge, screwdriver), "attaching the mop succeeds")
	TEST_ASSERT_EQUAL(assembly.build_step, 8, "step 7 -> 8")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	var/datum/interaction/construction/finish_edge = dq_edge(assembly, "8>done")
	TEST_ASSERT(dq_walk(H, assembly, finish_edge, cell), "installing the cell finishes it")
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/cleanbot/edCLN/bot = locate() in T
	TEST_ASSERT(bot, "the finished ED-CLN is on the turf")
	TEST_ASSERT_EQUAL(bot.name, "Test ED-CLN", "the custom name carried over")
