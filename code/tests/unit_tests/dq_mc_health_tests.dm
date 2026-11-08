// The MC Health panel's data (code/content/client/mc_health.dm): every section the panel draws is there, the subsystems' usage is a share of
// the tick and not the old hard-coded 0, the churn read leaves the churn source's window alone, and the build is cheap.

/datum/unit_test/dq_mc_health_data
/datum/unit_test/dq_mc_health_data/Run()
	var/started = TICK_USAGE_REAL
	var/list/data = mc_health_data()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	for(var/key in list("window_5s", "window_30s", "window_5m", "ticks", "outliers", "subsystems", "kernel", "gc", "entities", "churn", "runtime"))
		TEST_ASSERT(!isnull(data[key]), "the panel data has [key]")
	TEST_ASSERT(length(data["ticks"]) <= 120, "at most 120 recent ticks")
	var/list/census = data["entities"]["census"]
	TEST_ASSERT(census["turfs"] == world.maxx * world.maxy * world.maxz, "the census counts every turf")
	TEST_ASSERT(census["areas"] > 0, "and the areas")
	var/fired = FALSE
	for(var/list/S as anything in data["subsystems"])
		if(S["cost"] > 0)
			fired = TRUE
			TEST_ASSERT(S["usage"] > 0, "[S["name"]] costs [S["cost"]] ms a fire, so its usage is not 0")
	TEST_ASSERT(fired, "some system has a measured cost")
	TEST_NOTICE(src, "MC Health data: built in [round(ms, 0.01)] ms, [length(json_encode(data))] bytes, census [census["ms"]] ms")

/datum/unit_test/dq_mc_health_churn_peek_keeps_window
/datum/unit_test/dq_mc_health_churn_peek_keeps_window/Run()
	var/datum/churn_census/census = GLOB.churn_census
	census.draws["dq_peek_test"] = (census.draws["dq_peek_test"] || 0) + 3
	var/list/top = mc_health_churn()["draw"]
	var/found = FALSE
	for(var/list/row as anything in top)
		if(row[1] == "dq_peek_test")
			found = TRUE
	TEST_ASSERT(found || length(top) == 5, "the peek lists the busiest draw keys")
	TEST_ASSERT_EQUAL(census.draws["dq_peek_test"], 3, "reading the churn for the panel leaves the window's counts in place")
	census.draws -= "dq_peek_test"
