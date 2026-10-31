/datum/unit_test/interim_flight_assignment_deletion
	var/arrived = FALSE

/datum/unit_test/interim_flight_assignment_deletion/Run()
	var/datum/flight_vessel/vessel = allocate(/datum/flight_vessel)
	var/datum/expedition_site/site = allocate(/datum/expedition_site, 0, EXP_DIFF_LOW)
	var/datum/flight_destination/destination = allocate(/datum/flight_destination)
	rel_set(destination, nameof(destination.expedition), site)
	// The assignment relations installed by the expedition controller.
	rel_set(site, nameof(site.assigned_flight_vessel), vessel)
	rel_set(vessel, nameof(vessel.active_expedition), site)
	var/datum/flight_plan/plan = allocate(/datum/flight_plan, vessel, null, destination)
	TEST_ASSERT(plan in destination.active_plans, "The plan constructor must establish a real destination lease")
	TEST_ASSERT(site.has_active_assignment(), "The fixture must start with a real vessel assignment")
	if(arrived)
		plan.state = FLIGHT_PLAN_ARRIVED
	qdel(plan)
	TEST_ASSERT(!QDELETED(vessel) && !QDELETED(site), "Plan deletion must preserve the independent vessel and site")
	TEST_ASSERT(!LAZYLEN(destination.active_plans), "Plan deletion must release the destination lease")
	if(arrived)
		TEST_ASSERT_EQUAL(site.assigned_flight_vessel(), vessel, "An arrived plan must retain the site's vessel assignment")
		TEST_ASSERT_EQUAL(vessel.active_expedition(), site, "An arrived plan must retain the vessel's expedition assignment")
	else
		TEST_ASSERT_NULL(site.assigned_flight_vessel(), "Non-arrived plan deletion must release the surviving site's assignment")
		TEST_ASSERT_NULL(vessel.active_expedition(), "Non-arrived plan deletion must release the surviving vessel's assignment")

/datum/unit_test/interim_flight_assignment_deletion/arrived
	arrived = TRUE
