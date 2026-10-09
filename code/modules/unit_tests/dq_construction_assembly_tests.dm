// Vehicle and secbot assembly construction ladders (roadmap I5): each ladder walks forward, one stage at a time, from its start to the finished
// product, with the same items, tools and amounts as the old graphs. These assemblies are forward-only: no stage has a way back.
//
// Inputs are public: a click by a person holding the item or tool (p2_door_click through the input inbox), then time passes. State is read from the
// ladder (graph_current(), built()) and from what stands on the floor afterwards.

/// A person next to the test floor, kept awake by a controller.
/datum/unit_test/proc/dq_asm_person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/controller = allocate(/mob/living/simple_mob/e0_fixture, T)
	rel_set(H, nameof(H.teleop), controller)
	return H

/// A zero-speed tool of `path` on `T`.
/datum/unit_test/proc/dq_asm_tool(path, turf/T)
	var/obj/item/tool = allocate(path, T)
	tool.toolspeed = 0
	return tool

/// A lit welder with plenty of fuel.
/datum/unit_test/proc/dq_asm_welder(turf/T)
	var/obj/item/weldingtool/welder = dq_asm_tool(/obj/item/weldingtool, T)
	welder.reagents.add_reagent(REAGENT_ID_FUEL, welder.max_fuel)
	welder.setWelding(TRUE)
	return welder

/// `H` uses `held` on `target`, time passes.
/datum/unit_test/proc/dq_asm_click(mob/living/carbon/human/H, atom/target, obj/item/held)
	p2_door_click(H, target, held)
	p2_door_settle()

/// `H` uses `held` on `target` and the ladder of `target` is at `stage` afterwards.
/datum/unit_test/proc/dq_asm_step(mob/living/carbon/human/H, atom/target, obj/item/held, stage, what)
	dq_asm_click(H, target, held)
	TEST_ASSERT_EQUAL(graph_current(target), stage, "[what]: the ladder is at [stage_key(stage)] (it is at [stage_key(graph_current(target))])")

// ---- Quadbike ----

/// The quadbike assembly walks tires -> lights -> controls -> wire -> power -> motor -> reinforce -> finish.
/datum/unit_test/dq_construction_quadbike

