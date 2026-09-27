/datum/unit_test/dq_disposal_owned_power_retry
	needs_test_block = FALSE

/datum/unit_test/dq_disposal_owned_power_retry/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/machinery/disposal/bin = new(test_turf)
	bin.mode = 0 // The disposal mode constants are local to disposal_machines.dm.
	var/callback = TYPE_PROC_REF(/obj/machinery/disposal, retry_charge_after_power_restore)
	var/datum/object_model/schedule_entry/first = bin.EnsureAfter(5 SECONDS, callback)
	TEST_ASSERT(first && om_owner(first) == bin, "power retry belongs to the disposal bin")
	TEST_ASSERT(bin.EnsureAfter(1 SECOND, callback) == first, "repeated power restore preserves first retry")
	bin.retry_charge_after_power_restore()
	TEST_ASSERT(QDELETED(first) && !bin.PendingAfter(callback), "early retry canceled the pending timer")
	var/datum/object_model/schedule_entry/second = bin.EnsureAfter(5 SECONDS, callback)
	TEST_ASSERT(second && !QDELETED(second), "power retry can be scheduled again")
	qdel(bin)
	TEST_ASSERT(QDELETED(second), "bin deletion canceled its owned power retry")
