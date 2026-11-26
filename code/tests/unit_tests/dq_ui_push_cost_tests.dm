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


/// The op menu read the Abilities tab, the right-click menu and the Inspect tab share: a first read (a build) and a second read of the
/// unchanged menu (the cache), for a human's own menu and for another human as the target. A second read that rebuilds names what defeated the
/// cache (a read_once() sample, or the read owner whose generation moved).
/datum/unit_test/dq_ui_push_cost_op_menu
/datum/unit_test/dq_ui_push_cost_op_menu/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.add_shadekin(/datum/shadekin/full)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, get_step(test_floor(), EAST))
	op_menu_cache_clear()
	measure(H, H, "self")
	measure(H, other, "other human")
	// The same without the test build's debug checks (strict staleness checking, poisoned pools): what a production server pays.
	set_global(nameof(GLOB.staleness_on), FALSE)
	set_global(nameof(GLOB.pool_poison), FALSE)
	op_menu_cache_clear()
	measure(H, H, "self, production checks")
	measure(H, other, "other human, production checks")

/datum/unit_test/dq_ui_push_cost_op_menu/proc/measure(mob/living/carbon/human/H, atom/target, label)
	var/builds = GLOB.op_menu_builds
	var/started = TICK_USAGE_REAL
	var/list/rows = op_menu(H, target, null)
	var/first_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	var/n = 10
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		op_menu(H, target, null)
	var/warm_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/rebuilt = GLOB.op_menu_builds - builds - 1
	// A build of the menu once the world's lazy tables are warm: what a right-click on a target not yet asked about costs.
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		op_menu_cache_clear()
		op_menu(H, target, null)
	var/build_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_NOTICE(src, "UI_PUSH_COST op_menu [label]: warm build [round(build_ms, 0.01)] ms")
	TEST_NOTICE(src, "UI_PUSH_COST op_menu [label]: [length(rows)] rows, first read [round(first_ms, 0.01)] ms, unchanged read [round(warm_ms, 0.01)] ms, [rebuilt]/[n] unchanged reads rebuilt[rebuilt ? " ([why_uncached(H, target)])" : ""]")
	// The right-click menu's open: on a target not asked about yet (the menu is built), then again (the cached menu).
	op_menu_cache_clear()
	started = TICK_USAGE_REAL
	var/list/menu = interaction_menu_data(H, target)
	var/cold_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	started = TICK_USAGE_REAL
	interaction_menu_data(H, target)
	TEST_NOTICE(src, "UI_PUSH_COST right-click menu [label]: open [round(cold_ms, 0.01)] ms on a new target, [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01)] ms again, [length(json_encode(menu))] bytes")
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)

/// Why the cached menu of (H, target) was not used: the read_once() sampler, or the dependency whose generation moved.
/datum/unit_test/dq_ui_push_cost_op_menu/proc/why_uncached(mob/H, atom/target)
	var/datum/rx_state/actor_state = rx_of(H)
	var/datum/rx_state/target_state = rx_of(target)
	var/key = "[SHARED_CACHE_UID(H)]|[SHARED_CACHE_UID(target)]|-|[actor_state?.act_gen]|[target_state?.act_gen]||[actor_state?.provider_gen]"
	var/list/cached = GLOB.op_menu_cache[key]
	if(!cached)
		return "not stored: uncacheable (a requirement or condition sampled state with read_once())"
	if(!isnull(cached[2]))
		return "timed (a cooldown row): cached for one tick only"
	for(var/id in cached[3])
		var/list/record = cached[3][id]
		var/datum/D = handle_get(record[1])
		if(!D || rx_of(D).act_gen != record[2])
			return "dependency [D ? D.type : "deleted"] moved from generation [record[2]] to [D ? rx_of(D).act_gen : "-"]"
	return "stored and valid: the key moved (actor [actor_state?.act_gen], target [target_state?.act_gen])"


