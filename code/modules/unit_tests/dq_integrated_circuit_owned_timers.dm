/obj/item/integrated_circuit/time/ticker/dq_timer_test
	var/pulses = 0

/obj/item/integrated_circuit/time/ticker/dq_timer_test/check_power()
	return TRUE

/obj/item/integrated_circuit/time/ticker/dq_timer_test/activate_pin(pin_number)
	pulses++

/datum/unit_test/dq_integrated_circuit_owned_timers
	needs_test_block = FALSE

/datum/unit_test/dq_integrated_circuit_owned_timers/Run()
	var/turf/test_turf = locate(1, 1, 1)
	var/obj/item/integrated_circuit/time/delay/D = new(test_turf)
	D.delay = 5 SECONDS
	D.do_work()
	var/list/delay_entries = om_children(D, "om:schedule")
	TEST_ASSERT_EQUAL(length(delay_entries), 1, "delay circuit scheduled one owned pulse")
	var/datum/object_model/schedule_entry/pulse = delay_entries[1]
	TEST_ASSERT_EQUAL(om_owner(pulse), D, "delayed pulse belongs to the circuit")
	qdel(D)
	TEST_ASSERT(QDELETED(pulse), "deleting the delay circuit cancels its pulse")

	var/obj/item/integrated_circuit/time/ticker/dq_timer_test/T = new(test_turf)
	T.delay = 5 SECONDS
	var/datum/integrated_io/enable_pin = T.inputs[1]
	enable_pin.write_data_to_pin(TRUE)
	var/datum/object_model/schedule_entry/first = T.tick_timer
	TEST_ASSERT(first && om_owner(first) == T, "ticker schedules one owned tick")
	enable_pin.write_data_to_pin(FALSE)
	TEST_ASSERT(QDELETED(first) && !T.tick_timer, "disabling the ticker cancels its pending tick")
	enable_pin.write_data_to_pin(TRUE)
	var/datum/object_model/schedule_entry/second = T.tick_timer
	TEST_ASSERT(second && second != first && length(om_children(T, "om:schedule")) == 1, "restarting the ticker schedules exactly one tick")
	qdel(T)
	TEST_ASSERT(QDELETED(second), "deleting the ticker cancels its pending tick")

/// Logical attachment follows either endpoint without moving the physical item.
/datum/unit_test/dq_integrated_grenade_attachment_lifecycle
	needs_test_block = FALSE

/datum/unit_test/dq_integrated_grenade_attachment_lifecycle/Run()
	var/turf/test_turf = locate(1, 1, 1)
	var/obj/item/integrated_circuit/manipulation/grenade/primer = new(test_turf)
	var/obj/item/grenade/explosive/first = new(primer)
	TEST_ASSERT(primer.attach_grenade(first), "the primer should attach the first grenade")
	TEST_ASSERT_EQUAL(primer.attached_grenade, first, "the attachment mirror should point at the grenade")
	TEST_ASSERT_EQUAL(primer.size, initial(primer.size) + first.w_class, "the attached grenade should increase primer size")
	qdel(first)
	TEST_ASSERT_NULL(primer.attached_grenade, "destroying the grenade should clear the mirror")
	TEST_ASSERT_EQUAL(primer.size, initial(primer.size), "destroying the grenade should restore primer size")
	TEST_ASSERT_EQUAL(primer.desc, initial(primer.desc), "destroying the grenade should restore primer description")
	var/obj/item/grenade/explosive/second = new(primer)
	TEST_ASSERT(primer.attach_grenade(second), "the primer should attach a replacement grenade")
	TEST_ASSERT(primer.detach_grenade(), "the primer should explicitly detach the grenade")
	TEST_ASSERT_EQUAL(second.loc, primer, "detaching the logical link should leave physical containment alone")
	TEST_ASSERT_NULL(primer.attached_grenade, "explicit detachment should clear the mirror")
	TEST_ASSERT(primer.attach_grenade(second), "the primer should reattach the contained grenade")
	qdel(primer)
	TEST_ASSERT_EQUAL(second.loc, test_turf, "destroying the primer should drop its inactive grenade")
	TEST_ASSERT_NULL(om_first_linked_to(second, /datum/object_model/relation/integrated_grenade_attachment), "destroying the primer should remove the attachment edge")
	qdel(second)
