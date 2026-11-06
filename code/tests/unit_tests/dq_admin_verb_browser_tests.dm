// The admin verb browser (code/content/admin/admin_verb_browser.dm): what it lists, what running a row does, the pins and the settings table.

/// A zero-argument admin verb used only by the tests below: running it counts a call on its singleton.
ADMIN_VERB(dq_avb_test_verb, R_SERVER, "DQ Browser Test Verb", "Unit test only.", ADMIN_CATEGORY_SERVER_GAME)
	var/datum/admin_verb/dq_avb_test_verb/self = SSadmin_verbs.admin_verbs_by_type[/datum/admin_verb/dq_avb_test_verb]
	self.calls++

/datum/admin_verb/dq_avb_test_verb
	var/calls = 0

/// The visibility flags that unlock every flag-gated verb.
/datum/unit_test/proc/dq_avb_all_flags()
	return list(ADMIN_VERB_VISIBLITY_FLAG_LOCALHOST, ADMIN_VERB_VISIBLITY_FLAG_MAPPING_DEBUG)

/// The browser lists exactly the verbs the rights allow: never a verb the rights do not cover, never a context-menu-only verb.
/datum/unit_test/dq_admin_verb_browser_lists_only_permitted

/datum/unit_test/dq_admin_verb_browser_lists_only_permitted/Run()
	var/list/flags = dq_avb_all_flags()
	var/list/everything = SSadmin_verbs.browser_verbs(R_EVERYTHING, flags)
	TEST_ASSERT(length(everything) > 50, "an admin with every right should see the verbs, saw [length(everything)]")

	var/list/names = list()
	for(var/datum/admin_verb/V as anything in everything)
		TEST_ASSERT(istext(V.category), "[V.id] has no category: a context-menu-only verb must not be listed")
		TEST_ASSERT(!(V.name in names), "[V.name] is listed twice: a name is one command, so the browser lists it once")
		names += V.name
	TEST_ASSERT(!("Show Player Panel" in names), "Show Player Panel is context-menu only and must not be listed")

	// Rights narrow the list: R_DEBUG sees only the verbs that name R_DEBUG (or no right).
	for(var/datum/admin_verb/V as anything in SSadmin_verbs.browser_verbs(R_DEBUG, flags))
		TEST_ASSERT(V.permissions == R_NONE || (V.permissions & R_DEBUG), "[V.id] needs [V.permissions] but was listed for R_DEBUG alone")
	var/list/debug_ids = admin_verb_id_set(SSadmin_verbs.browser_verbs(R_DEBUG, flags))
	TEST_ASSERT(debug_ids["advanced_proc_call"], "Advanced ProcCall (R_DEBUG) should be listed for R_DEBUG")
	TEST_ASSERT(!debug_ids["restart"], "Reboot World (R_SERVER) must not be listed for R_DEBUG")
	TEST_ASSERT(!debug_ids["unban_panel"], "Unbanning Panel (R_BAN) must not be listed for R_DEBUG")

	var/list/server_ids = admin_verb_id_set(SSadmin_verbs.browser_verbs(R_SERVER, flags))
	TEST_ASSERT(server_ids["restart"], "Reboot World (R_SERVER) should be listed for R_SERVER")
	TEST_ASSERT(!server_ids["advanced_proc_call"], "Advanced ProcCall (R_DEBUG) must not be listed for R_SERVER")

	for(var/datum/admin_verb/V as anything in SSadmin_verbs.browser_verbs(NONE, flags))
		TEST_ASSERT_EQUAL(V.permissions, R_NONE, "[V.id] needs rights but was listed for an admin with none")

/// A verb behind a visibility flag is listed only to an admin who has the flag.
/datum/unit_test/dq_admin_verb_browser_respects_visibility_flags

/datum/unit_test/dq_admin_verb_browser_respects_visibility_flags/Run()
	var/found_flagged = FALSE
	for(var/verb_type in SSadmin_verbs.admin_verbs_by_type)
		var/datum/admin_verb/V = SSadmin_verbs.admin_verbs_by_type[verb_type]
		if(!V.visibility_flag || !istext(V.category))
			continue
		found_flagged = TRUE
		var/list/without = admin_verb_id_set(SSadmin_verbs.browser_verbs(R_EVERYTHING, list()))
		var/list/with = admin_verb_id_set(SSadmin_verbs.browser_verbs(R_EVERYTHING, list(V.visibility_flag)))
		TEST_ASSERT(!without[V.id], "[V.id] needs the [V.visibility_flag] flag but was listed without it")
		TEST_ASSERT(with[V.id], "[V.id] should be listed to an admin with the [V.visibility_flag] flag")
		break
	TEST_ASSERT(found_flagged, "no flag-gated admin verb was found to test")