/datum/unit_test/dq_construction_quadbike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/quadbike/assembly = allocate(/obj/item/vehicle_assembly/quadbike, T)
	TEST_ASSERT_EQUAL(graph_current(assembly), STAGE_QUADBIKE_FRAME, "starts at the bare frame")

	var/obj/item/stack/material/plastic/plastic = allocate(/obj/item/stack/material/plastic, T, 8)
	dq_asm_step(H, assembly, plastic, STAGE_QUADBIKE_WHEELED, "tires")
	TEST_ASSERT_EQUAL(plastic.get_amount(), 0, "all eight plastic sheets were used")

	var/obj/item/stock_parts/console_screen/screen = allocate(/obj/item/stock_parts/console_screen, T)
	dq_asm_step(H, assembly, screen, STAGE_QUADBIKE_LIT, "lights")
	TEST_ASSERT(QDELETED(screen), "the console screen is consumed")

	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/spring, T), STAGE_QUADBIKE_CONTROLLED, "controls")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	dq_asm_step(H, assembly, coil, STAGE_QUADBIKE_WIRED, "wire")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	dq_asm_step(H, assembly, cell, STAGE_QUADBIKE_POWERED, "power")
	TEST_ASSERT_EQUAL(assembly.cell(), cell, "the cell is stored on the assembly")
	TEST_ASSERT_EQUAL(cell.loc, assembly, "the cell moved onto the assembly")

	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/motor, T), STAGE_QUADBIKE_MOTORED, "motor")

	var/obj/item/stack/material/plasteel/plasteel = allocate(/obj/item/stack/material/plasteel, T, 2)
	dq_asm_step(H, assembly, plasteel, STAGE_QUADBIKE_REINFORCED, "reinforcement")
	TEST_ASSERT_EQUAL(plasteel.get_amount(), 0, "both plasteel sheets were used")

	dq_asm_click(H, assembly, dq_asm_tool(/obj/item/tool/wrench, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/train/engine/quadbike/built/product = own(locate_on(T, /obj/vehicle/train/engine/quadbike/built))
	TEST_ASSERT(product, "the finished quadbike is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")
	TEST_ASSERT_EQUAL(cell.loc, product, "the cell physically moved to the product")

/// At the lights stage, five sheets of steel convert a quadbike straight into a framed trailer.
/datum/unit_test/dq_construction_quadbike_to_trailer

/datum/unit_test/dq_construction_quadbike_to_trailer/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/quadbike/assembly = allocate(/obj/item/vehicle_assembly/quadbike, T)
	graph_place(assembly, STAGE_QUADBIKE_LIT)

	var/obj/item/stack/material/steel/steel = allocate(/obj/item/stack/material/steel, T, 5)
	dq_asm_click(H, assembly, steel)
	TEST_ASSERT_EQUAL(steel.get_amount(), 0, "all five steel sheets were used")
	TEST_ASSERT(QDELETED(assembly), "the quadbike assembly is gone")
	var/obj/item/vehicle_assembly/quadtrailer/trailer = own(locate_on(T, /obj/item/vehicle_assembly/quadtrailer))
	TEST_ASSERT(trailer, "a trailer assembly appears")
	TEST_ASSERT_EQUAL(graph_current(trailer), STAGE_QUADTRAILER_FRAMED, "the trailer starts framed")

// ---- Quadtrailer ----

/// The quadtrailer assembly is framed from a spare quadbike frame, wired, then closed up.
/datum/unit_test/dq_construction_quadtrailer

/datum/unit_test/dq_construction_quadtrailer/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = allocate(/obj/item/vehicle_assembly/quadtrailer, T)
	TEST_ASSERT_EQUAL(graph_current(trailer), STAGE_QUADTRAILER_FRAME, "starts at the bare trailer")

	var/obj/item/vehicle_assembly/quadbike/spare = allocate(/obj/item/vehicle_assembly/quadbike, T)
	dq_asm_step(H, trailer, spare, STAGE_QUADTRAILER_FRAMED, "framing from a spare quadbike")
	TEST_ASSERT(QDELETED(spare), "the spare quadbike frame is consumed")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	dq_asm_step(H, trailer, coil, STAGE_QUADTRAILER_WIRED, "wire")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	dq_asm_click(H, trailer, dq_asm_tool(/obj/item/tool/screwdriver, T))
	TEST_ASSERT(QDELETED(trailer), "the trailer assembly is gone")
	TEST_ASSERT(own(locate_on(T, /obj/vehicle/train/trolley/trailer)), "the finished trailer is on the turf")

/// A quadbike too advanced (its control system in) can't be turned into a trailer frame.
/datum/unit_test/dq_construction_quadtrailer_rejects_advanced_quadbike

/datum/unit_test/dq_construction_quadtrailer_rejects_advanced_quadbike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/quadtrailer/trailer = allocate(/obj/item/vehicle_assembly/quadtrailer, T)
	var/obj/item/vehicle_assembly/quadbike/advanced = allocate(/obj/item/vehicle_assembly/quadbike, T)
	graph_place(advanced, STAGE_QUADBIKE_CONTROLLED)
	dq_asm_click(H, trailer, advanced)
	TEST_ASSERT_EQUAL(graph_current(trailer), STAGE_QUADTRAILER_FRAME, "the trailer stays bare")
	TEST_ASSERT(!QDELETED(advanced), "the advanced quadbike is not consumed")

// ---- Spacebike ----

/// The spacebike assembly walks jetpack -> wire -> seat -> lights -> controls -> power -> finish.
/datum/unit_test/dq_construction_spacebike

/datum/unit_test/dq_construction_spacebike/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/spacebike/assembly = allocate(/obj/item/vehicle_assembly/spacebike, T)

	dq_asm_step(H, assembly, allocate(/obj/item/tank/jetpack, T), STAGE_SPACEBIKE_JETPACKED, "jetpack")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 2)
	dq_asm_step(H, assembly, coil, STAGE_SPACEBIKE_WIRED, "wire")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "both cable coils were used")

	var/obj/item/stack/material/plastic/plastic = allocate(/obj/item/stack/material/plastic, T, 3)
	dq_asm_step(H, assembly, plastic, STAGE_SPACEBIKE_SEATED, "seat")
	TEST_ASSERT_EQUAL(plastic.get_amount(), 0, "all three plastic sheets were used")

	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/console_screen, T), STAGE_SPACEBIKE_LIT, "lights")
	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/spring, T), STAGE_SPACEBIKE_CONTROLLED, "controls")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	dq_asm_step(H, assembly, cell, STAGE_SPACEBIKE_POWERED, "power")
	TEST_ASSERT_EQUAL(assembly.cell(), cell, "the cell is stored on the assembly")

	dq_asm_click(H, assembly, dq_asm_tool(/obj/item/tool/screwdriver, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/bike/built/product = own(locate_on(T, /obj/vehicle/bike/built))
	TEST_ASSERT(product, "the finished bike is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")

// ---- Snowmobile ----

/// The snowmobile assembly walks treads -> lights -> controls -> wire -> power -> motor -> reinforce -> finish.
/datum/unit_test/dq_construction_snowmobile

/datum/unit_test/dq_construction_snowmobile/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/vehicle_assembly/snowmobile/assembly = allocate(/obj/item/vehicle_assembly/snowmobile, T)

	var/obj/item/stack/material/steel/steel = allocate(/obj/item/stack/material/steel, T, 6)
	dq_asm_step(H, assembly, steel, STAGE_SNOWMOBILE_TRACKED, "treads")
	TEST_ASSERT_EQUAL(steel.get_amount(), 0, "all six steel sheets were used")

	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/console_screen, T), STAGE_SNOWMOBILE_LIT, "lights")
	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/spring, T), STAGE_SNOWMOBILE_CONTROLLED, "controls")
	dq_asm_step(H, assembly, allocate(/obj/item/stack/cable_coil, T, 2), STAGE_SNOWMOBILE_WIRED, "wire")

	var/obj/item/cell/cell = allocate(/obj/item/cell, T)
	dq_asm_step(H, assembly, cell, STAGE_SNOWMOBILE_POWERED, "power")
	dq_asm_step(H, assembly, allocate(/obj/item/stock_parts/motor, T), STAGE_SNOWMOBILE_MOTORED, "motor")

	var/obj/item/stack/material/plasteel/plasteel = allocate(/obj/item/stack/material/plasteel, T, 2)
	dq_asm_step(H, assembly, plasteel, STAGE_SNOWMOBILE_REINFORCED, "reinforcement")
	TEST_ASSERT_EQUAL(plasteel.get_amount(), 0, "both plasteel sheets were used")

	dq_asm_click(H, assembly, dq_asm_tool(/obj/item/tool/screwdriver, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/obj/vehicle/train/engine/quadbike/snowmobile/built/product = own(locate_on(T, /obj/vehicle/train/engine/quadbike/snowmobile/built))
	TEST_ASSERT(product, "the finished snowmobile is on the turf")
	TEST_ASSERT_EQUAL(product.cell, cell, "the cell moved to the product")

// ---- Secbot (helmet/signaler) assembly ----

/// The secbot assembly welds a hole, adds a prox sensor, a robot arm, then a baton.
/datum/unit_test/dq_construction_secbot_assembly

/datum/unit_test/dq_construction_secbot_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/assembly = allocate(/obj/item/secbot_assembly, T)
	TEST_ASSERT_EQUAL(graph_current(assembly), STAGE_SECBOT_HELMET, "starts at the helmet")

	dq_asm_step(H, assembly, dq_asm_welder(T), STAGE_SECBOT_HOLED, "welding the hole")

	var/obj/item/assembly/prox_sensor/prox = allocate(/obj/item/assembly/prox_sensor, T)
	dq_asm_step(H, assembly, prox, STAGE_SECBOT_SENSING, "the prox sensor")
	TEST_ASSERT(QDELETED(prox), "the prox sensor is consumed")

	dq_asm_step(H, assembly, allocate(/obj/item/robot_parts/l_arm, T), STAGE_SECBOT_ARMED, "the robot arm")

	assembly.created_name = "Test Securitron"
	dq_asm_click(H, assembly, allocate(/obj/item/melee/baton, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/bot = own(locate_on(T, /mob/living/bot/secbot))
	TEST_ASSERT(bot, "the finished Securitron is on the turf")
	TEST_ASSERT(!istype(bot, /mob/living/bot/secbot/slime), "a plain baton makes a plain secbot")
	TEST_ASSERT_EQUAL(bot.name, "Test Securitron", "the custom name carried over")

/// A slime baton on the last step makes a slime secbot instead.
/datum/unit_test/dq_construction_secbot_assembly_slime_baton

/datum/unit_test/dq_construction_secbot_assembly_slime_baton/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/assembly = allocate(/obj/item/secbot_assembly, T)
	graph_place(assembly, STAGE_SECBOT_ARMED)

	dq_asm_click(H, assembly, allocate(/obj/item/melee/baton/slime, T))
	var/mob/living/bot/secbot/slime/bot = own(locate_on(T, /mob/living/bot/secbot/slime))
	TEST_ASSERT(bot, "a slime secbot is on the turf")

// ---- ED-209 assembly ----

/// The ED-209 assembly walks two robot legs, a vest, welding, a helmet, a prox sensor, wiring, a taser, attaching the gun and a cell.
/datum/unit_test/dq_construction_ed209_assembly

/datum/unit_test/dq_construction_ed209_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly, T)
	assembly.created_name = "Test ED-209"

	dq_asm_step(H, assembly, allocate(/obj/item/robot_parts/l_leg, T), STAGE_BOT_FRAME_ONE_LEG, "the first leg")
	TEST_ASSERT_EQUAL(assembly.icon_state, "ed209_leg", "one leg on")
	dq_asm_step(H, assembly, allocate(/obj/item/robot_parts/r_leg, T), STAGE_BOT_FRAME_TWO_LEGS, "the second leg")
	TEST_ASSERT_EQUAL(assembly.icon_state, "ed209_legs", "two legs on")

	dq_asm_step(H, assembly, allocate(/obj/item/clothing/suit/storage/vest, T), STAGE_ED209_ARMOURED, "the vest")
	dq_asm_step(H, assembly, dq_asm_welder(T), STAGE_ED209_SHIELDED, "welding the vest")
	dq_asm_step(H, assembly, allocate(/obj/item/clothing/head/helmet, T), STAGE_ED209_HELMETED, "the helmet")
	dq_asm_step(H, assembly, allocate(/obj/item/assembly/prox_sensor, T), STAGE_ED209_SENSING, "the prox sensor")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 1)
	dq_asm_step(H, assembly, coil, STAGE_ED209_WIRED, "wire")
	TEST_ASSERT_EQUAL(coil.get_amount(), 0, "the cable coil was used")

	dq_asm_step(H, assembly, allocate(/obj/item/gun/energy/taser, T), STAGE_ED209_TASERED, "the taser")
	dq_asm_step(H, assembly, dq_asm_tool(/obj/item/tool/screwdriver, T), STAGE_ED209_ARMED, "attaching the gun")

	dq_asm_click(H, assembly, allocate(/obj/item/cell, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/ed209/bot = own(locate_on(T, /mob/living/bot/secbot/ed209))
	TEST_ASSERT(bot, "the finished ED-209 is on the turf")
	TEST_ASSERT(!istype(bot, /mob/living/bot/secbot/ed209/slime), "a plain taser makes a plain ED-209")
	TEST_ASSERT_EQUAL(bot.name, "Test ED-209", "the custom name carried over")

/// A xenotaser on the wired ED-209 swaps the assembly for the SL-ED-209 kind instead of arming it directly.
/datum/unit_test/dq_construction_ed209_assembly_xeno_taser_swap

/datum/unit_test/dq_construction_ed209_assembly_xeno_taser_swap/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/ed209_assembly/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly, T)
	graph_place(assembly, STAGE_ED209_WIRED)
	assembly.created_name = "Test SL-ED-209"

	dq_asm_click(H, assembly, allocate(/obj/item/gun/energy/taser/xeno, T))
	TEST_ASSERT(QDELETED(assembly), "the ED-209 assembly is gone")
	var/obj/item/secbot_assembly/ed209_assembly/slime/slime_assembly = own(locate_on(T, /obj/item/secbot_assembly/ed209_assembly/slime))
	TEST_ASSERT(slime_assembly, "a slime assembly appears")
	TEST_ASSERT_EQUAL(graph_current(slime_assembly), STAGE_ED209_TASERED, "the slime assembly picks up at the gun stage")
	TEST_ASSERT_EQUAL(slime_assembly.created_name, "Test SL-ED-209", "the custom name carried over")

// ---- SL-ED-209 assembly (standalone) ----

/// A directly-placed SL-ED-209 assembly (e.g. in a PoI) walks the same steps on its own ladder, taking only a xenotaser at the taser step.
/datum/unit_test/dq_construction_sled209_assembly

/datum/unit_test/dq_construction_sled209_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/ed209_assembly/slime/assembly = allocate(/obj/item/secbot_assembly/ed209_assembly/slime, T)
	graph_place(assembly, STAGE_ED209_SENSING)
	assembly.created_name = "Test Standalone SL-ED-209"

	dq_asm_step(H, assembly, allocate(/obj/item/stack/cable_coil, T, 1), STAGE_ED209_WIRED, "wire")

	var/obj/item/gun/energy/taser/plain_taser = allocate(/obj/item/gun/energy/taser, T)
	dq_asm_click(H, assembly, plain_taser)
	TEST_ASSERT_EQUAL(graph_current(assembly), STAGE_ED209_WIRED, "a plain taser doesn't fit the slime assembly")
	TEST_ASSERT(!QDELETED(plain_taser), "the plain taser is not consumed")

	dq_asm_step(H, assembly, allocate(/obj/item/gun/energy/taser/xeno, T), STAGE_ED209_TASERED, "the xenotaser")
	dq_asm_step(H, assembly, dq_asm_tool(/obj/item/tool/screwdriver, T), STAGE_ED209_ARMED, "attaching the gun")

	dq_asm_click(H, assembly, allocate(/obj/item/cell, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/secbot/ed209/slime/bot = own(locate_on(T, /mob/living/bot/secbot/ed209/slime))
	TEST_ASSERT(bot, "the finished SL-ED-209 is on the turf")

// ---- ED-CLN assembly ----

/// The ED-CLN assembly walks two robot legs, a bucket, welding, a prox sensor, wiring, a mop, attaching the mop and a cell.
/datum/unit_test/dq_construction_edCLN_assembly

/datum/unit_test/dq_construction_edCLN_assembly/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = dq_asm_person(T)
	var/obj/item/secbot_assembly/edCLN_assembly/assembly = allocate(/obj/item/secbot_assembly/edCLN_assembly, T)
	assembly.created_name = "Test ED-CLN"

	dq_asm_step(H, assembly, allocate(/obj/item/robot_parts/l_leg, T), STAGE_BOT_FRAME_ONE_LEG, "the first leg")
	dq_asm_step(H, assembly, allocate(/obj/item/robot_parts/r_leg, T), STAGE_BOT_FRAME_TWO_LEGS, "the second leg")
	dq_asm_step(H, assembly, allocate(/obj/item/reagent_containers/glass/bucket, T), STAGE_EDCLN_BUCKETED, "the bucket")
	dq_asm_step(H, assembly, dq_asm_welder(T), STAGE_EDCLN_WELDED, "welding the bucket")
	dq_asm_step(H, assembly, allocate(/obj/item/assembly/prox_sensor, T), STAGE_EDCLN_SENSING, "the prox sensor")

	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 1)
	dq_asm_step(H, assembly, coil, STAGE_EDCLN_WIRED, "wire")
	dq_asm_step(H, assembly, allocate(/obj/item/mop, T), STAGE_EDCLN_MOPED, "the mop")
	dq_asm_step(H, assembly, dq_asm_tool(/obj/item/tool/screwdriver, T), STAGE_EDCLN_ATTACHED, "attaching the mop")

	dq_asm_click(H, assembly, allocate(/obj/item/cell, T))
	TEST_ASSERT(QDELETED(assembly), "the assembly is gone")
	var/mob/living/bot/cleanbot/edCLN/bot = own(locate_on(T, /mob/living/bot/cleanbot/edCLN))
	TEST_ASSERT(bot, "the finished ED-CLN is on the turf")
	TEST_ASSERT_EQUAL(bot.name, "Test ED-CLN", "the custom name carried over")
