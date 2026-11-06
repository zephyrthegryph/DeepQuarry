// A caught fault is reported without throwing (the report_in_catch lint): under an outer try, which every kernel phase has, a stack_trace() in a catch left the
// catch at once and skipped everything after it.

/datum/rx_fx/faulting

/datum/rx_fx/faulting/on_watched(list/keys)
	throw EXCEPTION("expected on_change handler fault")

/// A throwing on_change handler does not cost the other holders in the batch, and rx_draining is not left set (which would stop every later drain in the world).
/datum/unit_test/dq_report_in_catch_rx_drain/Run()
	var/datum/rx_fx/faulting/bad = allocate(/datum/rx_fx/faulting)
	var/datum/rx_fx/good = allocate(/datum/rx_fx)
	bad.set_watched(1)
	good.set_watched(1)
	GLOB.dq_caught_capture = list()
	var/escaped = null
	try
		rx_drain()
	catch(var/exception/e)
		escaped = e.name
	var/list/reported = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = null
	var/stuck = GLOB.rx_draining
	GLOB.rx_draining = FALSE
	TEST_ASSERT_NULL(escaped, "the fault stays inside the drain")
	TEST_ASSERT(!stuck, "the drain finished")
	TEST_ASSERT_EQUAL(length(good.heard), 1, "the holder after the fault was still delivered to")
	TEST_ASSERT_EQUAL(length(reported), 1, "the fault was reported once")
	good.set_watched(2)
	rx_drain()
	TEST_ASSERT_EQUAL(length(good.heard), 2, "the next drain still runs")
