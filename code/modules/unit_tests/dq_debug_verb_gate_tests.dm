// Debug verbs must not be native /client/verb entries.
//
// A native verb on /client is given to every client by BYOND, and an in-body check_rights() only stops
// the call, not the "Debug" tab: every player saw the expedition generators. ADMIN_VERB grants the verb
// only to admins holding the right, and re-checks it at call time (SSadmin_verbs.dynamic_invoke_verb).

/datum/unit_test/dq_debug_verbs_admin_only

/// The verbs that used to be native /client/verb entries: ADMIN_VERB datum type -> the name they carried.
/datum/unit_test/dq_debug_verbs_admin_only/proc/former_native_verbs()
	var/static/list/former = list(
		/datum/admin_verb/generate_procedural_station = "Generate Procedural Station",
		/datum/admin_verb/generate_expedition_site = "Generate Expedition Site",
		/datum/admin_verb/generate_expedition_mission = "Generate Expedition Mission",
		/datum/admin_verb/show_generated_station_architecture = "Show Generated Station Architecture",
	)
	return former

/datum/unit_test/dq_debug_verbs_admin_only/Run()
	var/list/former = former_native_verbs()
	var/list/former_names = list()
	for(var/verb_type in former)
		former_names += former[verb_type]

	var/debug_prefix = "[ADMIN_CATEGORY_DEBUG]."
	var/reload_configuration_procs = 0
	for(var/native_path in typesof(/client/verb))
		var/procpath/native_verb = native_path
		TEST_ASSERT(!(native_verb.name in former_names), "[native_path] is a native /client/verb again: it is on every client. Declare it with ADMIN_VERB(..., R_DEBUG, ...).")
		var/category = native_verb.category
		if(!istext(category))
			continue
		TEST_ASSERT(category != ADMIN_CATEGORY_DEBUG && copytext(category, 1, length(debug_prefix) + 1) != debug_prefix, "[native_path] is a native /client/verb in the Debug tab ([category]): every client sees it. Use ADMIN_VERB(..., R_DEBUG, ...).")

	for(var/verb_type in former)
		var/datum/admin_verb/registered = SSadmin_verbs.admin_verbs_by_type[verb_type]
		TEST_ASSERT_NOTNULL(registered, "[verb_type] is not a registered admin verb.")
		TEST_ASSERT_EQUAL(registered.permissions, R_DEBUG, "[verb_type] must require exactly R_DEBUG.")
		TEST_ASSERT_EQUAL(registered.name, former[verb_type], "[verb_type] changed its name.")
		TEST_ASSERT(istext(registered.category) && findtext(registered.category, ADMIN_CATEGORY_DEBUG) == 1, "[verb_type] left the Debug category ([registered.category]).")

	// The panel dedupes verbs by name, so a legacy /client/proc beside the ADMIN_VERB of the same name is dead weight.
	for(var/proc_path in typesof(/client/proc))
		var/procpath/native_proc = proc_path
		if(native_proc.name == "Reload Configuration")
			reload_configuration_procs++
	TEST_ASSERT_EQUAL(reload_configuration_procs, 1, "Reload Configuration must be declared exactly once (the ADMIN_VERB), found [reload_configuration_procs].")
