// Pull pulls the thing chosen at once: ctrl-click (and the context menu's Pull, which takes the same action) names the target and asks no question.

/datum/unit_test/dq_pull_named_target_at_once

/datum/unit_test/dq_pull_named_target_at_once/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/structure/closet/C = allocate(/obj/structure/closet, get_step(test_floor(), EAST))
	var/obj/structure/closet/other = allocate(/obj/structure/closet, get_step(test_floor(), WEST))
	test_prompts_reset()
	H.action_pull(C)
	TEST_ASSERT_EQUAL(H.pulling_target(), C, "ctrl-click pulls the closet clicked, not another one")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "and asks nothing")
	H.stop_pulling()
	H.set_dir(WEST)
	H.pulled()
	TEST_ASSERT_EQUAL(H.pulling_target(), other, "the bare Pull verb pulls what is in front")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "and asks nothing")
	GLOB.test_prompts = null
