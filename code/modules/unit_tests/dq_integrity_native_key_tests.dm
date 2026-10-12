#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
// Include inside the unit-test manifest guard. No constructor or base vars change.
/obj/dq_integrity_key_probe
	abstract_type = /obj/dq_integrity_key_probe
	uses_integrity = TRUE
	max_integrity = 100
	integrity_failure = 0
	var/integrity_notifications = 0
CAPABILITIES(/obj/dq_integrity_key_probe)
	on_change(PROC_REF(integrity_value), ANY, then(PROC_REF(integrity_changed)))
/obj/dq_integrity_key_probe/proc/integrity_value()
	return get_integrity()
/obj/dq_integrity_key_probe/proc/integrity_changed(datum/act/A)
	integrity_notifications++
/obj/dq_integrity_key_probe/draw(datum/look/look)
	..()
	look.state(get_integrity() >= 50 ? "intact" : "damaged")

/datum/unit_test/dq_integrity_native_key/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/dq_integrity_key_probe/P = allocate(/obj/dq_integrity_key_probe, test_floor())
	test_drain()
	TEST_ASSERT_EQUAL(P.get_integrity(), 100, "The real integrity initializer must establish the maximum")
	TEST_ASSERT_EQUAL(P.icon_state, "intact", "The real draw must be warm before mutation")
	var/list/reads = change_read_keys(P, TYPE_PROC_REF(/obj/dq_integrity_key_probe, integrity_value))
	TEST_ASSERT(ATOM_INTEGRITY_KEY in reads, "The accessor must subscribe to its existing native producer key")
	var/initial_notifications = P.integrity_notifications
	P.update_integrity(40)
	test_drain()
	TEST_ASSERT_EQUAL(P.get_integrity(), 40, "The real setter must update integrity")
	TEST_ASSERT_EQUAL(P.icon_state, "damaged", "The existing key publication must invalidate the warm draw without a blanket channel")
	TEST_ASSERT_EQUAL(P.integrity_notifications, initial_notifications + 1, "One actual mutation must deliver one native notification")
	P.update_integrity(40)
	test_drain()
	TEST_ASSERT_EQUAL(P.integrity_notifications, initial_notifications + 1, "An unchanged value must publish nothing")
	P.repair_damage(40)
	test_drain()
	TEST_ASSERT_EQUAL(P.get_integrity(), 80, "Real repair must still pass through the existing setter")
	TEST_ASSERT_EQUAL(P.icon_state, "intact", "Repair must redraw the previous damage state")
	TEST_ASSERT_EQUAL(P.integrity_notifications, initial_notifications + 2, "Repair contributes exactly one more native delivery")

#endif

