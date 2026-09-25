/datum/unit_test/proc/create_test_human(turf/loc = null)
	if(!loc)
		// was T.zone.air.return_pressure() under ZAS; LINDA exposes
		// per-turf air directly via return_air().
		for(var/turf/simulated/floor/tiled/T in world)
			var/datum/gas_mixture/air = T.return_air()
			if(!air)
				continue
			var/pressure = air.return_pressure()
			if(90 < pressure && pressure < 120) // Find a turf between 90 and 120
				loc = T
				break

	TEST_ASSERT(loc, "No valid turf available for test mob")

	var/mob/living/carbon/human/test_human = allocate(/mob/living/carbon/human, loc)

	return test_human

/datum/unit_test/belly_nonsuffocation

/datum/unit_test/belly_nonsuffocation/Run()
	var/mob/living/carbon/human/pred = create_test_human()
	var/mob/living/carbon/human/prey = create_test_human()

	TEST_ASSERT(pred && prey, "Failed to create test mobs")

	pred.init_vore(TRUE)
	TEST_ASSERT(pred.vore_selected, "[pred] has no vore_selected")

	pred.vore_selected.nom_atom(prey)

	TEST_ASSERT(prey.loc == pred.vore_selected, "Prey not inside predator belly")

	var/start_oxy = prey.oxygen_debt()
	_vore_test_run_cycles(pred, prey, 10)

	var/end_oxy = prey.oxygen_debt()
	if(end_oxy > start_oxy)
		TEST_FAIL("Prey became hypoxic in belly (before: [start_oxy], after: [end_oxy])")

/datum/unit_test/belly_spacesafe

/datum/unit_test/belly_spacesafe/Run()
	var/mob/living/carbon/human/pred = create_test_human()
	var/mob/living/carbon/human/prey = create_test_human()

	TEST_ASSERT(pred && prey, "Failed to create test mobs")

	pred.init_vore(TRUE)
	TEST_ASSERT(pred.vore_selected, "[pred] has no vore_selected")

	pred.vore_selected.nom_atom(prey)

	TEST_ASSERT(prey.loc == pred.vore_selected, "Prey not inside predator belly")

	var/empty_z = using_map.get_empty_zlevel()
	TEST_ASSERT(empty_z, "Failed to get empty z-level")

	var/turf/space_turf = locate(
		round(world.maxx * 0.5),
		round(world.maxy * 0.5),
		empty_z
	)

	TEST_ASSERT(space_turf, "Failed to locate space turf")

	pred.forceMove(space_turf)

	var/start_oxy = prey.oxygen_debt()
	_vore_test_run_cycles(pred, prey, 10)

	var/end_oxy = prey.oxygen_debt()
	if(end_oxy > start_oxy)
		TEST_FAIL("Prey became hypoxic in space belly (before: [start_oxy], after: [end_oxy])")

/datum/unit_test/belly_damage

/datum/unit_test/belly_damage/Run()
	var/mob/living/carbon/human/pred = create_test_human()
	var/mob/living/carbon/human/prey = create_test_human()

	TEST_ASSERT(pred && prey, "Failed to create test mobs")

	pred.init_vore(TRUE)
	TEST_ASSERT(pred.vore_selected, "[pred] has no vore_selected")

	pred.vore_selected.nom_atom(prey)

	TEST_ASSERT(prey.loc == pred.vore_selected, "Prey not inside predator belly")

	pred.vore_selected.digest_mode = DM_DIGEST

	var/start_damage = _vore_test_total_injury(prey)
	_vore_test_run_cycles(pred, prey, 10)

	var/end_damage = _vore_test_total_injury(prey)
	if(end_damage <= start_damage)
		TEST_FAIL("Prey took no digestion damage (before: [start_damage], after: [end_damage])")


/// Every injury on a mob, whatever form the body gave it (limb wounds,
/// systemic afflictions, loads). Digestion may land as any of them.
/proc/_vore_test_total_injury(mob/living/L)
	. = 0
	for(var/category in 1 to INJURY_CATEGORY_COUNT)
		. += L.injury_load(category)
	. += L.oxygen_debt()
	for(var/datum/affliction/A as anything in L.body?.afflictions)
		if(A.injury_category)
			. += A.load_value()


/// Drive the predator, prey and the predator's belly through `cycles` Life
/// and belly-process cycles directly, instead of sleeping for real game time
/// (a mob Life tick is 2 s, so 10 cycles used to cost 20+ s per test).
/// The calls are the same ones SSmobs and SSreactor make each cycle.
/proc/_vore_test_run_cycles(mob/living/pred, mob/living/prey, cycles)
	for(var/i in 1 to cycles)
		pred.life_frame()
		prey.life_frame()
		for(var/obj/belly/B as anything in pred.vore_organs)
			B.belly_cycle(BELLY_BASELINE_TICK / (1 SECONDS))
