// Behaviour pins of the reagent machines (doc/rewrite/reagents.md section 5), written against the legacy interaction datums and kept through
// their conversion to ops: what a click or an alt-click with a held thing does to the machine's slots and counts. The generated pins
// (snapshots/pins/) show the menus; these show the effects.

/// The machine under test, allocated next to the actor.
/datum/unit_test/dq_p2_reagents/proc/rm_machine(type)
	var/obj/machinery/M = allocate(type, run_loc_floor_bottom_left)
	M.set_anchored(TRUE) // wrenched down, as it would be in use
	return M

/// A beaker clicked onto an empty chem master loads it; a second one is refused and stays in hand; a pill bottle loads into its own slot.
/datum/unit_test/dq_p2_reagents/chem_master_loads_a_beaker_and_a_pill_bottle

/datum/unit_test/dq_p2_reagents/chem_master_loads_a_beaker_and_a_pill_bottle/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_master/M = rm_machine(/obj/machinery/chem_master)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, M, B)
	TEST_ASSERT_EQUAL(M.beaker, B, "the beaker is loaded")
	TEST_ASSERT_EQUAL(B.loc, M, "into the machine")
	var/obj/item/reagent_containers/glass/beaker/B2 = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, M, B2)
	TEST_ASSERT_EQUAL(M.beaker, B, "a second beaker does not replace the first")
	TEST_ASSERT_EQUAL(B2.loc, H, "and stays in hand")
	var/obj/item/storage/pill_bottle/P = allocate(/obj/item/storage/pill_bottle, run_loc_floor_bottom_left)
	rc_click(H, M, P)
	TEST_ASSERT_EQUAL(M.loaded_pill_bottle, P, "the pill bottle goes in its slot")
	TEST_ASSERT(M.reagents && M.reagents.maximum_volume == 900, "the buffer holds 900 units")

/// The grinder starts with a large beaker; another beaker clicked on it stays in hand; an alt-click gives the beaker back.
/datum/unit_test/dq_p2_reagents/grinder_beaker_and_alt_click

/datum/unit_test/dq_p2_reagents/grinder_beaker_and_alt_click/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/reagentgrinder/G = rm_machine(/obj/machinery/reagentgrinder)
	var/obj/item/reagent_containers/glass/beaker/large/start = G.beaker
	TEST_ASSERT(istype(start), "it starts with a large beaker")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, G, B)
	TEST_ASSERT_EQUAL(G.beaker, start, "a second beaker is not taken")
	TEST_ASSERT_EQUAL(B.loc, H, "it stays in hand")
	H.drop_item()
	rc_alt_click(H, G, null)
	TEST_ASSERT_NULL(G.beaker, "an alt-click takes the beaker out")
	TEST_ASSERT_EQUAL(start.loc, H, "into the hand")
	H.drop_item()
	rc_click(H, G, B)
	TEST_ASSERT_EQUAL(G.beaker, B, "an empty grinder takes a beaker")

/// A dispenser takes a cartridge into a slot under its label and a beaker as its container.
/datum/unit_test/dq_p2_reagents/dispenser_takes_a_cartridge_and_a_container

/datum/unit_test/dq_p2_reagents/dispenser_takes_a_cartridge_and_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chemical_dispenser/D = rm_machine(/obj/machinery/chemical_dispenser)
	var/obj/item/reagent_containers/chem_disp_cartridge/water/cart = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water, run_loc_floor_bottom_left)
	rc_click(H, D, cart)
	TEST_ASSERT_EQUAL(D.cartridges[cart.label], cart, "the cartridge is in its slot")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, D, B)
	TEST_ASSERT_EQUAL(D.container, B, "the beaker is the container")
	var/obj/item/reagent_containers/glass/beaker/B2 = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, D, B2)
	TEST_ASSERT_EQUAL(D.container, B, "a second one does not replace it")

/// A synthesizer's cartridge slots are behind its panel: with the panel shut a cartridge stays out.
/datum/unit_test/dq_p2_reagents/synthesizer_locks_its_cartridges

