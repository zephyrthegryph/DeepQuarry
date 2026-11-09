// The character preview follows every Looks change.

/// What the preview would show of these preferences now: the mannequin dressed and drawn as the preview does, as the iconforge sprite tree.
/proc/dq_test_preview_signature(datum/preferences/P)
	var/mob/living/carbon/human/dummy/mannequin/mannequin = get_mannequin(P.client_ckey)
	mannequin.delete_inventory(TRUE)
	P.dress_preview_mob(mannequin)
	mannequin.set_dir(SOUTH)
	draw_now(mannequin)
	var/datum/dq_preview_flattener/flattener = new
	var/list/flat = flattener.flatten(mannequin, SOUTH)
	return "[json_encode(flat)]|[flattener.unsupported]"

/// The first coloured style of `styles` this character may wear that is not `except` and has a sprite to draw (a colour change must show).
/proc/dq_test_wearable_style(datum/preferences/P, list/styles, except)
	var/list/available = P.get_available_styles(styles)
	for(var/name in available)
		var/datum/sprite_accessory/S = available[name]
		if(istype(S) && S.do_colouration && name != except && !istaurtail(S) && icon_exists(S.icon, S.icon_state))
			return name

/// Each Looks change schedules a preview render (south now, every direction after), and that render draws the change.
/datum/unit_test/dq_looks_change_regenerates_preview

/datum/unit_test/dq_looks_change_regenerates_preview/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference_editor/legs/legs = GLOB.preference_editors_by_key["legs"]
	var/ears = dq_test_wearable_style(P, GLOB.ear_styles_list)
	var/tail = dq_test_wearable_style(P, GLOB.tail_styles_list)
	var/wings = dq_test_wearable_style(P, GLOB.wing_styles_list)
	TEST_ASSERT_NOTNULL(ears, "a Human may wear some ears")
	TEST_ASSERT_NOTNULL(tail, "and some tail")
	TEST_ASSERT_NOTNULL(wings, "and some wings")
	var/list/changes = list(
		list("ear_style", ears),
		list("ears_color1", "#12ab34"),
		list("tail_style", tail),
		list("tail_color1", "#3456cd"),
		list("wing_style", wings),
		list("wing_color1", "#ab1234"),
		list("eyes_color", "#2e6f9e"),
		list("eyes_color", "primary"),
		list("palette_primary", "#223344"),
		list("legs", "digitigrade"),
		list("legs", "plantigrade"),
		list("ear_style", ""),
		list("wing_style", ""),
	)
	for(var/list/change in changes)
		var/key = change[1]
		var/value = change[2]
		var/before = dq_test_preview_signature(P)
		var/generation = P.dq_preview_generation
		cancel_after(P, "preferences_preview_full")
		if(key == "legs")
			TEST_ASSERT_EQUAL(legs.handle_action(P, "set_leg_style", list("style" = value), null), PREF_UPDATE_ACCEPTED, "legs [value] accepted")
		else
			TEST_ASSERT(P.update_preference(GLOB.preference_entries_by_key[key], value), "[key] = [value] accepted")
		TEST_ASSERT(P.dq_preview_generation > generation, "[key] = [value] started a preview render")
		TEST_ASSERT(after_left(P, "preferences_preview_full") > 0, "[key] = [value] scheduled the render of every direction")
		TEST_ASSERT_NOTEQUAL(dq_test_preview_signature(P), before, "[key] = [value] changed what the preview draws")
	cancel_after(P, "preferences_preview_full")

	// The render lands and goes out: the new frames reach the windows (the data push runs), every direction included.
	var/version = P.dq_preview_version
	var/full_generation = P.dq_preview_generation
	P.update_preference(GLOB.preference_entries_by_key["tail_color1"], "#445566")
	var/deadline = world.time + 15 SECONDS
	UNTIL((P.dq_preview_generation > full_generation + 1 && !P.dq_preview_jobs_in_flight && !P.dq_data_push_pending) || world.time > deadline)
	log_world("dq_looks_change_regenerates_preview: generation [full_generation] -> [P.dq_preview_generation], version [version] -> [P.dq_preview_version], jobs [P.dq_preview_jobs_in_flight], push pending [P.dq_data_push_pending], full pending [after_left(P, "preferences_preview_full")], fallback [P.dq_last_preview_fallback]")
	TEST_ASSERT(P.dq_preview_generation > full_generation + 1, "the render of every direction ran after the south one")
	TEST_ASSERT(P.dq_preview_version > version, "a render landed")
	TEST_ASSERT_EQUAL(length(P.character_preview_b64 & list("south", "north", "east", "west")), 4, "with every direction")
	TEST_ASSERT(!P.dq_data_push_pending, "and its push to the windows went out")
	fdel(P.path)
	qdel(P, TRUE)

