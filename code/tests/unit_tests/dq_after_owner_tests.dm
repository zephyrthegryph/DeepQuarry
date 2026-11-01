// after(owner, delay, handler, ...): a call written with its owner missing used to return silently (the delay landed in the owner slot).

/datum/after_owner_probe
	var/fired = 0

/datum/after_owner_probe/proc/fire()
	fired++

/// A non-datum owner is a programmer error: the call reports a runtime and schedules nothing, on both clocks.
/datum/unit_test/dq_after_owner_misordered_is_loud

/datum/unit_test/dq_after_owner_misordered_is_loud/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/delay = 1 SECONDS // the misordered call goes through call() so the argument-order lint (which reads the source line) does not see it
	var/handler = TYPE_PROC_REF(/datum/after_owner_probe, fire)
	var/reported = 0
	var/own_id = 0
	var/world_id = 0
	// stack_trace() raises the runtime; the test catches it (a production call logs it and goes on).
	try
		own_id = call(GLOBAL_PROC_REF(after))(delay, handler, handler, null, CLOCK_OWN, list(probe))
	catch(var/exception/own_fault)
		reported++
		TEST_ASSERT(findtext(own_fault.name, "owner must be a datum"), "the report names the mistake: [own_fault.name]")
	try
		world_id = call(GLOBAL_PROC_REF(after))(delay, handler, handler, null, CLOCK_WORLD, list(probe))
	catch(var/exception/world_fault)
		reported++
		TEST_ASSERT(findtext(world_fault.name, "owner must be a datum"), "the report names the mistake: [world_fault.name]")
	TEST_ASSERT_EQUAL(reported, 2, "each misordered after() reports a runtime instead of returning silently")
	TEST_ASSERT(!own_id && !world_id, "a misordered after() schedules nothing")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(probe.fired, 0, "a misordered after() never fires")

/// The correct form still schedules and fires, with a datum owner and with the global owner.
/datum/unit_test/dq_after_owner_correct_forms_fire

/datum/unit_test/dq_after_owner_correct_forms_fire/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/runtimes_at_start = GLOB.total_runtimes
	TEST_ASSERT(after(probe, 1 SECONDS, TYPE_PROC_REF(/datum/after_owner_probe, fire)), "an owned timer is scheduled")
	TEST_ASSERT(after(probe, 1 SECONDS, TYPE_PROC_REF(/datum/after_owner_probe, fire), clock = CLOCK_WORLD), "an owned world timer is scheduled")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(probe.fired, 2, "both timers fire")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, runtimes_at_start, "the correct form reports nothing")

/// after(src, PROC_REF(x), delay) and a delay that is not a number: reported, and a number handler schedules nothing.
/datum/unit_test/dq_after_bad_delay_or_handler_is_loud

/datum/unit_test/dq_after_bad_delay_or_handler_is_loud/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/datum/after_owner_probe/probe = allocate(/datum/after_owner_probe)
	var/handler = TYPE_PROC_REF(/datum/after_owner_probe, fire)
	var/reported = 0
	var/swapped_id = 0
	try
		swapped_id = call(GLOBAL_PROC_REF(after))(probe, handler, 1 SECONDS)
	catch(var/exception/swapped_fault)
		reported++
		TEST_ASSERT(findtext(swapped_fault.name, "handler must be a proc reference"), "the report names the mistake: [swapped_fault.name]")
	TEST_ASSERT_EQUAL(reported, 1, "swapped arguments report a runtime")
	TEST_ASSERT(!swapped_id, "swapped arguments schedule nothing")
	try
		call(GLOBAL_PROC_REF(after))(probe, null, handler)
	catch(var/exception/null_delay_fault)
		reported++
		TEST_ASSERT(findtext(null_delay_fault.name, "delay must be a number"), "the report names the mistake: [null_delay_fault.name]")
	TEST_ASSERT_EQUAL(reported, 2, "a null delay reports a runtime")
	var/bad_with_id = 0
	var/bad_key_id = 0
	try
		bad_with_id = call(GLOBAL_PROC_REF(after))(probe, 1 SECONDS, handler, null, CLOCK_OWN, probe)
	catch(var/exception/with_fault)
		reported++
		TEST_ASSERT(findtext(with_fault.name, "with must be a list"), "the report names the mistake: [with_fault.name]")
	try
		bad_key_id = call(GLOBAL_PROC_REF(after))(probe, 1 SECONDS, handler, list(probe))
	catch(var/exception/key_fault)
		reported++
		TEST_ASSERT(findtext(key_fault.name, "key must be text"), "the report names the mistake: [key_fault.name]")
	TEST_ASSERT_EQUAL(reported, 4, "a bad with and a list in the key slot report a runtime")
	TEST_ASSERT(!bad_with_id && !bad_key_id, "neither schedules anything")

/// The declaration forms that would otherwise sit there and never run say so.
/datum/unit_test/dq_declare_dead_forms_are_loud

/datum/unit_test/dq_declare_dead_forms_are_loud/Run()
	var/list/old_capture = GLOB.declare_report_capture
	GLOB.declare_report_capture = list()
	var/not_a_notice = /datum/after_owner_probe
	var/bad_notice = on_notice(not_a_notice, then(TYPE_PROC_REF(/datum/after_owner_probe, fire)))
	var/empty_notice = on_notice(/datum/notice/ended)
	var/empty_change = on_change("fired", ANY)
	var/datum/after_owner_probe/held = allocate(/datum/after_owner_probe)
	release(held, "no such stat")
	var/read_unknown = stat_value(held, "no such stat either")
	var/bad_every = every(PROC_REF(fire_never), 1 SECONDS)
	var/empty_extend = extend("no parts here")
	var/no_edge = on_change("fired")
	observe(held, null, held)
	var/list/reports = GLOB.declare_report_capture
	GLOB.declare_report_capture = old_capture
	TEST_ASSERT(isnull(bad_notice) && isnull(empty_notice) && isnull(empty_change), "a dead form makes no entry")
	TEST_ASSERT(isnull(read_unknown) && isnull(bad_every) && isnull(empty_extend) && isnull(no_edge), "and neither do the others")
	TEST_ASSERT_EQUAL(length(reports), 9, "each dead form reports: [json_encode(reports)]")

