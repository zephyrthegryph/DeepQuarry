#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/unit_test/dq_pilotslug_helm_placement
	abstract_type = /datum/unit_test/dq_pilotslug_helm_placement

/// Disable eligible levels only while real construction runs. The production
/// rolls()/after_init() declarations remain active; each case then exercises
/// the real placement handler with its roll explicitly selected.
/datum/unit_test/dq_pilotslug_helm_placement/proc/make_slug(turf/start)
	RETURN_TYPE(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug)
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_var(using_map, nameof(using_map.player_levels), list())
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = allocate(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, start)
	set_var(P, nameof(P.takes_a_helm), TRUE)
	P.set_ghostjoin(FALSE)
	return P

/datum/unit_test/dq_pilotslug_helm_placement/valid/Run()
	var/turf/start = test_floor()
	var/turf/helm_turf = get_step(start, EAST)
	TEST_ASSERT(helm_turf && helm_turf != start, "The fixture has a distinct valid helm destination")
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = make_slug(start)
	var/obj/machinery/computer/ship/helm/fixture_helm = allocate(/obj/machinery/computer/ship/helm, helm_turf)
	TEST_ASSERT_EQUAL(get_turf(fixture_helm), helm_turf, "The real helm occupies the destination turf")
	set_var(using_map, nameof(using_map.player_levels), list(start.z))
	var/list/valid_turfs
	for(var/obj/machinery/computer/ship/helm/H in world)
		if(QDELETED(H))
			continue
		var/turf/T = get_turf(H)
		if(T && !QDELETED(T) && (T.z in using_map.player_levels))
			LAZYOR(valid_turfs, T)
	TEST_ASSERT(!(start in valid_turfs), "The original slug turf is not already a helm destination")
	TEST_ASSERT(helm_turf in valid_turfs, "The actual fixture helm is eligible")
	P.take_a_helm(null)
	TEST_ASSERT(get_turf(P) in valid_turfs, "The real handler places the selected slug at a live player-level helm")
	TEST_ASSERT(P.ghostjoin, "Successful helm placement enables ghost joining")

/datum/unit_test/dq_pilotslug_helm_placement/no_destination/Run()
	var/turf/start = test_floor()
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = make_slug(start)
	TEST_ASSERT(P.takes_a_helm, "The placement roll is selected, so this is not a default no-op")
	P.take_a_helm(null)
	TEST_ASSERT_EQUAL(P.loc, start, "No eligible helm preserves the original spawn location")
	TEST_ASSERT(!P.ghostjoin, "No destination does not enable ghost joining")

/datum/unit_test/dq_pilotslug_helm_placement/nullspace_helm/Run()
	var/turf/start = test_floor()
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = make_slug(start)
	var/obj/machinery/computer/ship/helm/invalid = allocate(/obj/machinery/computer/ship/helm, start)
	invalid.moveToNullspace()
	TEST_ASSERT(!get_turf(invalid), "The real nullspace helm has no valid destination turf")
	var/found = FALSE
	for(var/obj/machinery/computer/ship/helm/H in world)
		if(H == invalid)
			found = TRUE
			break
	TEST_ASSERT(found && !QDELETED(invalid), "The invalid helm remains a live candidate in the actual world search")
	set_var(using_map, nameof(using_map.player_levels), list(invalid.z))
	TEST_ASSERT(invalid.z in using_map.player_levels, "The old coordinate-only filter would admit this invalid helm")
	P.take_a_helm(null)
	TEST_ASSERT_EQUAL(P.loc, start, "A coordinate-matching helm without a turf preserves the spawn location")
	TEST_ASSERT(!P.ghostjoin, "An invalid helm does not enable ghost joining")
#endif
