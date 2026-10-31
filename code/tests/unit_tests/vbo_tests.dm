/// Tests that all mobs with assigned bellies use valid datums
/datum/unit_test/vbo_has_state

/datum/unit_test/vbo_has_state/Run()
	for(var/datum/belly_overlays/test_path as anything in subtypesof(/datum/belly_overlays))
		// belly_icon is now a string path, not an icon ref; wrap with file().
		var/icon_name = icon_states_fast(file(initial(test_path.belly_icon)))[1]
		if(!(icon_exists('icons/mob/vore_fullscreens/ui_lists/screen_full_vore_list_base.dmi', icon_name)))
			TEST_FAIL("[test_path] is missing inside the screen_full_vore_list_base list dmi file.")

/// Tests that all mobs with assigned bellies use valid datums
/datum/unit_test/mobs_use_valid_belly_overlays
	/// Set TRUE to trace every lifecycle phase of each mob's deletion (slow: ~1 s per mob).
	var/trace_lifecycle = FALSE

/datum/unit_test/mobs_use_valid_belly_overlays/Run()
	for(var/mob/living/simple_mob/test_path as anything in typesof(/mob/living/simple_mob))
		if(!initial(test_path.vore_active))
			continue
		var/started = REALTIMEOFDAY
		log_test("vbo: spawning [test_path]")
		var/mob/living/simple_mob/test_mob = new test_path()
		log_test("vbo: [test_path] made in [(REALTIMEOFDAY - started) / 10]s")
		test_mob.init_vore(TRUE)
		log_test("vbo: [test_path] init_vore done at [(REALTIMEOFDAY - started) / 10]s")
		for(var/obj/belly/mob_belly in test_mob.vore_organs)
			var/test_fullscreen = mob_belly.belly_fullscreen
			if(!length(test_fullscreen))
				continue
			var/datum/belly_overlays/test_overlay = text2path("/datum/belly_overlays/[lowertext(test_fullscreen)]")
			if(test_overlay)
				continue
			TEST_FAIL("[test_mob] uses a non existing belly_fullscreen [test_fullscreen].")
		log_test("vbo: [test_path] bellies checked, deleting")
		// Per-phase lifecycle tracing (GLOB.dq_lifecycle_trace_depth) wrote
		// ~250 log lines per mob and was ~1 s of each mob's 1.3 s cost; it is
		// opt-in via trace_lifecycle. The per-mob log_test lines still localise
		// a hang to one type.
		if(trace_lifecycle)
			GLOB.dq_lifecycle_trace_depth++
		qdel(test_mob)
		if(trace_lifecycle)
			GLOB.dq_lifecycle_trace_depth--
		log_test("vbo: [test_path] deleted at [(REALTIMEOFDAY - started) / 10]s")
