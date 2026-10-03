/// This fixture invokes the direct handler; it does not claim native admin rights or UI dispatch.
/datum/unit_test/om/interim_secrets_prompt_actor/run_om(list/made)
	sched.test_prompts = list()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	TEST_ASSERT_NULL(actor.client, "the actual fixture has no native privileged client")
	var/datum/secrets_menu/menu = allocate(/datum/secrets_menu, actor)
	TEST_ASSERT_NULL(menu.holder(), "the actual menu has no native admin holder")
	// Enable only the local handler prerequisite, without exercising privilege-gated dispatch.
	menu.is_funmin = TRUE
	var/obj/item/pen/held = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	TEST_ASSERT(actor.put_in_active_hand(held), "the actual actor holds an item before opening the choice")
	var/datum/antagonist/highlander/original_highlanders = GLOB.highlanders
	var/original_members = length(original_highlanders?.current_antagonists)
	var/original_players = length(REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	menu.ui_act_onlyone(actor, list(), null, null, "onlyone")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the actual direct handler opens its typed delay-choice prompt")
	var/datum/om/prompt/choice/alert/ask = sched.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.peek("answerer"), actor, "the actual secret choice belongs to the supplied actor")
	TEST_ASSERT("Instant!" in ask.choices, "the actual prompt retains the immediate action choice")
	TEST_ASSERT_EQUAL(length(ask.choices), 2, "the actual prompt retains its two intended action choices")
	var/datum/om/flow/rerun/act/flow = ask.flow
	TEST_ASSERT(istype(flow), "the real choice carries the actual UI-handler rerun flow")
	TEST_ASSERT_EQUAL(flow.action, "onlyone", "the actual rerun retains the handler action")
	TEST_ASSERT_EQUAL(flow.answer_key, "om_answer_a13", "the actual rerun uses the handler's precise answer-cache key")
	TEST_ASSERT_EQUAL(om_prompt_answer(ask, null, TRUE), "no answer", "closing the actual typed prompt cancels instead of executing an action")
	TEST_ASSERT(ask.answered, "the real cancellation marks the actual prompt answered")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "actual cancellation opens no additional choice")
	TEST_ASSERT_EQUAL(GLOB.highlanders, original_highlanders, "actual cancellation preserves the world highlander controller identity")
	TEST_ASSERT_EQUAL(length(original_highlanders?.current_antagonists), original_members, "actual cancellation creates no new highlander membership")
	TEST_ASSERT_EQUAL(length(REGISTRY_MEMBERS(REGISTRY_PLAYERS)), original_players, "actual cancellation preserves the world player registry")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), held, "actual cancellation preserves the real actor's held inventory")
	TEST_ASSERT_EQUAL(held.loc, actor, "actual cancellation preserves the item's actual containment")
	// Trusted server-only answer arguments exercise the existing unrecognized-answer exit.
	menu.ui_act_onlyone(actor, list("om_answer_a13" = "Cancelled", "om_reentry" = TRUE), null, null, "onlyone")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the direct handler consumes its server answer key without reopening the prompt")
	TEST_ASSERT_EQUAL(GLOB.highlanders, original_highlanders, "the unrecognized answer exit preserves the actual controller")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), held, "the unrecognized answer exit preserves actual inventory")