/// The Abilities tab's sprite sheet (code/content/abilities/ability_icons.dm): what building it costs, how big the download is, that every
/// ability type's button picture is in it, and the per-push icon cost with it (a sprite name) against the single cached images.
/datum/unit_test/dq_ui_push_cost_ability_sheet
/datum/unit_test/dq_ui_push_cost_ability_sheet/Run()
	var/built_at_boot = !!ability_sheet()
	var/started = TICK_USAGE_REAL
	var/datum/asset/spritesheet_batched/ability_icons/sheet = get_asset_datum(/datum/asset/spritesheet_batched/ability_icons)
	var/ready_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	TEST_ASSERT(sheet?.fully_generated, "the abilities sheet is built")
	if(!sheet?.fully_generated)
		return
	var/png_bytes = 0
	for(var/size_id in sheet.sizes)
		png_bytes += length(file("[SPRITESHEET_DIR][sheet.name]_[size_id].png"))
	var/css_bytes = length(file("[SPRITESHEET_DIR]spritesheet_[sheet.name].css"))
	var/missing = list()
	var/checked = 0
	for(var/datum/action/type as anything in typesof(/datum/action))
		var/icon_file = initial(type.button_icon)
		var/state = initial(type.button_icon_state)
		if(!isfile(icon_file) || isnull(state))
			continue
		checked++
		if(!sheet.icon_class_name(ability_sprite_id(ability_sheet_file_key(icon_file), state)))
			missing += "[type] ([icon_file]:[state])"
	TEST_NOTICE(src, "UI_PUSH_COST ability sheet: [built_at_boot ? "built at boot" : "built on first use in [round(ready_ms, 0.1)] ms"], [length(sheet.sprites)] sprites from [length(ability_sheet_files())] files, download [png_bytes] bytes png + [css_bytes] bytes css, [checked - length(missing)]/[checked] ability types' pictures in it")
	if(length(missing))
		TEST_NOTICE(src, "UI_PUSH_COST ability sheet: pictures not in their file: [jointext(missing, ", ")]")
	// Per-push icon cost for the button pictures of a shadekin's abilities: the cached single image (key lookup and per-client send) before, the
	// sprite name after.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.add_shadekin(/datum/shadekin/full)
	var/list/buttons = list()
	for(var/datum/action/entry as anything in ordered_abilities(H))
		if(entry.button_icon && !entry.ability_icon_source())
			buttons += entry
	TEST_ASSERT(length(buttons), "the shadekin has button pictures")
	var/n = 50
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		for(var/datum/action/entry as anything in buttons)
			CACHED3(icon_file_asset, entry.button_icon, isnull(entry.button_icon_state) ? "" : entry.button_icon_state, SOUTH)
	var/before_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		for(var/datum/action/entry as anything in buttons)
			sheet.icon_class_name(ability_sprite_id(ability_sheet_file_key(entry.button_icon), entry.button_icon_state))
	var/after_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_NOTICE(src, "UI_PUSH_COST ability sheet: [length(buttons)] button pictures per push, single cached images [round(before_ms, 0.001)] ms (+ one asset send per picture per client), sheet sprites [round(after_ms, 0.001)] ms (the sheet sent once per client)")

/// The inventory (strip) window of a dressed human: per push, every slot's picture as a base64 copy (before) against the cached icon state asset
/// (after: its address, the picture sent to a client once). Measured without a client, so the after side is the cache lookup.
/datum/unit_test/dq_ui_push_cost_inventory_icons
/datum/unit_test/dq_ui_push_cost_inventory_icons/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/black(H), SLOT_ID_SHOES)
	H.equip_to_slot_or_del(new /obj/item/clothing/gloves/black(H), SLOT_ID_GLOVES)
	H.put_in_r_hand(new /obj/item/flashlight(H))
	var/list/items = list()
	for(var/obj/item/I in H.get_equipped_items())
		items += I
	TEST_ASSERT(length(items) >= 3, "the human wears what the window shows")
	var/n = 10
	var/bytes_before = 0
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		bytes_before = 0
		for(var/obj/item/I as anything in items)
			bytes_before += length(icon2base64(icon(I.icon, I.icon_state, frame = 1)))
	var/before_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	for(var/obj/item/I as anything in items)
		CACHED3(icon_file_asset, I.icon, isnull(I.icon_state) ? "" : I.icon_state, SOUTH)
	var/bytes_after = 0
	started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		bytes_after = 0
		for(var/obj/item/I as anything in items)
			var/key = CACHED3(icon_file_asset, I.icon, isnull(I.icon_state) ? "" : I.icon_state, SOUTH)
			bytes_after += length(SSassets.get_asset_url(key))
	var/after_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	TEST_NOTICE(src, "UI_PUSH_COST inventory window: [length(items)] item pictures per push, base64 [round(before_ms, 0.001)] ms and [bytes_before] bytes, cached asset [round(after_ms, 0.001)] ms and [bytes_after] bytes")
	TEST_ASSERT(after_ms < before_ms, "the cached pictures cost less per push than base64 copies")
