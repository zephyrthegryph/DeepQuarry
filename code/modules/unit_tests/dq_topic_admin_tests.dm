// The admin panel's question links as ops (asks() steps): a link that asks (the newscaster's Feed title, its channel confirmation) opens its question, and
// the answer reaches the op's effect. A clientless fixture holder; the actor carries the admin authority a test can give.

/datum/admins/dq_topic_admin_fixture
	var/refreshes = 0

/datum/admins/dq_topic_admin_fixture/admincaster_refresh(mob/user)
	refreshes++

/datum/unit_test/om/dq_topic_admin_asks

/datum/unit_test/om/dq_topic_admin_asks/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/fixture_key = "dq_topic_admin_asks"
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admins/dq_topic_admin_fixture/holder = allocate(/datum/admins/dq_topic_admin_fixture, list(), fixture_key)
	GLOB.admin_datums -= fixture_key
	made += holder.admincaster_feed_message
	made += holder.admincaster_scratch_channel
	// a link that asks: the Feed title
	var/datum/op_result/asked = op_perform_by_key(actor, holder, null, "ac_set_new_title", ORIGIN_UI, AUTH_ADMIN, FALSE)
	TEST_ASSERT_NOTNULL(asked, "the link runs as an op")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "and opens its one question")
	var/datum/prompt/ask = GLOB.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.answerer, actor, "the question is the actor's")
	TEST_ASSERT_NULL(test_prompt_answer(ask, "Breaking news"), "the answer is accepted")
	TEST_ASSERT_EQUAL(holder.admincaster_feed_message.title, "Breaking news", "the answer reached the op's effect")
	TEST_ASSERT_EQUAL(holder.refreshes, 1, "and the panel refreshed once")
	// a link that confirms: an unnamed channel cannot be created, so the question says so and only offers OK
	holder.admincaster_feed_channel().channel_name = ""
	test_prompts_reset()
	op_perform_by_key(actor, holder, null, "ac_submit_new_channel", ORIGIN_UI, AUTH_ADMIN, FALSE)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the channel link opens its confirmation")
	var/datum/prompt/choice/confirm = GLOB.test_prompts[1]
	made += confirm
	TEST_ASSERT_EQUAL(length(confirm.choices), 1, "an unnamed channel is offered only OK")
	TEST_ASSERT_NULL(test_prompt_answer(confirm, "OK"), "which is accepted")
	TEST_ASSERT_EQUAL(holder.admincaster_screen, 7, "and shows the error screen, as it did")
	// the same link without the admin authority is refused for rights and opens nothing
	test_prompts_reset()
	op_perform_by_key(actor, holder, null, "ac_set_new_title", ORIGIN_UI, AUTH_PHYSICAL, FALSE)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "a link with no rights requirement opens its question for any actor the gate lets in")
	var/datum/op_result/forced = op_perform_by_key(actor, holder, null, "c_mode", ORIGIN_UI, AUTH_PHYSICAL, FALSE)
	TEST_ASSERT_EQUAL(forced?.outcome, ACT_REFUSED, "a link that needs rights refuses an actor without them")
	TEST_ASSERT_EQUAL(forced?.reason, /datum/msg/req_no_rights, "with the rights message")
