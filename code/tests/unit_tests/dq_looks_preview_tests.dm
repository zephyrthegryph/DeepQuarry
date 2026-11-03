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

/// The first coloured style of `styles` this character may wear that is not `except` (a colour change must show).
/proc/dq_test_wearable_style(datum/preferences/P, list/styles, except)
	var/list/available = P.get_available_styles(styles)
	for(var/name in available)
		var/datum/sprite_accessory/S = available[name]
		if(istype(S) && S.do_colouration && name != except && !istaurtail(S))
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
