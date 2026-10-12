// Client render regressions found on a local server (October 2026): area sprites showing in game, and the folded inventory bar's
// items showing on the first login.

/// An area shows nothing in game: its map sprite ("unknown", the editor colours) is blanked by its draw, from boot and after an alarm clears.
/datum/unit_test/dq_area_draws_blank

/datum/unit_test/dq_area_draws_blank/Run()
	var/area/A = get_area(test_floor())
	TEST_ASSERT_NOTNULL(A, "the test floor has an area")
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "", "a quiet area draws no sprite (was its map state '[initial(A.icon_state)]')")
	var/was_party = A.party
	A.set_party(1)
	refresh_flush()
	if(!A.requires_power || A.power_environ)
		TEST_ASSERT_EQUAL(A.icon_state, "party", "a party shows")
	A.set_party(was_party)
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "", "and the area is blank again when it ends")

/// An item equipped onto the toggled inventory bar while it is folded gets no screen position (so it is not drawn on the screen);
/// the always-shown slots keep theirs. Slot ids are text, so this must not be an ordering test on them.
/datum/unit_test/dq_folded_inventory_hides_equipped_items

/datum/unit_test/dq_folded_inventory_hides_equipped_items/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/hud/hud = allocate(/datum/hud, H)
	var/list/info = list()
	for(var/slot in list(SLOT_ID_HAND_L, SLOT_ID_HAND_R, SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_ID, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R, SLOT_ID_SUIT_STORAGE) + GLOB.hud_toggled_slots)
		info["[slot]"] = "1,[length(info) + 1]"
	hud.slot_info = info
	hud.hud_shown = 1
	hud.inventory_shown = 0
	var/obj/item/I = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	for(var/slot in GLOB.hud_toggled_slots)
		I.screen_loc = "stale"
		H.position_hud_item(I, slot)
		TEST_ASSERT_NULL(I.screen_loc, "a [slot] item is hidden while the inventory bar is folded")
	for(var/slot in list(SLOT_ID_BACK, SLOT_ID_BELT, SLOT_ID_ID, SLOT_ID_POCKET_L, SLOT_ID_POCKET_R, SLOT_ID_HAND_L, SLOT_ID_HAND_R))
		H.position_hud_item(I, slot)
		TEST_ASSERT_EQUAL(I.screen_loc, info["[slot]"], "a [slot] item keeps its place on the always-shown bar")
	hud.inventory_shown = 1
	H.position_hud_item(I, SLOT_ID_HEAD)
	TEST_ASSERT_EQUAL(I.screen_loc, info[SLOT_ID_HEAD], "an opened bar shows the hat")
	hud.hud_shown = 0
	H.position_hud_item(I, SLOT_ID_BACK)
	TEST_ASSERT_NULL(I.screen_loc, "a hidden HUD hides the back slot")
	H.position_hud_item(I, SLOT_ID_HAND_R)
	TEST_ASSERT_EQUAL(I.screen_loc, info[SLOT_ID_HAND_R], "but keeps the hands")
	I.screen_loc = null
