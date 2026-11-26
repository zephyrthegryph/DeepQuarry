// Using an item in hand (the Z key, the Activate Held Object entry, a click on the held item) reaches the item's in_hand() op.

/// A PDA that records its window being asked for (a test world has no client, so no window can open).
/obj/item/pda/dq_use_probe
	var/window_asked_by

/obj/item/pda/dq_use_probe/tgui_interact(mob/user, datum/tgui/ui = null, datum/tgui/parent_ui = null, custom_state = null)
	window_asked_by = user
	log_world("TRACE use_in_hand: [src] asked to open its window for [user]")

/// A held PDA opens its window when used in hand, through the Z key's path and through the resolver.
/datum/unit_test/dq_item_use_in_hand_pda

/datum/unit_test/dq_item_use_in_hand_pda/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/pda/dq_use_probe/P = allocate(/obj/item/pda/dq_use_probe, test_floor())
	TEST_ASSERT(H.put_in_active_hand(P), "the human takes the PDA")
	TEST_ASSERT(H.activate_held(), "activate_held reports the held item was used")
	TEST_ASSERT_EQUAL(P.window_asked_by, H, "activate_held (the Z key) asks for the PDA window")
	P.window_asked_by = null
	H.setClickCooldown(0)
	test_click(H, P, P, GESTURE_SELF)
	TEST_ASSERT_EQUAL(P.window_asked_by, H, "a use-in-hand click on the held PDA asks for its window")

/// A generic held item's in_hand() op fires on use in hand.
/datum/unit_test/dq_item_use_in_hand_generic

/datum/unit_test/dq_item_use_in_hand_generic/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	TEST_ASSERT(H.put_in_active_hand(F), "the human takes the flashlight")
	var/was_on = F.on
	TEST_ASSERT(H.activate_held(), "activate_held reports the held item was used")
	TEST_ASSERT(F.on != was_on, "using the flashlight in hand toggles it")