/datum/unit_test/dq_p2_reagents/synthesizer_locks_its_cartridges/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chemical_synthesizer/S = rm_machine(/obj/machinery/chemical_synthesizer)
	var/obj/item/reagent_containers/chem_disp_cartridge/water/cart = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water, run_loc_floor_bottom_left)
	cart.setLabel("dq test label")
	rc_click(H, S, cart)
	TEST_ASSERT_NULL(S.cartridges[cart.label], "the panel is locked: the cartridge stays out")
	TEST_ASSERT(istype(S.catalyst, /obj/item/reagent_containers/glass/beaker), "it starts with a catalyst beaker")
	TEST_ASSERT_EQUAL(S.reagents?.maximum_volume, 600, "and a 600 unit vessel")

/// A distillery installs a beaker into its input, then its output slot.
/datum/unit_test/dq_p2_reagents/distillery_installs_beakers

/datum/unit_test/dq_p2_reagents/distillery_installs_beakers/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/portable_atmospherics/powered/reagent_distillery/D = rm_machine(/obj/machinery/portable_atmospherics/powered/reagent_distillery)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, D, B, settle = FALSE)
	test_answer(H, "install input") // the radial asks which slot
	rc_settle()
	TEST_ASSERT_EQUAL(D.InputBeaker, B, "the beaker is installed as the input")
	TEST_ASSERT(istype(D.reagents, /datum/reagents/distilling), "its holder distills")

/// The injector maker racks an empty injector and takes a beaker.
/datum/unit_test/dq_p2_reagents/injector_maker_racks_injectors

/datum/unit_test/dq_p2_reagents/injector_maker_racks_injectors/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/injector_maker/M = rm_machine(/obj/machinery/injector_maker)
	var/obj/item/reagent_containers/hypospray/autoinjector/empty/E = allocate(/obj/item/reagent_containers/hypospray/autoinjector/empty, run_loc_floor_bottom_left)
	rc_click(H, M, E)
	TEST_ASSERT_EQUAL(M.count_small_injector, 1, "the empty injector is racked")
	TEST_ASSERT(QDELETED(E), "and used up")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 5)
	rc_click(H, M, B)
	TEST_ASSERT_EQUAL(M.beaker, B, "the beaker goes in")

/// The alembic takes a potion material, then the base it brews in.
/datum/unit_test/dq_p2_reagents/alembic_takes_material_and_base

/datum/unit_test/dq_p2_reagents/alembic_takes_material_and_base/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/alembic/M = rm_machine(/obj/machinery/alembic)
	var/obj/item/potion_material/blood_ruby/R = allocate(/obj/item/potion_material/blood_ruby, run_loc_floor_bottom_left)
	rc_click(H, M, R)
	TEST_ASSERT_EQUAL(M.potion_reagent, R, "the material is placed")
	var/obj/item/potion_base/ichor/I = allocate(/obj/item/potion_base/ichor, run_loc_floor_bottom_left)
	rc_click(H, M, I)
	TEST_ASSERT_EQUAL(M.base_reagent, I, "the base is placed")

/// A bunsen burner takes a container to heat.
/datum/unit_test/dq_p2_reagents/bunsen_takes_a_container

/datum/unit_test/dq_p2_reagents/bunsen_takes_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/bunsen_burner/M = rm_machine(/obj/machinery/bunsen_burner)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, M, B)
	TEST_ASSERT_EQUAL(M.held_container, B, "the container sits on the burner")
	TEST_ASSERT(istype(M.reagents, /datum/reagents/distilling), "its holder distills")

/// The chem analyzer analyzes a container in two seconds and remembers what was in it.
/datum/unit_test/dq_p2_reagents/chem_analyzer_analyzes_a_container

/datum/unit_test/dq_p2_reagents/chem_analyzer_analyzes_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chemical_analyzer/M = rm_machine(/obj/machinery/chemical_analyzer)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 12)
	rc_click(H, M, B)
	TEST_ASSERT_EQUAL(LAZYACCESS(M.found_reagents, REAGENT_ID_WATER), 12, "the water was found")
