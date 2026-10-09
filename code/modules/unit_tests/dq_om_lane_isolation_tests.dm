// OM scheduler error isolation, one test per lane (LANE_URGENT .. LANE_WORLD,
// code/__defines/om.dm). In the lane under test a failing behaviour runtimes in its
// tick AND in its wake gate (wake_if); a healthy behaviour shares the lane and a
// witness ticks in every other lane. Then the whole lane loop is made to runtime
// (sched.harness_lane_fault). Neither may stall the scheduler: the healthy behaviour
// and the other lanes keep running, and the faulted lane resumes once it's fixed.

/// wake_if that runtimes: the gate is behaviour code run inside the lane's wake drain.
/datum/om/check/test_lane_crash

/datum/om/check/test_lane_crash/why_not(datum/actor, datum/target)
	CRASH("deliberate wake gate runtime")

/datum/om/behaviour/test/lane_iso
	abstract_type = /datum/om/behaviour/test/lane_iso
	every = 1 SECONDS
	wake_on = CHANGE_DATUM_A

/datum/om/behaviour/test/lane_iso/bad
	abstract_type = /datum/om/behaviour/test/lane_iso/bad
	wake_if = /datum/om/check/test_lane_crash

/datum/om/behaviour/test/lane_iso/good_urgent
	lane = LANE_URGENT
/datum/om/behaviour/test/lane_iso/good_simulation
	lane = LANE_SIMULATION
/datum/om/behaviour/test/lane_iso/good_derived
	lane = LANE_DERIVED
/datum/om/behaviour/test/lane_iso/good_presentation
	lane = LANE_PRESENTATION
/datum/om/behaviour/test/lane_iso/good_background
	lane = LANE_BACKGROUND
/datum/om/behaviour/test/lane_iso/good_world
	lane = LANE_WORLD

/datum/om/behaviour/test/lane_iso/bad/urgent
	lane = LANE_URGENT
/datum/om/behaviour/test/lane_iso/bad/simulation
	lane = LANE_SIMULATION
/datum/om/behaviour/test/lane_iso/bad/derived
	lane = LANE_DERIVED
/datum/om/behaviour/test/lane_iso/bad/presentation
	lane = LANE_PRESENTATION
/datum/om/behaviour/test/lane_iso/bad/background
	lane = LANE_BACKGROUND
/datum/om/behaviour/test/lane_iso/bad/world
	lane = LANE_WORLD

/proc/om_lane_iso_good(lane)
	var/static/list/paths = list(
		/datum/om/behaviour/test/lane_iso/good_urgent,
		/datum/om/behaviour/test/lane_iso/good_simulation,
		/datum/om/behaviour/test/lane_iso/good_derived,
		/datum/om/behaviour/test/lane_iso/good_presentation,
		/datum/om/behaviour/test/lane_iso/good_background,
		/datum/om/behaviour/test/lane_iso/good_world,
	)
	return paths[lane]

/proc/om_lane_iso_bad(lane)
	var/static/list/paths = list(
		/datum/om/behaviour/test/lane_iso/bad/urgent,
		/datum/om/behaviour/test/lane_iso/bad/simulation,
		/datum/om/behaviour/test/lane_iso/bad/derived,
		/datum/om/behaviour/test/lane_iso/bad/presentation,
		/datum/om/behaviour/test/lane_iso/bad/background,
		/datum/om/behaviour/test/lane_iso/bad/world,
	)
	return paths[lane]

/datum/unit_test/om/lane_isolation
	abstract_type = /datum/unit_test/om/lane_isolation
	/// The LANE_* under test.
	var/lane = 0

/datum/unit_test/om/lane_isolation/run_om(list/made)
	TEST_ASSERT(lane >= 1 && lane <= OM_LANE_COUNT, "lane isolation test has no lane")
	sched.expect_errors = TRUE
	var/errors_before = length(sched.errors)

	// The lane under test: one failing entity queued before one healthy entity.
	var/datum/om_test_entity/bad = entity(made)
	bad.crash_on_tick = TRUE
	om_attach(bad, om_lane_iso_bad(lane))
	var/datum/om_test_entity/good = entity(made)
	om_attach(good, om_lane_iso_good(lane))
	// Witnesses in every other lane.
	var/list/witnesses = list()
	for(var/other in 1 to OM_LANE_COUNT)
		if(other == lane)
			continue
		var/datum/om_test_entity/W = entity(made)
		om_attach(W, om_lane_iso_good(other))
		witnesses["[other]"] = W

	// Wakes: the failing gate is drained first, the healthy wake after it.
	changed(bad, CHANGE_DATUM_A)
	changed(good, CHANGE_DATUM_A)
	scheduler_advance(3)

	TEST_ASSERT(bad.ticks >= 2, "lane [lane]: a runtiming tick removed its entity from the ring ([bad.ticks] ticks)")
	TEST_ASSERT_EQUAL(bad.wakes, 0, "lane [lane]: a runtiming wake gate still ran on_wake")
	TEST_ASSERT(good.ticks >= 2, "lane [lane]: a failing behaviour stalled a healthy one in the same lane ([good.ticks] ticks)")
	TEST_ASSERT_EQUAL(good.wakes, 1, "lane [lane]: a failing wake gate stalled the lane's wake drain")
	for(var/other in witnesses)
		var/datum/om_test_entity/W = witnesses[other]
		TEST_ASSERT(W.ticks >= 2, "lane [lane]: a failing behaviour stalled lane [other] ([W.ticks] ticks)")
	TEST_ASSERT(length(sched.errors) > errors_before, "lane [lane]: behaviour runtimes are recorded")
	var/list/S = sched.stat_for(definition_registry().behaviour(om_lane_iso_bad(lane)).id)
	TEST_ASSERT(S[OM_STAT_ERRORS] >= 3, "lane [lane]: tick and gate runtimes are counted per behaviour ([S[OM_STAT_ERRORS]])")

	// The whole lane loop runtimes: other lanes still run in the same pass.
	var/list/before = list()
	for(var/other in witnesses)
		var/datum/om_test_entity/W = witnesses[other]
		before[other] = W.ticks
	var/faults_before = sched.lane_faults
	sched.harness_lane_fault = new /list(OM_LANE_COUNT)
	sched.harness_lane_fault[lane] = TRUE
	scheduler_advance(2)
	TEST_ASSERT(sched.lane_faults > faults_before, "lane [lane]: a lane-level runtime was not caught and counted")
	for(var/other in witnesses)
		var/datum/om_test_entity/W = witnesses[other]
		TEST_ASSERT(W.ticks > before[other], "lane [lane]: a faulted lane stalled lane [other]")

	// Fixed: the faulted lane resumes, wakes included.
	sched.harness_lane_fault = null
	var/good_ticks = good.ticks
	changed(good, CHANGE_DATUM_A)
	scheduler_advance(2)
	TEST_ASSERT(good.ticks > good_ticks, "lane [lane]: the lane did not resume after its fault")
	TEST_ASSERT_EQUAL(good.wakes, 2, "lane [lane]: wakes queued during or after the fault were lost")

/datum/unit_test/om/lane_isolation/urgent
	lane = LANE_URGENT

/datum/unit_test/om/lane_isolation/simulation
	lane = LANE_SIMULATION

/datum/unit_test/om/lane_isolation/derived
	lane = LANE_DERIVED

/datum/unit_test/om/lane_isolation/presentation
	lane = LANE_PRESENTATION

/datum/unit_test/om/lane_isolation/background
	lane = LANE_BACKGROUND

/datum/unit_test/om/lane_isolation/world
	lane = LANE_WORLD