/// New preview frames reach every open window: each window's push carries them (two windows here, as dq_flush_data_push() pushes
/// each open one), and once that push ran the frames stop riding along. They were once versioned per window by the user's first
/// window, so a second window never got them.
/datum/unit_test/dq_preview_frames_reach_every_window

/datum/unit_test/dq_preview_frames_reach_every_window/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/version = P.dq_preview_version
	P.update_preference(GLOB.preference_entries_by_key["eyes_color"], "#2e6f9e")
	var/deadline = world.time + 15 SECONDS
	UNTIL((P.dq_preview_version > version && !P.dq_preview_jobs_in_flight) || world.time > deadline)
	TEST_ASSERT(P.dq_preview_version > version, "the Looks change rendered new frames")
	TEST_ASSERT(P.dq_preview_unsent, "with no window open yet the frames wait for one")
	var/list/first_window = P.ui_data_datum_preferences(null, null, null)
	var/list/second_window = P.ui_data_datum_preferences(null, null, null)
	TEST_ASSERT_NOTNULL(first_window["character_preview_assets"], "the first window's push carries the new frames")
	TEST_ASSERT_NOTNULL(second_window["character_preview_assets"], "and so does the second window's")
	TEST_ASSERT_EQUAL(second_window["character_preview_assets"]["south"], P.character_preview_b64["south"], "the new south frame")
	P.set_dq_preview_unsent(FALSE) // what dq_flush_data_push() does once every open window had its push
	TEST_ASSERT_NULL(P.ui_data_datum_preferences(null, null, null)["character_preview_assets"], "a later push does not resend them")
	P.tgui_close(null)
	TEST_ASSERT_NOTNULL(P.ui_data_datum_preferences(null, null, null)["character_preview_assets"], "a reopened window gets them again")
	fdel(P.path)
	qdel(P, TRUE)

/// Waits for the preview render a change started (the south one and every direction) to land. Returns the frames.
/proc/dq_test_wait_preview(datum/preferences/P, generation)
	var/deadline = world.time + 15 SECONDS
	UNTIL((P.dq_preview_generation > generation + 1 && !P.dq_preview_jobs_in_flight) || world.time > deadline)
	return P.character_preview_b64?.Copy()

/// The wings in the preview frames follow the wing style and the wing colour (the rendered frames, through the real async path).
/datum/unit_test/dq_preview_frames_follow_wings

/datum/unit_test/dq_preview_frames_follow_wings/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	// The preview no longer animates (the Animate preference was cut in Settings audit 2), so any two coloured wings will do.
	var/list/animated = list()
	var/list/available = P.get_available_styles(GLOB.wing_styles_list)
	for(var/name in available)
		var/datum/sprite_accessory/wing/W = available[name]
		if(istype(W) && W.do_colouration)
			animated += name
	log_world("dq_preview_frames_follow_wings: coloured wings: [jointext(animated, ", ")]")
	var/first = length(animated) ? animated[1] : dq_test_wearable_style(P, GLOB.wing_styles_list)
	var/second = length(animated) >= 2 ? animated[2] : dq_test_wearable_style(P, GLOB.wing_styles_list, first)
	TEST_ASSERT_NOTNULL(second, "two coloured wing styles to choose between")
	var/list/steps = list(
		list("wing_style", first),
		list("wing_style", second),
		list("wing_color1", "#ff2200"),
		list("wing_color1", "#0022ff"),
		list("wing_style", ""),
	)
	var/list/frames = dq_test_wait_preview(P, P.dq_preview_generation - 2)
	for(var/list/step in steps)
		var/generation = P.dq_preview_generation
		TEST_ASSERT(P.update_preference(GLOB.preference_entries_by_key[step[1]], step[2]), "[step[1]] = [step[2]] accepted")
		var/list/now = dq_test_wait_preview(P, generation)
		var/mob/living/carbon/human/M = get_mannequin(P.client_ckey)
		log_world("dq_preview_frames_follow_wings: [step[1]] = [step[2]]: wing_style [M.wing_style?.name] hidden [M.wings_hidden] flapping [M.flapping] colour [M.looks.wing_color] fallback [P.dq_last_preview_fallback]")
		for(var/dir in list("south", "north"))
			TEST_ASSERT_NOTEQUAL(now?[dir], frames?[dir], "[step[1]] = [step[2]] changed the [dir] frame")
		frames = now
	fdel(P.path)
	qdel(P, TRUE)

