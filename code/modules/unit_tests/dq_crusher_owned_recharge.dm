/datum/unit_test/dq_crusher_owned_recharge
	needs_test_block = FALSE

/datum/unit_test/dq_crusher_owned_recharge/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/item/kinetic_crusher/crusher = new(test_turf)
	crusher.charged = FALSE
	crusher.schedule_recharge()
	var/datum/object_model/schedule_entry/first = crusher.recharge_timer
	TEST_ASSERT(first && om_owner(first) == crusher, "crusher recharge belongs to the item")
	crusher.Recharge()
	TEST_ASSERT(crusher.charged && QDELETED(first) && !crusher.recharge_timer, "early recharge canceled the timer")
	crusher.charged = FALSE
	crusher.schedule_recharge()
	var/datum/object_model/schedule_entry/second = crusher.recharge_timer
	TEST_ASSERT(second && !QDELETED(second), "crusher scheduled another recharge")
	qdel(crusher)
	TEST_ASSERT(QDELETED(second), "crusher deletion canceled its recharge")
