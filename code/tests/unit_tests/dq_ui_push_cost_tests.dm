// What a push of a window and of the stat panel costs, and that a push the page already shows is dropped (tgui_window.dm send_message's
// same_key). The UI_PUSH_COST notices are the measurement: ms per push, bytes per push, before and after the caches.
//   bash tools/dq_focused_test.sh 'dq_ui_push_cost_*'

/// A window with a stand-in transport that keeps what it would write.
/datum/tgui_window/dq_push_stub
	var/list/sent = list()

/datum/tgui_window/dq_push_stub/reachable()
	return TRUE

/datum/tgui_window/dq_push_stub/deliver(message)
	sent += message

/datum/unit_test/dq_ui_push_cost_same_key
/datum/unit_test/dq_ui_push_cost_same_key/Run()
	var/datum/tgui_window/dq_push_stub/W = allocate(/datum/tgui_window/dq_push_stub, null, "dq_push_stub", FALSE)
	W.status = TGUI_WINDOW_READY
	W.send_message("update", list("a" = 1), same_key = "update")
	W.send_message("update", list("a" = 1), same_key = "update")
	TEST_ASSERT_EQUAL(length(W.sent), 1, "an update the page already shows is not sent again")
	TEST_ASSERT_EQUAL(W.unchanged_skipped, 1, "and the window counts it")
	W.send_message("update", list("a" = 2), same_key = "update")
	TEST_ASSERT_EQUAL(length(W.sent), 2, "a changed update goes out")
	W.send_message("update", list("a" = 1, "static" = 1))
	W.send_message("update", list("a" = 2), same_key = "update")
	TEST_ASSERT_EQUAL(length(W.sent), 4, "a full update (no key) in between makes the next keyed one go out even when it equals the one before")
	W.send_message("update_misc", list("TN" = "x"), same_key = "update_misc:x")
	W.forget_sent("update_misc:x")
	W.send_message("update_misc", list("TN" = "x"), same_key = "update_misc:x")
	TEST_ASSERT_EQUAL(length(W.sent), 6, "after the page dropped the state (forget_sent), the same message goes out again")
	W.close(FALSE)
	TEST_ASSERT_NULL(W.last_sent, "closing forgets what the page showed")

/// The Abilities tab of a shadekin: build cost and size of a push, and the icon cost per push before (cut, rsc copy and hash per ability per
/// push, what icon2html did) and after (the icon_file_asset cache).
/datum/unit_test/dq_ui_push_cost_abilities
/datum/unit_test/dq_ui_push_cost_abilities/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.add_shadekin(/datum/shadekin/full)
	var/obj/item/flashlight/F = allocate(/obj/item/flashlight, test_floor())
	H.put_in_r_hand(F)
	var/list/abilities = ordered_abilities(H)
	TEST_ASSERT(length(abilities) >= 2, "the shadekin has abilities to show")
	var/n = 20
	var/started = TICK_USAGE_REAL
	var/list/data
	for(var/i in 1 to n)
		data = ability_panel_data(H)
	var/build_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/bytes = length(json_encode(data))
	// Before: per ability per push, the old ability_icon_src() path (icon() of the state, a dmi-path probe that copies it into the rsc, then
	// icon2html's cut, rsc copy and hash).
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		for(var/datum/action/entry as anything in abilities)
			dq_old_ability_icon_cost(entry)
	var/icons_before_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	// After: the cached asset name (built once, on the first push).
	for(var/datum/action/entry as anything in abilities)
		dq_new_ability_icon_key(entry)
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		for(var/datum/action/entry as anything in abilities)
			dq_new_ability_icon_key(entry)
	var/icons_after_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		op_menu(H, H, null)
	var/menu_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_NOTICE(src, "UI_PUSH_COST abilities: one op_menu read [round(menu_ms, 0.001)] ms")
	TEST_NOTICE(src, "UI_PUSH_COST abilities: [length(abilities)] entries, [bytes] bytes/push, data [round(build_ms, 0.001)] ms/push, icons before [round(icons_before_ms, 0.001)] ms/push, icons after [round(icons_after_ms, 0.001)] ms/push")
	TEST_ASSERT(icons_after_ms < icons_before_ms, "the cached icons cost less than cutting them on every push")
	// Two pushes of an unchanged tab: the second is dropped.
	var/datum/tgui_window/dq_push_stub/W = allocate(/datum/tgui_window/dq_push_stub, null, "dq_push_stub_ab", FALSE)
	W.status = TGUI_WINDOW_READY
	started = TICK_USAGE_REAL
	W.send_message("update_abilities", data, same_key = "update_abilities")
	var/send_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	W.send_message("update_abilities", ability_panel_data(H), same_key = "update_abilities")
	var/same_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT_EQUAL(length(W.sent), 1, "an unchanged Abilities tab is not sent again")
	TEST_NOTICE(src, "UI_PUSH_COST abilities send: [round(send_ms, 0.001)] ms delivered, [round(same_ms, 0.001)] ms when unchanged (dropped, data build included)")

/// The old per-ability icon work of one push (ability_icon_src() before the cache), without the send.
/datum/unit_test/dq_ui_push_cost_abilities/proc/dq_old_ability_icon_cost(datum/action/entry)
	var/atom/source = entry.ability_icon_source()
	if(source)
		var/icon/cut = icon(source.icon, source.icon_state, source.dir, 1, FALSE)
		generate_and_hash_rsc_file(cut, get_icon_dmi_path(source))
		return
	if(!entry.button_icon)
		return
	var/icon/passed = icon(entry.button_icon, entry.button_icon_state)
	var/path = get_icon_dmi_path(passed)
	generate_and_hash_rsc_file(icon(passed, "", SOUTH, 1, FALSE), path)

/// The new per-ability icon work of one push, without the send.
/datum/unit_test/dq_ui_push_cost_abilities/proc/dq_new_ability_icon_key(datum/action/entry)
	var/atom/source = entry.ability_icon_source()
	if(source)
		return CACHED3(icon_file_asset, source.icon, isnull(source.icon_state) ? "" : source.icon_state, source.dir || SOUTH)
	if(!entry.button_icon)
		return null
	return CACHED3(icon_file_asset, entry.button_icon, isnull(entry.button_icon_state) ? "" : entry.button_icon_state, SOUTH)

/// The Status tab: build cost and size of a push (sent every status_wait fires to a client on the tab).
/datum/unit_test/dq_ui_push_cost_status
/datum/unit_test/dq_ui_push_cost_status/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/n = 50
	var/started = TICK_USAGE_REAL
	var/list/payload
	for(var/i in 1 to n)
		payload = list(
			global_data = SSstatpanels.global_data || list("Map: x"),
			ping_str = "Ping: 0ms (Average: 0ms)",
			other_str = H.get_status_tab_items(),
		)
	var/build_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/datum/tgui_window/dq_push_stub/W = allocate(/datum/tgui_window/dq_push_stub, null, "dq_push_stub_st", FALSE)
	W.status = TGUI_WINDOW_READY
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		W.send_message("update_stat", payload, same_key = "update_stat")
	var/send_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_ASSERT_EQUAL(length(W.sent), 1, "the same Status lines go out once")
	TEST_NOTICE(src, "UI_PUSH_COST status: [length(json_encode(payload))] bytes/push, build [round(build_ms, 0.001)] ms/push, send (unchanged after the first) [round(send_ms, 0.001)] ms/push")

