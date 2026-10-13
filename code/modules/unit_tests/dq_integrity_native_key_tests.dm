#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
// Include inside the unit-test manifest guard. No constructor or base vars change.
/obj/dq_integrity_key_probe
	abstract_type = /obj/dq_integrity_key_probe
	uses_integrity = TRUE
	max_integrity = 100
	integrity_failure = 0
	var/integrity_notifications = 0
	var/mid_batch_icon
	var/mid_batch_notifications
	var/mid_batch_integrity
CAPABILITIES(/obj/dq_integrity_key_probe)
	on_change(PROC_REF(integrity_value), ANY, then(PROC_REF(integrity_changed)))
/obj/dq_integrity_key_probe/proc/integrity_value(datum/act/eval/A)
	return get_integrity()
/obj/dq_integrity_key_probe/proc/integrity_changed(datum/act/A)
	integrity_notifications++
/obj/dq_integrity_key_probe/draw(datum/look/look)
	..()
	look.state(get_integrity() >= 50 ? "intact" : "damaged")

/obj/dq_integrity_key_probe/proc/write_atomic_sample()
	update_integrity(40)
	// Force the delivery boundary without allowing a partial publication.
	test_drain()
	mid_batch_icon = icon_state
	mid_batch_notifications = integrity_notifications
	mid_batch_integrity = get_integrity()
	update_integrity(80)

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

/datum/unit_test/dq_integrity_native_key/atomic_publication/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/dq_integrity_key_probe/P = allocate(/obj/dq_integrity_key_probe, test_floor())
	test_drain()
	var/before = P.integrity_notifications
	state_batch(P, TYPE_PROC_REF(/obj/dq_integrity_key_probe, write_atomic_sample))
	TEST_ASSERT_EQUAL(P.mid_batch_integrity, 40, "The real writer applies its value before publication")
	TEST_ASSERT_EQUAL(P.mid_batch_icon, "intact", "A forced drain cannot expose an intermediate damaged presentation")
	TEST_ASSERT_EQUAL(P.mid_batch_notifications, before, "A forced drain cannot deliver an incomplete native-key cohort")
	test_drain()
	TEST_ASSERT_EQUAL(P.get_integrity(), 80, "The complete native snapshot must retain the final value")
	TEST_ASSERT_EQUAL(P.icon_state, "intact", "Presentation must use the completed snapshot")
	TEST_ASSERT_EQUAL(P.integrity_notifications, before + 1, "Two native publications in one batch must deliver once")

// suspended is a real inherited virtual stat: there is deliberately no D.vars slot.
/obj/dq_virtual_stat_draw_probe
	abstract_type = /obj/dq_virtual_stat_draw_probe
/obj/dq_virtual_stat_draw_probe/draw(datum/look/look)
	..()
	look.state(stat_value(src, STAT_SUSPENDED) ? "suspended" : "active")

/datum/unit_test/dq_integrity_native_key/virtual_stat_draw/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/dq_virtual_stat_draw_probe/P = allocate(/obj/dq_virtual_stat_draw_probe, test_floor())
	var/obj/source = allocate(/obj, test_floor())
	test_drain()
	TEST_ASSERT(!("suspended" in P.vars), "This fixture must exercise the virtual-stat publication branch")
	TEST_ASSERT_EQUAL(P.icon_state, "active", "The virtual stat draw must be warm before the hold")
	hold(P, STAT_SUSPENDED, TRUE, source)
	test_drain()
	TEST_ASSERT_EQUAL(stat_value(P, STAT_SUSPENDED), TRUE, "The real source hold must compose the virtual stat")
	TEST_ASSERT_EQUAL(P.icon_state, "suspended", "A virtual stat publication must invalidate the warm draw")
	release(P, STAT_SUSPENDED, source)
	test_drain()
	TEST_ASSERT_EQUAL(P.icon_state, "active", "Releasing the actual source must restore the draw")

/obj/dq_capability_key_draw_probe
	abstract_type = /obj/dq_capability_key_draw_probe
	var/mid_batch_icon
/obj/dq_capability_key_draw_probe/draw(datum/look/look)
	..()
	look.state(cap_has(src, CAP_LOCKED) ? "locked" : "unlocked")
/obj/dq_capability_key_draw_probe/proc/write_atomic_sample()
	cap_set(src, CAP_LOCKED, TRUE)
	test_drain()
	mid_batch_icon = icon_state
	cap_set(src, CAP_LOCKED, FALSE)

/datum/unit_test/dq_integrity_native_key/capability_draw/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/dq_capability_key_draw_probe/P = allocate(/obj/dq_capability_key_draw_probe, test_floor())
	test_drain()
	TEST_ASSERT_EQUAL(P.icon_state, "unlocked", "The capability-state draw must start warm")
	state_batch(P, TYPE_PROC_REF(/obj/dq_capability_key_draw_probe, write_atomic_sample))
	TEST_ASSERT_EQUAL(P.mid_batch_icon, "unlocked", "An intermediate capability publication must remain inside the atomic boundary")
	test_drain()
	TEST_ASSERT_EQUAL(P.icon_state, "unlocked", "The complete capability snapshot must remain unlocked")
	TEST_ASSERT(cap_set(P, CAP_LOCKED, TRUE), "The real capability setter must change its bit")
	test_drain()
	TEST_ASSERT_EQUAL(P.icon_state, "locked", "The actual engine key must invalidate the warmed draw")
	TEST_ASSERT(cap_set(P, CAP_LOCKED, FALSE), "The actual capability bit must clear")
	test_drain()
	TEST_ASSERT_EQUAL(P.icon_state, "unlocked", "Clearing the actual capability bit must restore the draw")
#endif

