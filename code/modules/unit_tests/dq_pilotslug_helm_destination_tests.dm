#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/unit_test/dq_pilotslug_helm_destination
	var/valid_helm = TRUE

/datum/unit_test/dq_pilotslug_helm_destination/no_valid_destination
	valid_helm = FALSE

/datum/unit_test/dq_pilotslug_helm_destination/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	set_var(using_map, nameof(using_map.player_levels), list())
	var/obj/machinery/computer/ship/helm/locationless = allocate(/obj/machinery/computer/ship/helm, null)
	TEST_ASSERT_NULL(get_turf(locationless), "Live locationless candidate has no move destination")
	var/turf/helm_turf = get_step(T, EAST)
	TEST_ASSERT(istype(helm_turf, /turf/simulated/floor) && helm_turf != T, "Actual separate floor turf is available for the admitted helm")
	if(valid_helm)
		allocate(/obj/machinery/computer/ship/helm, helm_turf)
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/pilot = allocate(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, T)
	pilot.takes_a_helm = TRUE
	set_var(using_map, nameof(using_map.player_levels), valid_helm ? list(T.z) : list(0))
	// Drive the normal effect through a real timer; do not invoke early after_init.
	after(pilot, 1 SECOND, TYPE_PROC_REF(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, take_a_helm))
	test_time(1 SECOND)
	if(!valid_helm)
		TEST_ASSERT_EQUAL(get_turf(pilot), T, "No valid candidate preserves the pilot's actual location without a runtime")
	else
		var/turf/destination = get_turf(pilot)
		TEST_ASSERT(destination != T, "The real timer moves the pilot away from its original floor")
		TEST_ASSERT(destination && (destination.z in using_map.player_levels), "Actual deferred move ends on an admitted live turf")
		var/helm_at_destination = FALSE
		for(var/obj/machinery/computer/ship/helm/H in destination)
			helm_at_destination = TRUE
		TEST_ASSERT(helm_at_destination, "Actual destination contains a real helm")
#endif


