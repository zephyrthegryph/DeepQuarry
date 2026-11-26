// setSharedState stores what a client sends on the window's host datum: it is bounded in key count and key/value length, takes text only,
// and an existing key may still change at the key limit.

/datum/unit_test/dq_tgui_shared_state_bounded
/datum/unit_test/dq_tgui_shared_state_bounded/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/host = allocate(/obj/item, T)
	var/datum/tgui/dq_status_probe/ui = new(user, host, "Probe")
	TEST_ASSERT(ui.set_shared_state("tab", "\"1\""), "a short text key and value are stored")
	TEST_ASSERT_EQUAL(host.tgui_shared_states?["tab"], "\"1\"", "the stored value is on the host datum")
	TEST_ASSERT(!ui.set_shared_state(5, "\"x\""), "a non-text key is refused")
	TEST_ASSERT(!ui.set_shared_state("num", 5), "a non-text value is refused")
	TEST_ASSERT(!ui.set_shared_state(dq_repeat_char("k", TGUI_SHARED_STATE_MAX_KEY_LEN + 1), "\"x\""), "an over-long key is refused")
	TEST_ASSERT(!ui.set_shared_state("big", dq_repeat_char("v", TGUI_SHARED_STATE_MAX_VALUE_LEN + 1)), "an over-long value is refused")
	TEST_ASSERT(!("big" in host.tgui_shared_states), "a refused value is not stored")
	for(var/i in 2 to TGUI_SHARED_STATE_MAX_KEYS)
		TEST_ASSERT(ui.set_shared_state("key[i]", "[i]"), "key [i] fits under the key limit")
	TEST_ASSERT_EQUAL(LAZYLEN(host.tgui_shared_states), TGUI_SHARED_STATE_MAX_KEYS, "the host holds exactly the key limit")
	TEST_ASSERT(!ui.set_shared_state("one_more", "\"x\""), "a new key past the limit is refused")
	TEST_ASSERT_EQUAL(LAZYLEN(host.tgui_shared_states), TGUI_SHARED_STATE_MAX_KEYS, "the refused key did not grow the table")
	TEST_ASSERT(ui.set_shared_state("tab", "\"2\""), "an existing key may still change at the limit")
	TEST_ASSERT_EQUAL(host.tgui_shared_states["tab"], "\"2\"", "the existing key took its new value")
	qdel(ui)

/// `count` copies of `char`.
/proc/dq_repeat_char(char, count)
	var/list/parts = new /list(count)
	for(var/i in 1 to count)
		parts[i] = char
	return jointext(parts, "")
