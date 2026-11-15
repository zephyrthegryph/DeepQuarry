// The spawn point audit: every /datum/spawnpoint either lands a body somewhere livable on this map or is excluded from every list for saying so,
// and the setup list, the saved choice and the join share one check. Run on the full map too (dq_focused_test.sh --full-map).
// SPAWN_AUDIT lines in the test log are the per-map answer.

/// Every spawn point lands a live body on a floor with air, or is honestly not on this map.
/datum/unit_test/dq_spawnpoint_every_point_lands

/datum/unit_test/dq_spawnpoint_every_point_lands/Run()
	for(var/name in using_map.allowed_spawns)
		TEST_ASSERT(GLOB.spawntypes[name], "the map allows [name], which no spawn point is called")
	for(var/name in GLOB.spawntypes)
		var/datum/spawnpoint/P = GLOB.spawntypes[name]
		var/listed = (name in using_map.allowed_spawns)
		var/list/usable = P.usable_turfs()
		log_test("SPAWN_AUDIT: [name]: listed=[listed] candidates=[length(P.candidates())] usable=[length(usable)] on_map=[!!P.is_on_map()]")
		if(!P.is_on_map())
			TEST_ASSERT(!listed, "[using_map.type] allows [name] but it has nowhere safe to stand")
			continue
		for(var/turf/T as anything in usable)
			var/datum/gas_mixture/air = T.return_air()
			TEST_ASSERT(air && air.return_pressure() > 50 && air.return_temperature() > 250 && air.return_temperature() < 330, "[name] at [T.x],[T.y],[T.z] ([T.type]) has no breathable air")
		var/turf/landing = P.get_spawn_position()
		log_test("SPAWN_AUDIT: [name] lands at [landing.x],[landing.y],[landing.z] ([get_area(landing)])")
		TEST_ASSERT(isturf(landing), "[name] gives a real turf")
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, landing)
		TEST_ASSERT(H.loc == landing && H.stat != DEAD, "a body stands alive at [name]")

/// A preferences datum for a character of this species and play mode.
/proc/dq_spawn_audit_prefs(species, play_mode = "human")
	var/datum/preferences/dq_test_stub/prefs = new
	prefs.set_value_cache_at(/datum/preference/choiced/species, species)
	prefs.set_value_cache_at(/datum/preference/text/human/play_mode, play_mode)
	prefs.set_value_cache_at(/datum/preference/organ_data, list())
	return prefs

/// Gives a map without the Dark a stand-in for this test; TRUE if it did.
/proc/dq_spawn_audit_dark_begin(turf/floor)
	if("The Dark" in using_map.allowed_spawns)
		return FALSE
	using_map.allowed_spawns += "The Dark"
	GLOB.latejoin_thedark += floor
	return TRUE

/proc/dq_spawn_audit_dark_end(turf/floor)
	using_map.allowed_spawns -= "The Dark"
	GLOB.latejoin_thedark -= floor

/// Only a Shadekin is offered the Dark; a Shadekin is offered no crew spawn; a robot gets cyborg storage and no cryo.
/datum/unit_test/dq_spawnpoint_choices_follow_character

/datum/unit_test/dq_spawnpoint_choices_follow_character/Run()
	var/turf/floor = run_loc_floor_bottom_left
	if(dq_spawn_audit_dark_begin(floor))
		defer_cleanup(null, GLOBAL_PROC_REF(dq_spawn_audit_dark_end), floor)

	var/list/human = spawnpoint_choices_for(dq_spawn_audit_prefs(SPECIES_HUMAN))
	TEST_ASSERT(!("The Dark" in human), "a human is offered the Dark: [english_list(human)]")
	TEST_ASSERT("Arrivals Shuttle" in human, "a human is offered arrivals: [english_list(human)]")
	TEST_ASSERT("Cryogenic Storage" in human, "a human is offered cryo: [english_list(human)]")
	TEST_ASSERT(!("Cyborg Storage" in human), "a human is offered cyborg storage: [english_list(human)]")

	var/list/kin = spawnpoint_choices_for(dq_spawn_audit_prefs(SPECIES_SHADEKIN))
	TEST_ASSERT("The Dark" in kin, "a Shadekin is offered the Dark: [english_list(kin)]")
	TEST_ASSERT(!("Arrivals Shuttle" in kin), "a Shadekin (no crew job) is offered arrivals: [english_list(kin)]")
	TEST_ASSERT(!("Cryogenic Storage" in kin), "a Shadekin (no crew job) is offered cryo: [english_list(kin)]")

	var/list/robot = spawnpoint_choices_for(dq_spawn_audit_prefs(SPECIES_HUMAN, "robot"))
	TEST_ASSERT("Cyborg Storage" in robot, "a robot is offered cyborg storage: [english_list(robot)]")
	TEST_ASSERT(!("Cryogenic Storage" in robot), "a robot is offered cryo: [english_list(robot)]")

	for(var/list/offered as anything in list(human, kin, robot))
		for(var/name in offered)
			var/datum/spawnpoint/P = GLOB.spawntypes[name]
			TEST_ASSERT(P.is_on_map(), "[name] is offered though it is not on this map")

