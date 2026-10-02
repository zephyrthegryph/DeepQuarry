/// The actual admin fax logo prompt belongs to its supplied actor and refuses a clientless actor without admin rights.
/datum/unit_test/om/interim_adminpaper_logo_actor/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/paper/admin/paper = allocate(/obj/item/paper/admin, run_loc_floor_bottom_left)
	var/original_info = paper.info
	paper.adminbrowse(user)
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the actual browse helper creates its logo prompt for the supplied actor")
	var/datum/om/prompt/choice/ask = sched.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.peek("answerer"), user, "the actual parked prompt answers to the supplied actor")
	TEST_ASSERT_EQUAL(ask.peek("receiver"), paper, "the actual parked prompt targets the original admin paper")
	TEST_ASSERT_EQUAL(paper.tgui_view, "write", "the actual browse helper sets its intended write view")
	TEST_ASSERT_EQUAL(om_prompt_answer(ask, "NanoTrasen"), "no admin rights", "the actual logo callback remains protected by its existing permission check")
	TEST_ASSERT_NULL(paper.header, "permission refusal prevents header creation")
	TEST_ASSERT_EQUAL(paper.info, original_info, "permission refusal preserves the actual paper body")