/// Running a row resolves to the verb that was listed (rights checked), and that verb's body is the one that runs.
/datum/unit_test/dq_admin_verb_browser_invoking_runs_the_verb

/datum/unit_test/dq_admin_verb_browser_invoking_runs_the_verb/Run()
	var/list/flags = dq_avb_all_flags()
	var/datum/admin_verb/dq_avb_test_verb/test_verb = SSadmin_verbs.admin_verbs_by_type[/datum/admin_verb/dq_avb_test_verb]
	TEST_ASSERT_NOTNULL(test_verb, "the test verb should be registered")
	TEST_ASSERT_EQUAL(test_verb.id, "dq_avb_test_verb", "a verb's id is its ADMIN_VERB path name")
	TEST_ASSERT_EQUAL(SSadmin_verbs.admin_verbs_by_id["dq_avb_test_verb"], test_verb, "the id registry should find the verb")

	TEST_ASSERT_NULL(SSadmin_verbs.browser_resolve("dq_avb_test_verb", R_DEBUG, flags), "an admin without R_SERVER must not resolve a R_SERVER verb")
	TEST_ASSERT_NULL(SSadmin_verbs.browser_resolve("not_a_real_verb", R_EVERYTHING, flags), "an unknown id resolves to nothing")
	TEST_ASSERT_NULL(SSadmin_verbs.browser_resolve("show_player_panel", R_EVERYTHING, flags), "a context-menu-only verb is not run from the browser")

	var/datum/admin_verb/resolved = SSadmin_verbs.browser_resolve("dq_avb_test_verb", R_SERVER, flags)
	TEST_ASSERT_EQUAL(resolved, test_verb, "R_SERVER resolves the verb")
	TEST_ASSERT_EQUAL(test_verb.calls, 0, "the verb has not run yet")
	resolved.__avd_do_verb(null)
	TEST_ASSERT_EQUAL(test_verb.calls, 1, "the resolved verb's body should be the one that runs")
	// The command is the one the verb panel sends: the verb's name with dashes.
	TEST_ASSERT_EQUAL(test_verb.command(), "DQ-Browser-Test-Verb", "the command is the verb name with dashes, as the verb panel sends it")

/// The default pins are real verbs, few enough for a small panel, and the pin helpers behave.
/datum/unit_test/dq_admin_verb_browser_pins

