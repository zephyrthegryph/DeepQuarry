/// Semantic wakes retain the scheduler's existing wake categories.
/datum/unit_test/dq_life_typed_wake

/datum/unit_test/dq_life_typed_wake/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.life_awake = NONE
	TEST_ASSERT(H.wake_life(/datum/life_wake_event/body, "test body"), "body event was accepted")
	TEST_ASSERT_EQUAL(H.life_awake, LIFE_WAKE_BODY, "body event wakes the body concerns")
	H.life_awake = NONE
	TEST_ASSERT(H.wake_life(/datum/life_system/breathing, "test family"), "direct family was accepted")
	TEST_ASSERT_EQUAL(H.life_awake, LIFE_SYS_BREATHING, "direct family wakes its concern")
