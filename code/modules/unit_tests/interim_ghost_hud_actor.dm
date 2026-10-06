/datum/unit_test/om/interim_ghost_hud_jump_actor/run_om(list/made)
	test_prompts_reset()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/destination = get_step(start, EAST)
	TEST_ASSERT(isturf(destination) && destination != start, "a real separate destination exists")
	var/mob/observer/dead/actor = allocate(/mob/observer/dead, start)
	var/mob/observer/dead/bystander = allocate(/mob/observer/dead, start)
	actor.forceMove(start)
	bystander.forceMove(start)
	TEST_ASSERT_EQUAL(get_turf(actor), start, "the actual observer starts at the known jump origin")
	TEST_ASSERT_EQUAL(get_turf(bystander), start, "the actual unrelated observer starts at the known origin")
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, destination)
	var/atom/movable/screen/ghost/jumptomob/button = allocate(/atom/movable/screen/ghost/jumptomob)
	km_synthetic_click(actor, button)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "the actual native ghost click opens the real jump choice")
	var/datum/prompt/choice/ask = GLOB.test_prompts[1]
	made += ask
	TEST_ASSERT_EQUAL(ask.answerer, actor, "the native boundary passes the actual observer to the real prompt")
	var/target_key
	for(var/key in ask.choices)
		if(ask.choices[key] == target)
			target_key = key
			break
	TEST_ASSERT(!isnull(target_key), "the actual registry-backed jump list includes the real target")
	test_prompt_answer(ask, target_key)
	TEST_ASSERT_EQUAL(get_turf(actor), destination, "the actual answer moves the original observer to the actual target")
	TEST_ASSERT_EQUAL(get_turf(bystander), start, "the unrelated observer does not move")
	TEST_ASSERT_EQUAL(get_turf(target), destination, "the selected mob remains at its original destination")
	button.click_with_actor(bystander, "", "", "")
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "the explicit helper opens a second real jump prompt")
	var/datum/prompt/choice/second = GLOB.test_prompts[2]
	made += second
	TEST_ASSERT_EQUAL(second.answerer, bystander, "the helper retains its supplied observer instead of the previous native actor")
	test_prompt_answer(second, null, TRUE)
	TEST_ASSERT_EQUAL(get_turf(bystander), start, "cancelling the actual jump choice leaves the observer in place")
	TEST_ASSERT_EQUAL(get_turf(actor), destination, "cancellation does not affect the first observer")

/datum/unit_test/om/interim_ghost_hud_actor_refusal/run_om(list/made)
	test_prompts_reset()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/turf/original = get_turf(actor)
	var/list/buttons = list(/atom/movable/screen/ghost/returntomenu, /atom/movable/screen/ghost/jumptomob, /atom/movable/screen/ghost/orbit, /atom/movable/screen/ghost/reenter_corpse, /atom/movable/screen/ghost/teleport, /atom/movable/screen/ghost/pai, /atom/movable/screen/ghost/up, /atom/movable/screen/ghost/down, /atom/movable/screen/ghost/vr)
	for(var/button_type in buttons)
		var/atom/movable/screen/ghost/button = allocate(button_type)
		km_synthetic_click(actor, button)
		button.click_with_actor(null, "", "", "")
		TEST_ASSERT_EQUAL(get_turf(actor), original, "unsupported native actor and missing explicit actor cannot move through ghost controls")
		TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 0, "each real ghost control refuses unsupported and missing actors without opening a choice")
