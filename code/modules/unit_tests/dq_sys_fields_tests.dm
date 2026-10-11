// Core state as declared fields (doc/rewrite/systems.md §2, machinery_fields.dm): the stat
// bitfield raises the channel of each bit that changed, once per change; operable() follows it;
// the core fields and hand-written setters are registered with their family channels.

/// Counts raises of `mask` on `E` recorded since `sched.test_raises` was armed, and disarms it.
/datum/unit_test/proc/dq_sys_fields_count_raises(datum/time_scheduler/sched, datum/E, mask)
	. = 0
	for(var/list/raise as anything in sched.test_raises)
		if(raise[1] == E && (raise[2] & mask))
			.++

/// Machines publish actual tracked/state keys; their obsolete scheduler field-channel rows are gone.
/datum/unit_test/dq_sys_fields_registered

/datum/unit_test/dq_sys_fields_registered/Run()
	var/list/F = definition_registry().fields_of(/obj/machinery/recharger)
	for(var/name in list("on", "locked", "stat", "operable", "use_power"))
		TEST_ASSERT(!F[name], "Machine [name] no longer maps to a legacy channel")
	TEST_ASSERT_EQUAL(F["anchored"], 0, "Inherited anchor row has no scheduler-channel mask")
	TEST_ASSERT_EQUAL(F["density"], 0, "Inherited density row has no scheduler-channel mask")
	var/obj/machinery/recharger/M = allocate(/obj/machinery/recharger)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	TEST_ASSERT(M.operable(), "Actual conditions permit the real recharger")
	M.set_broken_condition(TRUE)
	TEST_ASSERT(!M.operable(), "The composed condition observes actual damage")

/// The hand-written setters publish genuine var keys, once per change.
/datum/unit_test/dq_sys_fields_custom_setters_raise

/datum/unit_test/dq_sys_fields_custom_setters_raise/Run()
	var/obj/machinery/M = allocate(/obj/machinery)
	M.set_anchored(FALSE)
	M.set_density(FALSE)
	M.set_use_power(USE_POWER_IDLE)
	var/datum/dq_b4_key_probe/anchor = dq_b4_probe(M, nameof(M.anchored))
	var/datum/dq_b4_key_probe/dense = dq_b4_probe(M, nameof(M.density))
	var/datum/dq_b4_key_probe/power = dq_b4_probe(M, nameof(M.use_power))
	M.set_anchored(TRUE)
	M.set_anchored(TRUE)
	M.set_density(TRUE)
	M.set_density(TRUE)
	TEST_ASSERT(M.set_use_power(USE_POWER_ACTIVE), "Changing mode reports a real change")
	M.set_use_power(USE_POWER_ACTIVE)
	rx_drain()
	TEST_ASSERT(M.anchored && M.density, "Actual anchor/density state changed")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_ACTIVE, "The actual power mode changed")
	TEST_ASSERT_EQUAL(anchor.hits, 1, "Anchor key publishes once")
	TEST_ASSERT_EQUAL(dense.hits, 1, "Density key publishes once")
	TEST_ASSERT_EQUAL(power.hits, 1, "Power-mode key publishes once")
