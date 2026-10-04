// Framework gap closures (doc/rewrite/codemod_rules.md): OP_DECLINE. Fixtures: code/tests/engine/gap_fixtures.dm.

/datum/unit_test/dq_gap
	abstract_type = /datum/unit_test/dq_gap

/datum/unit_test/dq_gap/Run()
	test_driver_begin()
	run_gap()
	test_driver_end()

/datum/unit_test/dq_gap/proc/run_gap()
	return

/// A handler that answers OP_DECLINE leaves the click to the next candidate; one that does not decline is the only one that runs.
/datum/unit_test/dq_gap/op_decline_falls_through
/datum/unit_test/dq_gap/op_decline_falls_through/run_gap()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/gap_decline/target = allocate(/obj/gap_decline, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	var/datum/op_result/R = test_click(H, target, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(target.second, 1, "the declined click went to the next candidate")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "which committed")
	target.declines = FALSE
	test_click(H, target, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(target.first, 1, "not declining, the first op took the click")
	TEST_ASSERT_EQUAL(target.second, 1, "and the second did not run")

/// Every candidate declining leaves the driver the declined result and tells nobody.
/datum/unit_test/dq_gap/op_decline_alone_is_not_handled
/datum/unit_test/dq_gap/op_decline_alone_is_not_handled/run_gap()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/gap_decline_alone/target = allocate(/obj/gap_decline_alone, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	var/datum/op_result/R = test_click(H, target, thing)
	TEST_ASSERT_EQUAL(target.first, 1, "the handler ran once")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_DECLINED, "the result says declined, not refused or committed")

/// A type-level every() with when = a tracked var: parked while false (no timer), runs on its interval while true, parks again when it clears.
/datum/unit_test/dq_gap/every_parks_and_wakes
/datum/unit_test/dq_gap/every_parks_and_wakes/run_gap()
	var/obj/gap_every/E = allocate(/obj/gap_every, run_loc_floor_bottom_left)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(E.ticks, 0, "false: it never ran")
	TEST_ASSERT(length(E.rx?.every_parked), "and it is parked, holding no timer")
	E.set_active(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(E.ticks >= 4 && E.ticks <= 5, "true: it ran on its interval (ran [E.ticks])")
	TEST_ASSERT(!length(E.rx?.every_parked), "no longer parked")
	E.set_active(FALSE)
	var/seen = E.ticks
	test_time(5 SECONDS)
	TEST_ASSERT(E.ticks <= seen + 1, "false again: it stopped (ran [E.ticks - seen] more)")
	TEST_ASSERT(length(E.rx?.every_parked), "and parked")
	E.set_active(TRUE)
	seen = E.ticks
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks > seen, "woken again")

/// An instance that starts true arms at once.
/datum/unit_test/dq_gap/every_starts_when_true
/datum/unit_test/dq_gap/every_starts_when_true/run_gap()
	var/obj/gap_every/running/E = allocate(/obj/gap_every/running, run_loc_floor_bottom_left)
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks >= 2, "running from creation (ran [E.ticks])")
	TEST_ASSERT(!length(E.rx?.every_parked), "never parked")

/// A proc gate cannot be trusted to announce every change, so the every() polls (never parks) and still follows the condition.
/datum/unit_test/dq_gap/every_with_a_proc_gate_polls
/datum/unit_test/dq_gap/every_with_a_proc_gate_polls/run_gap()
	var/obj/gap_every_proc/E = allocate(/obj/gap_every_proc, run_loc_floor_bottom_left)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(E.ticks, 0, "false: it did not run")
	TEST_ASSERT(!length(E.rx?.every_parked), "and it is polling, not parked")
	E.set_on(TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks >= 2, "true: it runs (ran [E.ticks])")

/// Converted periodic (a tracked var plus every()): a pinpointer steps (and shows what it found) only while active.
/datum/unit_test/dq_gap/periodic_pinpointer_steps_while_active
/datum/unit_test/dq_gap/periodic_pinpointer_steps_while_active/run_gap()
	var/obj/item/pinpointer/P = allocate(/obj/item/pinpointer, run_loc_floor_bottom_left)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(P.icon_state, "pinoff", "off: it never stepped")
	P.set_active(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(P.icon_state != "pinoff", "active: its step ran and set what it points at ([P.icon_state])")
	P.set_active(FALSE)
	P.icon_state = "pinoff"
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(P.icon_state, "pinoff", "off again: it stopped stepping")

/// Converted periodic: a radio jammer drains its cell on its 2 s step only while switched on.
/datum/unit_test/dq_gap/periodic_jammer_drains_while_on
/datum/unit_test/dq_gap/periodic_jammer_drains_while_on/run_gap()
	var/obj/item/radio_jammer/J = allocate(/obj/item/radio_jammer, run_loc_floor_bottom_left)
	var/start = J.power_source.charge
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(J.power_source.charge, start, "off: nothing drained")
	J.set_on(TRUE)
	test_time(6 SECONDS)
	TEST_ASSERT(J.power_source.charge < start, "on: the step drained the cell ([start] to [J.power_source.charge])")
	J.set_on(FALSE)
	var/seen = J.power_source.charge
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(J.power_source.charge, seen, "off again: it stopped")
