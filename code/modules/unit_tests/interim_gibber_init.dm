/// Real safety/emag/drag/eject behavior survives removal of a redundant initializer.
/datum/unit_test/interim_gibber_init
	var/interrupted = FALSE

/datum/unit_test/interim_gibber_init/interrupted
	interrupted = TRUE

/datum/unit_test/interim_gibber_init/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/gibber/gibber = allocate(/obj/machinery/gibber, T)
	TEST_ASSERT(!QDELETED(gibber), "actual gibber initializes alive")
	TEST_ASSERT(!gibber.emagged(), "actual initialized gibber starts with its human safety guard enabled")
	TEST_ASSERT(!gibber.operating, "actual initialized gibber starts idle")
	TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual initialized gibber occupant slot starts empty")
	TEST_ASSERT_EQUAL(user.stat, CONSCIOUS, "actual drag actor starts conscious")
	TEST_ASSERT(!user.restrained(), "actual drag actor is not restrained before the real safety check")
	TEST_ASSERT(!victim.abiotic(TRUE), "actual human fixture has no items blocking gibber insertion")
	TEST_ASSERT_EQUAL(test_op_handler(gibber, "gibber_interaction_drag", user, victim), TRUE, "actual safe-mode human drag entry is handled")
	TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual enabled safety guard refuses human insertion")
	TEST_ASSERT_EQUAL(victim.loc, T, "actual safety refusal preserves its human on the original floor")
	TEST_ASSERT_EQUAL(test_op_handler(gibber, "on_emag", user), OP_OK, "actual emag callback disables the safety guard")
	TEST_ASSERT(gibber.emagged(), "actual emag state disables its safety guard")
	TEST_ASSERT_EQUAL(test_op_handler(gibber, "gibber_interaction_drag", user, victim), TRUE, "actual emagged drag entry starts timed insertion")
	TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual timed insertion does not move the human immediately")
	test_time(2 SECONDS)
	TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual occupant slot remains empty before the three-second deadline")
	TEST_ASSERT_EQUAL(victim.loc, T, "actual pending insertion preserves its human floor")
	if(interrupted)
		var/turf/away = get_step(get_step(T, EAST), EAST)
		TEST_ASSERT(away, "actual cancellation fixture provides a floor outside machine reach")
		user.forceMove(away)
	test_time(1 SECOND)
	if(interrupted)
		TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual actor movement cancels insertion before its deadline")
		TEST_ASSERT_EQUAL(victim.loc, T, "actual canceled insertion preserves the original human floor")
	else
		TEST_ASSERT_EQUAL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), victim, "actual timed insertion installs the same human in its real sealed slot")
		TEST_ASSERT_EQUAL(victim.loc, gibber, "actual timed insertion physically contains the original human")
		TEST_ASSERT_EQUAL(test_op_handler(gibber, "gibber_verb_eject", user), TRUE, "actual empty-gibber entry ejects its occupant")
		TEST_ASSERT_NULL(gibber.slot_item(OCCUPANT_SLOT_GIBBER), "actual ejection clears the real occupant slot")
		TEST_ASSERT_EQUAL(victim.loc, T, "actual ejection returns the same human to the original floor")
	TEST_ASSERT_EQUAL(test_op_handler(gibber, "on_emag", user), OP_OK, "actual second emag callback re-enables the safety guard")
	TEST_ASSERT(!gibber.emagged(), "actual repeat emag toggles the safety state back")
	TEST_ASSERT(!gibber.operating, "actual insertion or cancellation never starts gibbing")
	TEST_ASSERT(!QDELETED(user) && !QDELETED(victim) && !QDELETED(gibber), "actual safety insertion ejection or cancellation preserves every original identity")
