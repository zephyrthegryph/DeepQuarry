// The pathfinder service's mutex and waiter count (code/_helpers/pathfinding/pathfinder.dm).
// A search that runtimes, and a request that times out waiting, must both leave the service as
// they found it: a held mutex or a leaked waiter count slows or blocks every later request.

/// A search that always runtimes.
/datum/pathfinding/dq_test_crash

/datum/pathfinding/dq_test_crash/search()
	CRASH("dq_pathfinder_tests: this search crashes on purpose")

/// A search that finds a (fake) path.
/datum/pathfinding/dq_test_found

/datum/pathfinding/dq_test_found/search()
	return list("found")

/datum/unit_test/dq_pathfinder_search_runtime_releases_mutex

/datum/unit_test/dq_pathfinder_search_runtime_releases_mutex/Run()
	var/datum/system/pathing/service = SSpathing
	var/datum/pathfinding/dq_test_crash/crasher = new(null, null, null, 1, 8)
	var/threw = FALSE
	try
		service.run_pathfinding(crasher)
	catch
		threw = TRUE
	TEST_ASSERT(threw, "a runtime in search() reaches the caller")
	TEST_ASSERT(!service.pathfinding_mutex, "the mutex is released after search() runtimed")
	TEST_ASSERT_EQUAL(service.pathfinding_blocked, 0, "no waiter is counted after a search that runtimed")
	// The next request must not wait on a mutex nobody holds.
	var/datum/pathfinding/dq_test_found/finder = new(null, null, null, 1, 8)
	var/list/path = service.run_pathfinding(finder)
	TEST_ASSERT(islist(path) && length(path) == 1, "a request after a runtime still runs its search")
	TEST_ASSERT(!service.pathfinding_mutex, "and releases the mutex too")

/datum/unit_test/dq_pathfinder_timeout_releases_waiter

/datum/unit_test/dq_pathfinder_timeout_releases_waiter/Run()
	var/datum/system/pathing/service = SSpathing
	// Someone else holds the mutex for longer than this waiter will wait.
	service.pathfinding_mutex = TRUE
	for(var/i in 1 to 12)
		TEST_ASSERT(!service.wait_for_mutex(world.time, 1), "wait [i] times out while the mutex stays held")
		TEST_ASSERT_EQUAL(service.pathfinding_blocked, 0, "wait [i] timed out and left the waiter count at zero")
	// More than the backoff threshold of timeouts: the leak used to make every later wait take the slow branch.
	service.pathfinding_mutex = FALSE
	TEST_ASSERT(service.wait_for_mutex(world.time, 1), "a free mutex is taken at once")
	TEST_ASSERT_EQUAL(service.pathfinding_blocked, 0, "and the waiter count is still zero")