/// The playtester's setup (animated preview, no outfit, Cyber dragon wings on the palette): wing changes reach the frames.
/datum/unit_test/dq_preview_frames_follow_linked_wings

/datum/unit_test/dq_preview_frames_follow_linked_wings/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs(list("animations_toggle" = 1, "preview_job" = 0, "preview_loadout" = 0, "wing_style" = "Cyber dragon wing (colorable)", "wing_color1" = "primary", "wing_color2" = "secondary", "wing_color3" = "tertiary"))
	var/list/steps = list(
		list("wing_color1", "secondary"),
		list("palette_secondary", "#ff2200"),
		list("wing_color1", "#00ff22"),
		list("wing_style", "Cyber doe wing"),
		list("wing_style", "Cyber dragon wing (colorable)"),
		list("wing_style", ""),
	)
	var/list/frames = dq_test_wait_preview(P, P.dq_preview_generation - 2)
	P.update_preview_icon()
	frames = dq_test_wait_preview(P, P.dq_preview_generation - 1)
	for(var/list/step in steps)
		var/generation = P.dq_preview_generation
		var/mob/living/carbon/human/M = get_mannequin(P.client_ckey)
		var/sig_before = dq_test_preview_signature(P)
		var/colour_before = M.looks.wing_color
		TEST_ASSERT(P.update_preference(GLOB.preference_entries_by_key[step[1]], step[2]), "[step[1]] = [step[2]] accepted")
		var/list/now = dq_test_wait_preview(P, generation)
		var/sig_after = dq_test_preview_signature(P)
		log_world("dq_preview_frames_follow_linked_wings: [step[1]] = [step[2]]: colour [colour_before] -> [M.looks.wing_color]; signature changed [sig_before != sig_after]; south changed [now?["south"] != frames?["south"]]; generation [generation] -> [P.dq_preview_generation]; fallback [P.dq_last_preview_fallback]; wing key [look_part_key(M.wing_look(FALSE))]; overlays [length(M.overlays)]; rx key [length(M.rx?.look_key)]")
		if(now?["south"] == frames?["south"])
			TEST_FAIL("[step[1]] = [step[2]] left the south frame as it was")
		frames = now
	fdel(P.path)
	qdel(P, TRUE)

/// A taur body keeps the tail it replaces: the Tail row shows it greyed, only the taur is worn, and removing the taur wears the tail again.
/datum/unit_test/dq_taur_keeps_tail

/datum/unit_test/dq_taur_keeps_tail/Run()
	var/datum/preferences/dq_test_stub/P = dq_palette_test_prefs()
	var/datum/preference_editor/legs/legs = GLOB.preference_editors_by_key["legs"]
	var/tail = dq_test_wearable_style(P, GLOB.tail_styles_list)
	var/taur
	for(var/key in GLOB.tail_styles_list)
		var/datum/sprite_accessory/S = GLOB.tail_styles_list[key]
		if(istype(S) && istaurtail(S) && (S.name in P.get_available_styles(GLOB.tail_styles_list)))
			taur = S.name
			break
	TEST_ASSERT_NOTNULL(tail, "a tail to keep")
	TEST_ASSERT_NOTNULL(taur, "a taur body to wear")
	P.update_preference(GLOB.preference_entries_by_key["tail_style"], tail)
	var/datum/preference/tail_pref = GLOB.preference_entries_by_key["tail_style"]

	TEST_ASSERT_EQUAL(legs.handle_action(P, "set_leg_style", list("style" = taur), null), PREF_UPDATE_ACCEPTED, "the taur is accepted")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/tail_style), taur, "the taur body is worn as the tail style")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/tail_style_under_taur), tail, "the tail is kept, not cleared")
	TEST_ASSERT_EQUAL(tail_pref.get_widget_props(P)["under_taur"], tail, "the greyed Tail row is told which tail it shows")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	P.copy_to(H)
	TEST_ASSERT_EQUAL(H.tail_style?.name, taur, "only the taur is drawn while it is worn")

	TEST_ASSERT_EQUAL(legs.handle_action(P, "set_leg_style", list("style" = "plantigrade"), null), PREF_UPDATE_ACCEPTED, "Normal legs are accepted")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/text/human/tail_style), tail, "removing the taur wears the kept tail again")
	TEST_ASSERT(!P.read_preference(/datum/preference/text/human/tail_style_under_taur), "and nothing is kept any more")
	P.copy_to(H)
	TEST_ASSERT_EQUAL(H.tail_style?.name, tail, "the tail is drawn again")
	cancel_after(P, "preferences_preview_full")
	fdel(P.path)
	qdel(P, TRUE)
