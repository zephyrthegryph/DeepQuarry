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

/// No area shows its map-editor sprite in game once the world is up, whatever way its first draw was scheduled (a parked, stamped or never-queued draw
/// leaves the mapped icon_state: "Space", "Emergency Storage" on the tiles). Nothing here flushes the refresh queue first.
/datum/unit_test/dq_areas_show_no_map_sprite

/datum/unit_test/dq_areas_show_no_map_sprite/Run()
	var/checked = 0
	var/list/shown = list()
	for(var/area/A in world)
		if(!length(A.contents))
			continue
		checked++
		if(A.icon_state in list("", "party", "red", "blue-red"))
			continue
		shown += "[A.type]=[A.icon_state]"
	TEST_ASSERT(checked, "the world has areas with turfs")
	TEST_ASSERT(!length(shown), "[length(shown)] area(s) still show a map-editor sprite: [jointext(shown.Copy(1, min(length(shown), 12) + 1), ", ")]")

/// A boot that loads a look-verdict cache (look_verdicts_load()) knows its types lazy before any of them draws. An area is in no chunk a client can come near, so a
/// parked first draw of it is never asked for: it showed its map sprite for the whole round ("Space", "Emergency Storage"). Areas are never lazy, whatever a verdict
/// says, and the boot settle draws them. Nothing here flushes after the settle.
/datum/unit_test/dq_areas_draw_under_cached_lazy_verdict

/datum/unit_test/dq_areas_draw_under_cached_lazy_verdict/Run()
	set_global(nameof(GLOB.refresh_parked_near), GLOB.refresh_parked_near)
	interest_isolate()
	set_global(nameof(GLOB.refresh_parked_marked), GLOB.refresh_parked_marked)
	set_global(nameof(GLOB.refresh_parked), GLOB.refresh_parked)
	set_global(nameof(GLOB.refresh_near_drawn), GLOB.refresh_near_drawn)
	set_global(nameof(GLOB.refresh_park_residual), GLOB.refresh_park_residual)
	set_global(nameof(GLOB.type_look_stamp_skipped), GLOB.type_look_stamp_skipped)
	set_global(nameof(GLOB.interest_unperceivable_skipped), GLOB.interest_unperceivable_skipped)
	var/area/A = get_area(test_floor())
	TEST_ASSERT_NOTNULL(A, "the test floor has an area")
	refresh_flush()
	var/was_lazy = GLOB.type_look_lazy[A.type]
	var/was_stamp = GLOB.type_look_stamp[A.type]
	GLOB.type_look_lazy[A.type] = TRUE // the cache says so
	GLOB.type_look_stamp -= A.type
	TEST_ASSERT(!look_lazy_ok(A), "an area is never lazy, whatever its verdict")
	// The state a boot with that cache leaves: the map sprite showing, one real mark made during init (the lighting setup's), nothing drawn.
	A.set_icon_state(initial(A.icon_state))
	rx_of(A).look_key = null
	refresh_mark(A, DEP_ALL)
	TEST_ASSERT(!(A.refresh_queued & DEP_CREATED), "a real mark clears the creation mark")
	refresh_settle_created()
	refresh_park_backlog()
	TEST_ASSERT(A.refresh_queued != DEP_PARKED, "the park leaves the area's first draw queued")
	refresh_flush()
	TEST_ASSERT_EQUAL(A.icon_state, "", "and the area is drawn blank (was its map state '[initial(A.icon_state)]')")
	GLOB.type_look_lazy[A.type] = was_lazy
	GLOB.type_look_stamp[A.type] = was_stamp

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
