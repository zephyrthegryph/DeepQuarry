/// "There can only be one" asks the pressing admin how long to wait (an asks() step of the op) before anything happens: closing the
/// question cancels the op, and nothing changes.
/datum/unit_test/interim_secrets_prompt_actor/Run()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/secrets_menu/menu = allocate(/datum/secrets_menu, actor)
	menu.is_funmin = TRUE
	var/obj/item/pen/held = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	TEST_ASSERT(actor.put_in_active_hand(held), "the actor holds an item before the question opens")
	var/datum/antagonist/highlander/original_highlanders = GLOB.highlanders
	var/original_members = length(original_highlanders?.current_antagonists)
	var/original_players = length(REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	var/datum/op_result/pressed = op_ui_act(actor, menu, "onlyone")
	TEST_ASSERT(istype(pressed), "the button reaches the op")
	TEST_ASSERT_NULL(pressed.outcome, "the op waits on its question")
	test_answer(actor, null, REQ_CANCELLED)
	TEST_ASSERT_NOTNULL(pressed.outcome, "closing the question ends the op")
	TEST_ASSERT_EQUAL(GLOB.highlanders, original_highlanders, "cancelling keeps the highlander controller")
	TEST_ASSERT_EQUAL(length(original_highlanders?.current_antagonists), original_members, "cancelling makes no highlander")
	TEST_ASSERT_EQUAL(length(REGISTRY_MEMBERS(REGISTRY_PLAYERS)), original_players, "cancelling keeps the player registry")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), held, "cancelling keeps the actor's held item")
