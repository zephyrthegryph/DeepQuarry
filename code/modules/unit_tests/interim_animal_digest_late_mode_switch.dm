/datum/unit_test/interim_animal_digest_late_mode_switch/Run()
	test_driver_begin()
	check_late_mode_switch()
	test_driver_end()

/datum/unit_test/interim_animal_digest_late_mode_switch/proc/check_late_mode_switch()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/simple_mob/animal = allocate(/mob/living/simple_mob, test_floor())
	var/mob/living/simple_mob/control = allocate(/mob/living/simple_mob, test_floor())
	animal.init_vore(TRUE)
	control.init_vore(TRUE)
	var/obj/belly/belly = animal.vore_selected
	var/obj/belly/control_belly = control.vore_selected
	TEST_ASSERT(belly && belly.owner == animal, "Actual animal initialization supplies its selected owned belly")
	TEST_ASSERT(control_belly && control_belly.owner == control && control_belly != belly, "Independent animal has a distinct actual belly")
	own(belly)
	own(control_belly)
	TEST_ASSERT_EQUAL(actor.stat, CONSCIOUS, "Actual requesting human starts conscious")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Fixture starts without a pending native request")
	belly.digest_mode = DM_HOLD
	control_belly.digest_mode = DM_HOLD

	animal.toggle_digestion_for(actor)
	TEST_ASSERT(istype(SSrequests.open_for(actor), /datum/prompt/choice/animal_digestion/enable), "Public helper opens actual enable request")
	belly.digest_mode = DM_DIGEST
	test_answer(actor, "Enable")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_DIGEST, "Late mode change survives first answer while opposite branch asks")
	TEST_ASSERT(istype(SSrequests.open_for(actor), /datum/prompt/choice/animal_digestion/disable), "Answer rechecks current mode and opens actual disable request")
	belly.digest_mode = DM_HOLD
	test_answer(actor, "Disable")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_DIGEST, "Second late switch applies cached Enable answer to current hold mode")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Both cached answers finish without reopening enable")

	animal.toggle_digestion_for(actor)
	TEST_ASSERT(istype(SSrequests.open_for(actor), /datum/prompt/choice/animal_digestion/disable), "Digest mode opens actual disable request")
	belly.digest_mode = DM_HOLD
	test_answer(actor, "Disable")
	TEST_ASSERT(istype(SSrequests.open_for(actor), /datum/prompt/choice/animal_digestion/enable), "Late hold mode opens actual enable request")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "No answer from the wrong branch changes hold mode")
	belly.digest_mode = DM_DIGEST
	test_answer(actor, "Enable")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "Second late switch applies cached Disable answer to current digest mode")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Both cached answers finish without reopening disable")

	animal.toggle_digestion_for(actor)
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "Explicit close has a real pending request")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "Closing actual request preserves mode")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Explicit close does not reopen a request")
	animal.toggle_digestion_for(actor)
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "Cancel button has a real pending request")
	test_answer(actor, "Cancel")
	TEST_ASSERT_EQUAL(belly.digest_mode, DM_HOLD, "Accepted Cancel button preserves mode")
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Accepted Cancel button finishes the request")
	TEST_ASSERT_EQUAL(control.vore_selected, control_belly, "Independent animal retains its original selected belly")
	TEST_ASSERT_EQUAL(control_belly.digest_mode, DM_HOLD, "Independent animal remains unchanged throughout both workflows")
