// Character setup capture (developer tool). With a save at data/ui_capture/save.json (a copy of a player's
// preferences.json; gitignored), writes data/ui_capture/prefs.json — the window payload for every character tab,
// catalogs included — for data/ui_capture/harness.html, and data/ui_capture/timings.json: per tab, the server time
// and payload size of a first visit and of a revisit, and of a first visit from a second player's prefs (what the
// shared caches buy). Without the save it does nothing, so it is safe in every run.
//   bash tools/dq_focused_test.sh /datum/unit_test/dq_ui_capture_prefs
//   python -m http.server 8731 --directory .   ->  http://localhost:8731/data/ui_capture/harness.html?cat=identity

#define DQ_UI_CAPTURE_DIR "data/ui_capture/"

/// A prefs datum loaded from a save path with no client.
/datum/preferences/dq_ui_capture

/datum/preferences/dq_ui_capture/New(path_override)
	for(var/middleware_type in subtypesof(/datum/preference_middleware))
		rel_add(src, nameof(middleware), new middleware_type(src))
	client_ckey = "ui_capture"
	path = path_override
	load_savefile()
	load_character()

/// One tab switch the way the window does it: select the category (asking for catalogs when the client has none),
/// then build the update. Returns list(ms, bytes, payload).
/datum/preferences/dq_ui_capture/proc/switch_to(category, force_catalogs)
	var/started = TICK_USAGE_REAL
	var/datum/preference_middleware/character_setup/setup = locate() in middleware
	dq_category_index = dq_category_index || dq_character_category_index(read_preference(/datum/preference/text/human/play_mode) || "human")
	dq_active_category = category
	if(force_catalogs)
		LAZYINITLIST(dq_force_catalogs_by_window)
		dq_force_catalogs_by_window["unpooled"] = TRUE
	setup?.dq_note_category_selected(category, "unpooled", force_catalogs)
	var/list/payload = ui_data_datum_preferences(null, null, null)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	return list(ms, length(json_encode(payload)), payload)

/datum/unit_test/dq_ui_capture_prefs

/datum/unit_test/dq_ui_capture_prefs/Run()
	if(!fexists(DQ_UI_CAPTURE_DIR + "save.json"))
		return // no local save: nothing to capture
	fdel(DQ_UI_CAPTURE_DIR + "prefs.json")
	fdel(DQ_UI_CAPTURE_DIR + "timings.json")
	var/datum/preferences/dq_ui_capture/P = new(DQ_UI_CAPTURE_DIR + "save.json")
	P.set_current_window(PREFERENCE_TAB_CHARACTER_PREFERENCES)
	var/list/static_data = P.tgui_static_data(null)
	var/list/index = dq_character_category_index(P.read_preference(/datum/preference/text/human/play_mode) || "human")
	var/list/out = list("static_data" = static_data, "index" = index, "categories" = list())
	var/list/timings = list()
	for(var/cat in index)
		var/list/first = P.switch_to(cat, TRUE)
		out["categories"][cat] = first[3]
		timings[cat] = list("first_ms" = first[1], "first_bytes" = first[2], "catalog_build_ms" = first[3]["dq_catalog_build_ms"])
	for(var/cat in index)
		var/list/again = P.switch_to(cat, FALSE)
		timings[cat]["revisit_ms"] = again[1]
		timings[cat]["revisit_bytes"] = again[2]
	// A second player's prefs on the same save: what global caches save a fresh session.
	var/datum/preferences/dq_ui_capture/Q = new(DQ_UI_CAPTURE_DIR + "save.json")
	Q.set_current_window(PREFERENCE_TAB_CHARACTER_PREFERENCES)
	for(var/cat in index)
		var/list/fresh = Q.switch_to(cat, TRUE)
		timings[cat]["second_session_first_ms"] = fresh[1]
	// A third session that prefetches every tab once (what the window does after its first page), then switches.
	var/datum/preferences/dq_ui_capture/R = new(DQ_UI_CAPTURE_DIR + "save.json")
	R.set_current_window(PREFERENCE_TAB_CHARACTER_PREFERENCES)
	R.switch_to(index[1], TRUE)
	LAZYINITLIST(R.dq_prefetch_by_window)
	R.dq_prefetch_by_window["unpooled"] = TRUE
	var/prefetch_started = TICK_USAGE_REAL
	var/list/prefetch_payload = R.ui_data_datum_preferences(null, null, null)
	timings["_prefetch"] = list("ms" = TICK_DELTA_TO_MS(TICK_USAGE_REAL - prefetch_started), "bytes" = length(json_encode(prefetch_payload)))
	for(var/cat in index)
		var/list/after = R.switch_to(cat, FALSE)
		timings[cat]["after_prefetch_switch_ms"] = after[1]
		timings[cat]["after_prefetch_switch_bytes"] = after[2]
	text2file(json_encode(out), DQ_UI_CAPTURE_DIR + "prefs.json")
	text2file(json_encode(timings), DQ_UI_CAPTURE_DIR + "timings.json")
	log_world("UI_CAPTURE wrote [length(index)] categories: [json_encode(timings)]")
	TEST_ASSERT_EQUAL(P.read_preference(/datum/preference/name/real_name), P.savefile.get_entry("character[P.default_slot]")?["real_name"], "the captured character is the saved one")

#undef DQ_UI_CAPTURE_DIR