/// A saved choice that stops holding falls back with no error, the species change rebuilds the setup list, and the join holds the same line.
/datum/unit_test/dq_spawnpoint_invalid_choice_falls_back

/datum/unit_test/dq_spawnpoint_invalid_choice_falls_back/Run()
	var/turf/floor = run_loc_floor_bottom_left
	if(dq_spawn_audit_dark_begin(floor))
		defer_cleanup(null, GLOBAL_PROC_REF(dq_spawn_audit_dark_end), floor)

	var/datum/preference/spawnpoint = GLOB.preference_entries[/datum/preference/choiced/living/spawnpoint]
	var/datum/preferences/prefs = dq_spawn_audit_prefs(SPECIES_HUMAN)
	prefs.begin_update_batch() // the stub has no savefile: this batch never flushes
	TEST_ASSERT_EQUAL(spawnpoint.sanitize("The Dark", prefs), "Arrivals Shuttle", "a human's saved Dark loads as arrivals")
	TEST_ASSERT(!spawnpoint.validate(prefs, "The Dark"), "a forged write of the Dark is refused for a human")

	// The human turns Shadekin in setup: the constraint moves the choice and drops the cached list the window was sent.
	prefs.set_value_cache_at(/datum/preference/choiced/living/spawnpoint, "Arrivals Shuttle")
	prefs.set_value_cache_at(/datum/preference/choiced/species, SPECIES_SHADEKIN)
	var/version = prefs.dq_category_structure_version
	var/datum/preference_constraint/species_refits_spawnpoint/fit = new
	fit.apply(prefs, "species", SPECIES_HUMAN, SPECIES_SHADEKIN)
	TEST_ASSERT_EQUAL(prefs.read_preference(/datum/preference/choiced/living/spawnpoint), "The Dark", "a Shadekin's saved arrivals moves to the Dark")
	TEST_ASSERT(prefs.dq_category_structure_version > version, "the setup list is rebuilt for the new species")
	var/list/category_choices = spawnpoint.get_pref_choices(prefs)
	TEST_ASSERT("The Dark" in category_choices, "the rebuilt list carries the Dark")

	// ...and back.
	prefs.set_value_cache_at(/datum/preference/choiced/species, SPECIES_HUMAN)
	fit.apply(prefs, "species", SPECIES_SHADEKIN, SPECIES_HUMAN)
	TEST_ASSERT_EQUAL(prefs.read_preference(/datum/preference/choiced/living/spawnpoint), "Arrivals Shuttle", "back to human, the Dark moves to arrivals")

	// The join: a human who still holds the Dark lands at arrivals; a Shadekin Anomaly who holds arrivals lands in the Dark.
	var/datum/spawnpoint/where = spawnpoint_for_join(prefs, JOB_INTERN, "The Dark")
	TEST_ASSERT_EQUAL(where?.display_name, "Arrivals Shuttle", "the join moves a human off the Dark")
	var/datum/preferences/kin = dq_spawn_audit_prefs(SPECIES_SHADEKIN)
	where = spawnpoint_for_join(kin, JOB_ANOMALY, "Arrivals Shuttle")
	TEST_ASSERT_EQUAL(where?.display_name, "The Dark", "the join moves a Shadekin Anomaly to the Dark")
	TEST_ASSERT(isnull(spawnpoint_for_join(prefs, JOB_ANOMALY, "The Dark")), "no spawn point takes a human as Anomaly")

/// An Outsider spawns at whichever spawn point the player chose, like a normal job.
/datum/unit_test/dq_spawnpoint_outsider_takes_chosen

/datum/unit_test/dq_spawnpoint_outsider_takes_chosen/Run()
	var/datum/preferences/prefs = dq_spawn_audit_prefs(SPECIES_HUMAN)
	for(var/name in using_map.allowed_spawns)
		var/datum/spawnpoint/P = GLOB.spawntypes[name]
		if(!P.check_job_spawning(JOB_OUTSIDER))
			TEST_ASSERT(P.allowed_mob_types == JOB_SILICON || length(P.restrict_job), "[name] refuses an Outsider")
			continue
		var/datum/spawnpoint/where = spawnpoint_for_join(prefs, JOB_OUTSIDER, name)
		TEST_ASSERT_EQUAL(where?.display_name, name, "an Outsider who chose [name] goes there")
		var/turf/landing = where.get_spawn_position()
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, landing)
		TEST_ASSERT(H.loc == landing && H.stat != DEAD, "an Outsider stands alive at [name]")
		log_test("SPAWN_AUDIT: Outsider at [name] lands at [landing.x],[landing.y],[landing.z]")
