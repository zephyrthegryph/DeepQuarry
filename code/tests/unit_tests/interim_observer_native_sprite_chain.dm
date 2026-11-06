/// Production ghost sprite verb and real native answers; no client-window delivery claim.
/datum/unit_test/interim_observer_native_sprite_chain

/datum/unit_test/interim_observer_native_sprite_chain/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/original_state = ghost.icon_state
	var/original_sprite = ghost.ghost_sprite
	var/pick_key
	var/second_key
	for(var/key in GLOB.possible_ghost_sprites)
		var/state = GLOB.possible_ghost_sprites[key]
		if(!state || state == "blank" || state == original_state)
			continue
		if(isnull(pick_key))
			pick_key = key
		else if(state != GLOB.possible_ghost_sprites[pick_key])
			second_key = key
			break
	TEST_ASSERT_NOTNULL(pick_key, "the real sprite registry supplies a nonblank alternative to the initial sprite")
	TEST_ASSERT_NOTNULL(second_key, "the real sprite registry supplies a second distinct nonblank alternative")
	var/picked_state = GLOB.possible_ghost_sprites[pick_key]
	var/second_state = GLOB.possible_ghost_sprites[second_key]

	ghost.choose_ghost_sprite()
	test_drain()
	TEST_ASSERT(istype(SSrequests.open_for(ghost), /datum/prompt/choice/ghost_sprite), "the actual sprite verb opens its native choice")
	test_answer(ghost, pick_key)
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "the selected sprite is previewed before confirmation")
	TEST_ASSERT_EQUAL(ghost.ghost_sprite, original_sprite, "preview does not commit the stored ghost sprite")
	TEST_ASSERT(istype(SSrequests.open_for(ghost), /datum/prompt/choice/ghost_sprite_confirm), "preview opens the actual second confirmation")
	test_answer(ghost, "No")
	TEST_ASSERT_EQUAL(ghost.icon_state, original_state, "No restores the initial actual icon state")
	TEST_ASSERT(istype(SSrequests.open_for(ghost), /datum/prompt/choice/ghost_sprite), "No opens the real first question again")
	test_answer(ghost, pick_key)
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "repicking previews the actual chosen sprite again")
	test_answer(ghost, "Yes")
	TEST_ASSERT_EQUAL(ghost.ghost_sprite, picked_state, "Yes commits the actual selected sprite")
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "Yes retains the real previewed icon")
	TEST_ASSERT_NULL(SSrequests.open_for(ghost), "Yes ends the sprite workflow")

	ghost.choose_ghost_sprite()
	test_drain()
	test_answer(ghost, second_key)
	TEST_ASSERT_EQUAL(ghost.icon_state, second_state, "the next actual selection previews a distinct sprite")
	test_answer(ghost, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "second-question cancellation restores its initial actual state")
	TEST_ASSERT_EQUAL(ghost.ghost_sprite, picked_state, "second-question cancellation preserves the committed sprite")
	TEST_ASSERT_NULL(SSrequests.open_for(ghost), "second-question cancellation does not repick")

	ghost.choose_ghost_sprite()
	test_drain()
	TEST_ASSERT(istype(SSrequests.open_for(ghost), /datum/prompt/choice/ghost_sprite), "first-question cancellation control really opens")
	test_answer(ghost, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "first-question cancellation preserves the actual current icon")
	TEST_ASSERT_EQUAL(ghost.ghost_sprite, picked_state, "first-question cancellation preserves the stored sprite")
	TEST_ASSERT_NULL(SSrequests.open_for(ghost), "first-question cancellation ends without confirmation")

	ghost.choose_ghost_sprite()
	test_drain()
	test_answer(ghost, second_key)
	TEST_ASSERT_EQUAL(ghost.icon_state, second_state, "the invalid-answer control has a real distinct preview")
	var/datum/request/confirmation = SSrequests.open_for(ghost)
	TEST_ASSERT(istype(confirmation, /datum/prompt/choice/ghost_sprite_confirm), "the invalid-answer control really opens confirmation")
	test_answer(ghost, "Not An Offered Answer")
	TEST_ASSERT_EQUAL(SSrequests.open_for(ghost), confirmation, "an invalid confirmation is refused without replacing the actual request")
	TEST_ASSERT_NOTNULL(confirmation.last_error, "the refused choice records its actual diagnostic")
	test_answer(ghost, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(ghost.icon_state, picked_state, "explicit cancellation restores the initial state even after a stale refusal diagnostic")
	TEST_ASSERT_EQUAL(ghost.ghost_sprite, picked_state, "invalid-then-cancel never commits the preview")
	TEST_ASSERT_NULL(SSrequests.open_for(ghost), "invalid-then-cancel ends without another first question")
