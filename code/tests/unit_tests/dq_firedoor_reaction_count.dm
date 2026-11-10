// A firedoor reacts to the area's power only when its own has_power flips: an unchanged channel write, an unchanged APC re-apply and a flip of a channel
// it does not draw on queue no reaction for it, and a real flip of its channel is one has_power evaluation and one reaction per door.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The reactions the firedoors under test have heard (power lost plus restored), by door.
/datum/unit_test/dq_firedoor_reaction_count
	var/heard = 0

/datum/unit_test/dq_firedoor_reaction_count/proc/on_power_heard(datum/act/notice/A)
	heard++

/datum/unit_test/dq_firedoor_reaction_count/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	test_driver_begin()
	var/turf/T = get_turf(apc)
	var/area/A = apc.area
	var/list/doors = list()
	var/list/spots = list()
	for(var/turf/simulated/floor/F in A)
		if(!F.density && !(locate(/obj/machinery) in F) && length(spots) < 6)
			spots += F
	TEST_ASSERT(length(spots) >= 6, "the APC's area has fewer than six free floor tiles")
	var/n = 0
	for(var/turf/spot as anything in spots)
		var/obj/machinery/door/firedoor/D = allocate(++n % 2 ? /obj/machinery/door/firedoor/border_only : /obj/machinery/door/firedoor/glass, spot)
		doors += D
		observe(D, /datum/notice/machinery_power_lost, src, then(PROC_REF(on_power_heard)))
		observe(D, /datum/notice/machinery_power_restored, src, then(PROC_REF(on_power_heard)))
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	heard = 0
	var/evals = GLOB.stat_evals
	var/gated = GLOB.stat_hops_gated

	// Unchanged writes: nothing is marked, evaluated or heard.
	A.set_channels(TRUE, TRUE, TRUE)
	apc.apply_area_power()
	test_drain()
	TEST_ASSERT_EQUAL(GLOB.stat_evals - evals, 0, "an unchanged channel write evaluated [GLOB.stat_evals - evals] stat(s)")
	TEST_ASSERT_EQUAL(heard, 0, "an unchanged channel write queued [heard] firedoor reaction(s)")

	// A channel the doors do not draw on: still nothing for them.
	A.set_channels(FALSE, TRUE, TRUE)
	test_drain()
	TEST_ASSERT_EQUAL(heard, 0, "an equipment flip queued [heard] firedoor reaction(s)")
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	heard = 0
	evals = GLOB.stat_evals
	gated = GLOB.stat_hops_gated

	// Their own channel: one reaction per door, and a bounded number of evaluations.
	A.set_channels(TRUE, TRUE, FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(heard, length(doors), "the environment cut reached [heard] reaction(s) for [length(doors)] firedoor(s)")
	// Only the machines that draw on the environment channel are evaluated (has_power, and the operable it feeds): the lamps, canisters and the rest of
	// the area, whose has_power reads another channel, are not reached by this flip.
	var/spent = GLOB.stat_evals - evals
	var/drawing = 0
	for(var/obj/machinery/M as anything in A.power_machines)
		if(M.draws_environ())
			drawing++
	TEST_ASSERT(spent <= 2 * drawing, "the environment cut evaluated [spent] stat(s) for [drawing] machine(s) drawing on it")
	TEST_ASSERT(GLOB.stat_hops_gated > gated, "the machines not drawing on the environment channel were reached by its flip")
	A.set_channels(TRUE, TRUE, TRUE)
	test_drain()
	test_driver_end()

#endif
