// Core state as tracked vars (machinery_fields.dm): operable() follows the conditions held on a machine;
// the hand-written setters of the core vars publish their key once per change.

/// A machine's operability stat reader follows the conditions held on it.
/datum/unit_test/dq_sys_fields_registered

/datum/unit_test/dq_sys_fields_registered/Run()
	var/list/F = definition_registry().fields_of(/obj/machinery/recharger)
	TEST_ASSERT_NULL(F["operable"], "operable is a stat reader, not a legacy scheduler field")
	var/obj/machinery/recharger/M = allocate(/obj/machinery/recharger)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	TEST_ASSERT(M.operable(), "the stat reader observes powered, intact machinery")
	M.set_broken_condition(TRUE)
	TEST_ASSERT(!M.operable(), "the stat reader follows the actual broken condition")

/// The hand-written setters of the core machine vars publish their key on a change only, once per change.
/datum/unit_test/dq_sys_fields_custom_setters_publish

/datum/unit_test/dq_sys_fields_custom_setters_publish/Run()
	var/obj/machinery/M = allocate(/obj/machinery)
	M.set_anchored(FALSE)
	M.set_density(FALSE)
	M.set_use_power(USE_POWER_IDLE)
	var/datum/dq_b4_key_probe/anchored = dq_b4_probe(M, "anchored")
	var/datum/dq_b4_key_probe/density = dq_b4_probe(M, "density")
	var/datum/dq_b4_key_probe/draw = dq_b4_probe(M, "use_power")
	M.set_anchored(TRUE)
	M.set_anchored(TRUE)
	M.set_density(TRUE)
	M.set_density(TRUE)
	TEST_ASSERT(M.set_use_power(USE_POWER_ACTIVE), "set_use_power() of a change returned FALSE")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_ACTIVE, "set_use_power() did not write")
	rx_drain()
	TEST_ASSERT_EQUAL(anchored.hits, 1, "set_anchored publishes once per change")
	TEST_ASSERT_EQUAL(density.hits, 1, "set_density publishes once per change")
	TEST_ASSERT_EQUAL(draw.hits, 1, "set_use_power publishes once per change")
