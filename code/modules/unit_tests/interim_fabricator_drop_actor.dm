/datum/unit_test/interim_fabricator_drop_actor
	abstract_type = /datum/unit_test/interim_fabricator_drop_actor
	var/machine_type

/datum/unit_test/interim_fabricator_drop_actor/production
	machine_type = /obj/machinery/rnd/production/protolathe

/datum/unit_test/interim_fabricator_drop_actor/mech
	machine_type = /obj/machinery/mecha_part_fabricator_tg

/// The drop direction follows a drag of the machine (the fabricator capability's drop_here op): only by someone standing next to it, never a ghost,
/// and never toward the machine's own tile; it never starts printing.
/datum/unit_test/interim_fabricator_drop_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east = get_step(T, EAST)
	var/turf/north = get_step(T, NORTH)
	var/turf/far = get_step(get_step(get_step(T, EAST), EAST), EAST)
	TEST_ASSERT(isfloorturf(east) && isfloorturf(north) && isfloorturf(far), "actual near and distant landing floors exist")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, far)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	ghost.forceMove(T)
	var/obj/machinery/machine = allocate(machine_type, T)
	TEST_ASSERT(!fabricator_printing(machine), "the machine is not printing")
	test_drag(actor, machine, east)
	TEST_ASSERT_EQUAL(machine.vars["drop_direction"], EAST, "a drag selects the east output direction")
	TEST_ASSERT(!machine.Adjacent(bystander) && machine.Adjacent(ghost), "distant human and nearby observer satisfy their distinct refusal preconditions")
	test_drag(bystander, machine, north)
	TEST_ASSERT_EQUAL(machine.vars["drop_direction"], EAST, "a distant actor cannot reorient the machine")
	test_drag(ghost, machine, north)
	TEST_ASSERT_EQUAL(machine.vars["drop_direction"], EAST, "a nearby observer cannot reorient the machine")
	test_drag(actor, machine, T)
	TEST_ASSERT_EQUAL(machine.vars["drop_direction"], EAST, "a zero-vector drop leaves its previous output orientation unchanged")
	test_drag(actor, machine, north)
	TEST_ASSERT_EQUAL(machine.vars["drop_direction"], NORTH, "the same actor can choose another output floor")
	TEST_ASSERT(!fabricator_printing(machine), "orientation never starts printing")
	test_driver_end()
