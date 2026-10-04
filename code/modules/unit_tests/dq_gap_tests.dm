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
