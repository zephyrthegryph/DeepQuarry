/obj/interim_fabricator_drop_actor_click
	var/obj/machinery/machine
	var/turf/landing

/obj/interim_fabricator_drop_actor_click/Click(location, control, params)
	machine.MouseDrop(null, get_turf(machine), landing)

/datum/unit_test/interim_fabricator_drop_actor
	abstract_type = /datum/unit_test/interim_fabricator_drop_actor
	var/machine_type

/datum/unit_test/interim_fabricator_drop_actor/production
	machine_type = /obj/machinery/rnd/production/protolathe

/datum/unit_test/interim_fabricator_drop_actor/mech
	machine_type = /obj/machinery/mecha_part_fabricator_tg

/datum/unit_test/interim_fabricator_drop_actor/Run()
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
	if(istype(machine, /obj/machinery/rnd/production))
		var/obj/machinery/rnd/production/production = machine
		TEST_ASSERT(!production.busy, "the real production machine is not printing")
	else
		var/obj/machinery/mecha_part_fabricator_tg/mech = machine
		TEST_ASSERT_NULL(mech.being_built(), "the actual mech fabricator has no active design")
	var/obj/interim_fabricator_drop_actor_click/probe = allocate(/obj/interim_fabricator_drop_actor_click, T)
	rel_set(probe, nameof(probe.machine), machine)
	rel_set(probe, nameof(probe.landing), east)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(actual_direction(machine), EAST, "the actual native drag selects the real east output direction")
	TEST_ASSERT(!machine.Adjacent(bystander) && machine.Adjacent(ghost), "distant human and nearby actual observer satisfy their distinct refusal preconditions")
	rel_set(probe, nameof(probe.landing), north)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_EQUAL(actual_direction(machine), EAST, "a distant native actor cannot reorient the actual machine")
	km_synthetic_click(ghost, probe)
	TEST_ASSERT_EQUAL(actual_direction(machine), EAST, "a nearby actual observer cannot reorient the actual machine")
	rel_set(probe, nameof(probe.landing), T)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(actual_direction(machine), EAST, "an actual zero-vector drop leaves its previous output orientation unchanged")
	rel_set(probe, nameof(probe.landing), north)
	km_synthetic_click(actor, probe)
	TEST_ASSERT_EQUAL(actual_direction(machine), NORTH, "the same supported native actor can choose another real output floor")
	if(istype(machine, /obj/machinery/rnd/production))
		var/obj/machinery/rnd/production/production = machine
		TEST_ASSERT(!production.busy, "orientation never starts production printing")
	else
		var/obj/machinery/mecha_part_fabricator_tg/mech = machine
		TEST_ASSERT_NULL(mech.being_built(), "orientation never starts a mech design")

/datum/unit_test/interim_fabricator_drop_actor/proc/actual_direction(obj/machinery/machine)
	if(istype(machine, /obj/machinery/rnd/production))
		var/obj/machinery/rnd/production/production = machine
		return production.drop_direction
	var/obj/machinery/mecha_part_fabricator_tg/mech = machine
	return mech.drop_direction
