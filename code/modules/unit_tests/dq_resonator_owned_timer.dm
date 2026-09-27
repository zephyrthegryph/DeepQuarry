/datum/unit_test/dq_resonator_owned_burst_timer
	needs_test_block = FALSE

/datum/unit_test/dq_resonator_owned_burst_timer/Run()
	var/turf/test_turf = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/obj/effect/resonance/field = new(test_turf, null, 5 SECONDS)
	var/datum/object_model/schedule_entry/timer = field.burst_timer
	TEST_ASSERT(timer && om_owner(timer) == field, "resonance burst is scheduled under field ownership")
	qdel(field)
	TEST_ASSERT(QDELETED(timer), "field deletion canceled its pending burst")
