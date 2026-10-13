// The map loader as a job() (code/modules/maps/map_load.dm): the chunked drive places and initializes exactly
// what the synchronous drive does, loads queue one at a time, and a failed load still reports.

/// type text -> count of every turf and atom on `z`.
/proc/dq_z_census(z)
	var/list/census = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		census["[T.type]"]++
		for(var/atom/A as anything in T)
			census["[A.type]"]++
	return census

/datum/unit_test/dq_map_load_job
	abstract_type = /datum/unit_test/dq_map_load_job
	/// Completions in the order they arrived: list(tag, result).
	var/list/completions = list()

/datum/unit_test/dq_map_load_job/proc/done(tag, result)
	completions += list(list(tag, result))

/// Runs the kernel until `count` completions arrived (or a generous number of passes went by).
/datum/unit_test/dq_map_load_job/proc/await_loads(count)
	for(var/pass in 1 to 4000)
		if(length(completions) >= count)
			return
		test_time(1)

/// A new-z load on the job path builds the same z as the sync one.
/datum/unit_test/dq_map_load_job/new_z_matches_sync/Run()
	test_driver_begin()
	var/datum/map_template/unit_tests/template = new
	var/sync_z = template.load_new_z()
	TEST_ASSERT(sync_z, "the sync load placed the template")
	var/list/expected = dq_z_census(sync_z)
	template.load_new_z_async(FALSE, PROC_REF(done), src, list("z"))
	TEST_ASSERT_EQUAL(length(completions), 0, "an async load does nothing before the kernel's pass")
	await_loads(1)
	TEST_ASSERT_EQUAL(length(completions), 1, "the job reported once")
	var/async_z = completions[1][2]
	TEST_ASSERT(async_z && async_z != sync_z, "the job loaded a z of its own")
	var/list/got = dq_z_census(async_z)
	TEST_ASSERT_EQUAL(length(got), length(expected), "the two z-levels hold the same kinds of things")
	for(var/kind in expected)
		TEST_ASSERT_EQUAL(got[kind], expected[kind], "[kind] count on the job-loaded z")
	test_driver_end()

/// A load at a turf on the job path builds what the sync load builds, and chunks over several steps.
/datum/unit_test/dq_map_load_job/at_matches_sync/Run()
	test_driver_begin()
	var/datum/map_template/unit_tests/template = new
	var/sync_z = world.increment_max_z()
	var/async_z = world.increment_max_z()
	TEST_ASSERT(template.load(locate(1, 1, sync_z)), "the sync load placed the template")
	var/list/expected = dq_z_census(sync_z)
	var/datum/map_load/M = template.load_async(locate(1, 1, async_z), FALSE, PROC_REF(done), src, list("at"))
	TEST_ASSERT_NOTNULL(M, "load_async() starts a load")
	await_loads(1)
	TEST_ASSERT_EQUAL(length(completions), 1, "the job reported once")
	TEST_ASSERT_EQUAL(completions[1][2], TRUE, "and reported success")
	TEST_ASSERT(M.steps > 3, "the load took several steps, not one")
	var/list/got = dq_z_census(async_z)
	for(var/kind in expected)
		TEST_ASSERT_EQUAL(got[kind], expected[kind], "[kind] count on the job-loaded z")
	TEST_ASSERT_EQUAL(length(got), length(expected), "the two z-levels hold the same kinds of things")
	TEST_ASSERT_NULL(GLOB.map_load_active, "a finished load is not the active one")
	test_driver_end()

/// Loads wait for one another: the second starts when the first has finished.
/datum/unit_test/dq_map_load_job/queues/Run()
	test_driver_begin()
	var/datum/map_template/unit_tests/template = new
	template.load_new_z_async(FALSE, PROC_REF(done), src, list("first"))
	template.load_new_z_async(FALSE, PROC_REF(done), src, list("second"))
	TEST_ASSERT_EQUAL(length(GLOB.map_load_queue), 1, "the second load waits behind the first")
	await_loads(2)
	TEST_ASSERT_EQUAL(length(completions), 2, "both loads reported")
	TEST_ASSERT_EQUAL(completions[1][1], "first", "in the order they were submitted")
	TEST_ASSERT_EQUAL(completions[2][1], "second", "and the second after the first")
	TEST_ASSERT(completions[1][2] && completions[2][2], "both loaded")
	TEST_ASSERT_EQUAL(length(GLOB.map_load_queue), 0, "the queue is empty again")
	test_driver_end()

/// A load that cannot start (off the edge of the world) reports failure instead of hanging.
/datum/unit_test/dq_map_load_job/reports_failure/Run()
	test_driver_begin()
	var/datum/map_template/unit_tests/template = new
	template.load_async(locate(world.maxx, world.maxy, 1), FALSE, PROC_REF(done), src, list("edge"))
	await_loads(1)
	TEST_ASSERT_EQUAL(length(completions), 1, "the job reported once")
	TEST_ASSERT_EQUAL(completions[1][2], FALSE, "and reported failure")
	TEST_ASSERT_NULL(GLOB.map_load_active, "without holding the loader")
	test_driver_end()
