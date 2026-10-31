/// Each actual hardware repair uses the real click/timer path and consumes its original replacement before granting functionality.
/datum/unit_test/round2_paicard_hardware_repair
	parent_type = /datum/unit_test/dq_p2_engine
	var/part_type = /obj/item/paiparts/processor
	var/hardware_key = nameof(/obj/item/paicard::processor)
	var/refuse_release = TRUE

/datum/unit_test/round2_paicard_hardware_repair/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/board
	part_type = /obj/item/paiparts/board
	hardware_key = nameof(/obj/item/paicard::board)

/datum/unit_test/round2_paicard_hardware_repair/board/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/capacitor
	part_type = /obj/item/paiparts/capacitor
	hardware_key = nameof(/obj/item/paicard::capacitor)

/datum/unit_test/round2_paicard_hardware_repair/capacitor/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/projector
	part_type = /obj/item/paiparts/projector
	hardware_key = nameof(/obj/item/paicard::projector)

/datum/unit_test/round2_paicard_hardware_repair/projector/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/emitter
	part_type = /obj/item/paiparts/emitter
	hardware_key = nameof(/obj/item/paicard::emitter)

/datum/unit_test/round2_paicard_hardware_repair/emitter/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/speech_synthesizer
	part_type = /obj/item/paiparts/speech_synthesizer
	hardware_key = nameof(/obj/item/paicard::speech_synthesizer)

/datum/unit_test/round2_paicard_hardware_repair/speech_synthesizer/allowed
	refuse_release = FALSE

/datum/unit_test/round2_paicard_hardware_repair/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/paicard/device = allocate(/obj/item/paicard, T)
	var/obj/item/paiparts/part = allocate(part_type, T)
	TEST_ASSERT_EQUAL(part.type, part_type, "actual fixture initializes the exact declared hardware ingredient")
	TEST_ASSERT_EQUAL(device.vars[hardware_key], PP_FUNCTIONAL, "real pAI initializes tested hardware functional")
	set_var(device, hardware_key, PP_MISSING)
	set_var(device, nameof(device.panel_open), TRUE)
	TEST_ASSERT(user.put_in_active_hand(part), "actor holds exact original replacement hardware")
	if(refuse_release)
		add_trait(part, TRAIT_NODROP, "round2_pai_hardware")
		TEST_ASSERT(user.release_refusal(part, user), "actual inventory refuses original sticky hardware")
	TEST_ASSERT(!user.incapacitated(), "real repair actor starts healthy")
	test_click(user, device, part)
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(device.vars[hardware_key], PP_MISSING, "actual click repair grants no functional hardware before its three-second deadline")
	TEST_ASSERT(!QDELETED(part), "actual repair consumes no original part before its deadline")
	TEST_ASSERT_EQUAL(user.get_active_hand(), part, "pending repair preserves exact original source hand")
	test_time(2 SECONDS)
	TEST_ASSERT(!user.incapacitated(), "real repair actor remains healthy at completion")
	if(refuse_release)
		TEST_ASSERT_EQUAL(device.vars[hardware_key], PP_MISSING, "refused original consumption grants no functional hardware")
		TEST_ASSERT(!QDELETED(part), "refused completion preserves original hardware alive")
		TEST_ASSERT_EQUAL(user.get_active_hand(), part, "refused completion preserves exact original hand")
		TEST_ASSERT_EQUAL(part.loc, user, "refused completion preserves original inventory containment")
	else
		TEST_ASSERT_EQUAL(device.vars[hardware_key], PP_FUNCTIONAL, "actual allowed completion installs functional hardware")
		TEST_ASSERT(QDELETED(part), "actual allowed completion consumes exact original hardware")
		TEST_ASSERT_NULL(user.get_active_hand(), "actual allowed completion clears original source hand")
