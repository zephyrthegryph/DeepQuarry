// Fixes from the second engine review: a runtime in game code must never leave an engine latch set or a bookkeeping list half-built.

// ---------------------------------------------------------------- rx_drain: the latch is released when a crossing handler runtimes

/// `level` is watched by an on_cross handler that runtimes; `calm` by an ordinary on_change handler.
/datum/rx_fx_cross_throw
	var/level = 0
	var/calm = 0
	var/calm_runs = 0

/datum/rx_fx_cross_throw/reactions()
	. = ..()
	. += on_cross(nameof(level), list(10, 20), PROC_REF(on_level))
	. += on_change(list(nameof(calm)), PROC_REF(on_calm))

/datum/rx_fx_cross_throw/proc/on_level(band, previous)
	CRASH("rx_fx_cross_throw: expected runtime in an on_cross handler")

/datum/rx_fx_cross_throw/proc/on_calm(list/keys)
	calm_runs++

/datum/unit_test/dq_review2_rx_drain_survives_a_throwing_crossing/Run()
	var/datum/rx_fx_cross_throw/F = allocate(/datum/rx_fx_cross_throw)
	F.set_level(5)
	rx_drain()
	F.set_level(15) // a non-urgent crossing: queued for the drain
	var/list/saved_capture = GLOB.dq_caught_capture
	GLOB.dq_caught_capture = list()
	rx_drain()
	GLOB.dq_caught_capture = saved_capture
	TEST_ASSERT(!GLOB.rx_draining, "the drain latch was released after a handler runtimed")
	F.set_calm(1)
	rx_drain()
	TEST_ASSERT_EQUAL(F.calm_runs, 1, "a later change is still delivered")