/datum/unit_test/dq_declare_dead_forms_are_loud/proc/fire_never()
	return

/// A relation whose entry names no type still has a typed var, which DM does not check: rel_var_type_note() holds the writes.
/datum/unit_test/dq_rel_var_types_hold

/datum/unit_test/dq_rel_var_types_hold/Run()
	TEST_ASSERT(length(declared_rel_var_types()), "the generator lists the typed relation vars")
	var/list/seen = list()
	for(var/text in GLOB.rel_type_mismatches)
		// The one known case: a hose connector is a datum that poses as its reagents' my_atom on purpose (connector.dm, "atom reagent code piggyback").
		if(findtext(text, "/datum/reagents.my_atom is declared /atom, got a /datum/hose_connector"))
			continue
		seen += text
	TEST_ASSERT(!length(seen), "relation writes broke a var's declared type: [jointext(seen, "; ")]")

/// A hook is called through typesof(), so nothing names it: deleting one compiles, passes every other test, and quietly stops bans from loading.
/// These paths fail the compile if one goes. A new hook is added here.
/datum/unit_test/dq_startup_hooks_exist_and_run

/datum/unit_test/dq_startup_hooks_exist_and_run/Run()
	var/list/startup = list(
		/hook/startup/proc/loadBans,
		/hook/startup/proc/loadJobBans,
		/hook/startup/proc/resetInvestigate,
		/hook/startup/proc/setupTeleportLocs,
		/hook/startup/proc/setupGhostTeleportLocs,
		/hook/startup/proc/runechat_images,
		/hook/startup/proc/createDatacore,
		/hook/startup/proc/loadMode,
		/hook/startup/proc/updateHoliday,
		/hook/startup/proc/populate_gear_list,
		/hook/startup/proc/load_robot_custom_sprites,
		/hook/startup/proc/init_vore_datum_ref_lists,
		/hook/startup/proc/initialise_map_list,
	)
	for(var/hook in startup)
		TEST_ASSERT(hook in GLOB.hooks_called, "[hook] did not run at startup")
	for(var/hook in typesof(/hook/startup/proc))
		TEST_ASSERT((hook in startup) || !findtext("[hook]", "/proc/"), "[hook] is a startup hook this test does not name: add it")
	TEST_ASSERT(GLOB.data_core, "createDatacore made the data core")
	var/list/roundend = list(/hook/roundend/proc/stop_all_media, /hook/roundend/proc/metrics_round_end, /hook/roundend/proc/persist_locations)
	TEST_ASSERT_EQUAL(length(roundend), 3, "the round end hooks exist (the paths compile); they run only at round end")

/// Rust invokes these by name through call_id: a missing one panics the FFI call, and no DM source calls them.
/datum/unit_test/dq_native_callbacks_exist

/datum/unit_test/dq_native_callbacks_exist/Run()
	var/turf/T = test_floor()
	TEST_ASSERT(hascall(T, "consider_firelocks"), "the katmos firelock callback exists")
	TEST_ASSERT(hascall(T, "handle_decompression_floor_rip"), "the katmos floor rip callback exists")

/// Move wave A changed the compile order of nine client preference files. Their global initialisers read other globals, so an order that broke would leave these empty.
/datum/unit_test/dq_preference_globals_init_in_order

/datum/unit_test/dq_preference_globals_init_in_order/Run()
	TEST_ASSERT(length(GLOB.preference_entries), "the preference singletons exist")
	TEST_ASSERT(length(GLOB.preference_entries_by_key), "and by key")
	TEST_ASSERT(length(GLOB.pref_metadata_table), "the metadata table was built")
	for(var/datum/preference_editor/editor as anything in GLOB.preference_editors)
		for(var/key in editor.static_invalidator_keys)
			TEST_ASSERT(editor in GLOB.dq_editor_static_invalidators_by_key[key], "[editor.type] is indexed under [key]")
	TEST_ASSERT(GLOB.dq_species_preview_cache["__robot__"], "the species preview cache was warmed")
	for(var/species_name in GLOB.playable_species)
		var/datum/species/S = GLOB.all_species[species_name]
		if(S && species_name != SPECIES_CUSTOM)
			TEST_ASSERT(length(GLOB.dq_species_preview_cache), "species were available when the cache warmed")
			break

/// An unidentified hypospray starts with its hypo identification from its own block; an ordinary injector allocates none.
/datum/unit_test/dq_unidentified_hypo_has_identity

/datum/unit_test/dq_unidentified_hypo_has_identity/Run()
	var/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified/hidden = allocate(/obj/item/reagent_containers/hypospray/autoinjector/bonemed/unidentified)
	var/obj/item/reagent_containers/hypospray/autoinjector/bonemed/plain = allocate(/obj/item/reagent_containers/hypospray/autoinjector/bonemed)
	TEST_ASSERT(istype(hidden.identity, /datum/identification/hypo), "the unidentified one has its hypo identification, got [hidden.identity]")
	TEST_ASSERT_NULL(plain.identity, "the ordinary one has none")
