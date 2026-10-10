// Core state as declared fields (doc/rewrite/systems.md §2, machinery_fields.dm): the stat
// bitfield raises the channel of each bit that changed, once per change; operable() follows it;
// the core fields and hand-written setters are registered with their family channels.

/// Counts raises of `mask` on `E` recorded since `sched.test_raises` was armed, and disarms it.
/datum/unit_test/proc/dq_sys_fields_count_raises(datum/time_scheduler/sched, datum/E, mask)
	. = 0
	for(var/list/raise as anything in sched.test_raises)
		if(raise[1] == E && (raise[2] & mask))
			.++

/// The registry knows the core fields with their family channels, the operability stat reader and
/// the registered hand-written setters (anchored, density, use_power).
/datum/unit_test/dq_sys_fields_registered

/datum/unit_test/dq_sys_fields_registered/Run()
	var/datum/definition_registry/reg = definition_registry()
	var/list/F = reg.fields_of(/obj/machinery/recharger)
	TEST_ASSERT_EQUAL(F["on"], CHANGE_MACHINE_SETTINGS, "on channel")
	TEST_ASSERT_EQUAL(F["locked"], CHANGE_MACHINE_MODE, "locked channel")
	TEST_ASSERT_EQUAL(F["stat"], CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_POWER, "stat channel")
	TEST_ASSERT_NULL(F["operable"], "operable is a stat reader, not a legacy scheduler field")
	var/obj/machinery/recharger/M = allocate(/obj/machinery/recharger)
	M.set_grid_power(TRUE)
	M.set_broken_condition(FALSE)
	TEST_ASSERT(M.operable(), "the stat reader observes powered, intact machinery")
	M.set_broken_condition(TRUE)
	TEST_ASSERT(!M.operable(), "the stat reader follows the actual broken condition")
	TEST_ASSERT(F["anchored"] & CHANGE_MACHINE_ANCHORED, "anchored does not raise CHANGE_MACHINE_ANCHORED on a machine")
	TEST_ASSERT(F["density"] & CHANGE_MACHINE_SETTINGS, "density does not raise CHANGE_MACHINE_SETTINGS on a machine")
	TEST_ASSERT(F["use_power"] & CHANGE_MACHINE_SETTINGS, "use_power does not raise CHANGE_MACHINE_SETTINGS")
	var/list/mob_fields = reg.fields_of(/mob/living)
	TEST_ASSERT_EQUAL(mob_fields["anchored"], 0, "anchored raises no channel on a mob")

/// The hand-written setters registered as fields raise their family channel on a change only.
/datum/unit_test/dq_sys_fields_custom_setters_raise

/datum/unit_test/dq_sys_fields_custom_setters_raise/Run()
	var/obj/machinery/M = allocate(/obj/machinery)
	var/datum/scheduler_record/rec = scheduler_record_of(M)
	var/datum/time_scheduler/sched = rec.sched
	M.om_listen |= CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_SETTINGS
	M.set_anchored(FALSE)
	M.set_density(FALSE)
	M.set_use_power(USE_POWER_IDLE)
	sched.test_raises = list()
	M.set_anchored(TRUE)
	M.set_anchored(TRUE)
	TEST_ASSERT_EQUAL(dq_sys_fields_count_raises(sched, M, CHANGE_MACHINE_ANCHORED), 1, "set_anchored raises once per change")
	sched.test_raises = list()
	M.set_density(TRUE)
	M.set_density(TRUE)
	TEST_ASSERT(M.set_use_power(USE_POWER_ACTIVE), "set_use_power() of a change returned FALSE")
	TEST_ASSERT_EQUAL(M.use_power, USE_POWER_ACTIVE, "set_use_power() did not write")
	TEST_ASSERT_EQUAL(dq_sys_fields_count_raises(sched, M, CHANGE_MACHINE_SETTINGS), 2, "set_density + set_use_power raise once each")
	sched.test_raises = null