/datum/unit_test/dq_admin_verb_browser_pins/Run()
	var/list/defaults = admin_verb_default_pins()
	TEST_ASSERT(length(defaults) >= 20 && length(defaults) <= 30, "the default pin set should be about 25 verbs, found [length(defaults)]")
	TEST_ASSERT("admin_verb_browser" in defaults, "the Admin Verbs button is always pinned")
	for(var/id in defaults)
		TEST_ASSERT(SSadmin_verbs.admin_verbs_by_id[id], "default pin [id] is not a registered admin verb")
		TEST_ASSERT(istext(SSadmin_verbs.admin_verbs_by_id[id].category), "default pin [id] has no category, so the panel could not show it")

	TEST_ASSERT_EQUAL(jointext(admin_verb_pins_from_pref(ADMIN_VERB_PINS_UNSET), ","), jointext(defaults, ","), "an unset preference means the default set")
	TEST_ASSERT_EQUAL(jointext(admin_verb_pins_from_pref(null), ","), jointext(defaults, ","), "no preference yet means the default set")
	TEST_ASSERT_EQUAL(length(admin_verb_pins_from_pref(ADMIN_VERB_PINS_NONE)), 1, "the none marker reads as a single unknown id, not the defaults")
	TEST_ASSERT_EQUAL(jointext(admin_verb_ids_from_text("a,b,a,,c"), ","), "a,b,c", "ids split on commas, once each, no blanks")
	TEST_ASSERT_EQUAL(admin_verb_ids_to_text(list("a", "b")), "a,b", "ids join with commas")
	TEST_ASSERT_EQUAL(admin_verb_ids_to_text(list()), ADMIN_VERB_PINS_NONE, "an empty list is written as the none marker")
	TEST_ASSERT_EQUAL(jointext(admin_verb_ids_flipped(list("a"), "b"), ","), "a,b", "an unpinned verb is added")
	TEST_ASSERT_EQUAL(jointext(admin_verb_ids_flipped(list("a", "b"), "a"), ","), "b", "a pinned verb is removed")
	TEST_ASSERT_EQUAL(jointext(admin_verb_ids_touched(list("a", "b", "c"), "c"), ","), "c,a,b", "a used verb moves to the front")
	var/list/many = list()
	for(var/i in 1 to ADMIN_VERB_RECENT_MAX + 5)
		many = admin_verb_ids_touched(many, "v[i]")
	TEST_ASSERT_EQUAL(length(many), ADMIN_VERB_RECENT_MAX, "the recent list is capped")
	TEST_ASSERT_EQUAL(jointext(admin_verb_ids_known(list("a", "b", "c"), list("a" = TRUE, "c" = TRUE)), ","), "a,c", "ids the admin's rights do not cover are dropped")

	for(var/pref_type in list(/datum/preference/text/admin_verb_pins, /datum/preference/text/admin_verb_recent))
		TEST_ASSERT_NOTNULL(GLOB.preference_entries[pref_type], "[pref_type] should be a registered preference")
	var/datum/preference/pins_pref = GLOB.preference_entries[/datum/preference/text/admin_verb_pins]
	TEST_ASSERT_EQUAL(pins_pref.create_default_value(), ADMIN_VERB_PINS_UNSET, "a new admin starts on the default pins")

/// The server settings panel names real verbs, reads a live state for each, and picks the verb the rights allow.
/datum/unit_test/dq_admin_verb_browser_settings

/datum/unit_test/dq_admin_verb_browser_settings/Run()
	var/list/flags = dq_avb_all_flags()
	var/list/seen = list()
	for(var/list/row as anything in admin_setting_table())
		TEST_ASSERT(!(row[1] in seen), "setting [row[1]] is in the table twice")
		seen += row[1]
		TEST_ASSERT(!isnull(admin_setting_state(row[1])), "setting [row[1]] has no state read")
		TEST_ASSERT(length(row[5]) >= 1, "setting [row[1]] names no verb")
		for(var/verb_id in row[5])
			var/datum/admin_verb/V = SSadmin_verbs.admin_verbs_by_id[verb_id]
			TEST_ASSERT_NOTNULL(V, "setting [row[1]] names [verb_id], which is not an admin verb")
			TEST_ASSERT(istext(V.category), "setting [row[1]]'s verb [verb_id] has no category")
	TEST_ASSERT(length(seen) >= 20, "the settings panel should hold the server toggles, found [length(seen)]")
	TEST_ASSERT_NULL(admin_setting_state("not_a_setting"), "an unknown setting has no state")

	var/list/enter_row
	var/list/aliens_row
	for(var/list/row as anything in admin_setting_table())
		if(row[1] == "enter")
			enter_row = row
		if(row[1] == "aliens")
			aliens_row = row
	TEST_ASSERT_NULL(admin_setting_verb(enter_row, R_DEBUG, flags), "Toggle Entering needs R_SERVER or R_ADMIN, not R_DEBUG")
	var/datum/admin_verb/enter_verb = admin_setting_verb(enter_row, R_SERVER, flags)
	TEST_ASSERT_EQUAL(enter_verb?.id, "toggleenter", "R_SERVER may flip Toggle Entering")
	// The two Toggle Aliens verbs are one row: each right reaches its own verb.
	TEST_ASSERT_EQUAL(admin_setting_verb(aliens_row, R_FUN, flags)?.id, "toggle_aliens", "R_FUN flips aliens with the admin verb")
	TEST_ASSERT_EQUAL(admin_setting_verb(aliens_row, R_DEBUG, flags)?.id, "cmd_debug_tog_aliens", "R_DEBUG flips aliens with the debug verb")
	TEST_ASSERT_NULL(admin_setting_verb(aliens_row, R_BAN, flags), "R_BAN may not flip aliens")
