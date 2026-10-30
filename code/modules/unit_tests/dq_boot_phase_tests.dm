/// The boot phase timers (code/engine/kernel/boot_phase.dm): a phase between BEGIN and END adds its elapsed time and one call, and does
/// nothing while the timers are off.
/datum/unit_test/dq_boot_phase_timers_accumulate

/datum/unit_test/dq_boot_phase_timers_accumulate/Run()
	var/was_on = GLOB.boot_phase_on
	var/list/saved_us = GLOB.boot_phase_us.Copy()
	var/list/saved_calls = GLOB.boot_phase_calls.Copy()
	GLOB.boot_phase_on = FALSE
	BOOT_PHASE_BEGIN(bp_off)
	BOOT_PHASE_END(bp_off, "dq_test: off")
	TEST_ASSERT(isnull(GLOB.boot_phase_calls["dq_test: off"]), "a phase recorded while the timers were off")
	GLOB.boot_phase_on = TRUE
	for(var/i in 1 to 3)
		BOOT_PHASE_BEGIN(bp_on)
		BOOT_PHASE_END(bp_on, "dq_test: on")
	TEST_ASSERT_EQUAL(GLOB.boot_phase_calls["dq_test: on"], 3, "three timed phases count three calls")
	TEST_ASSERT(GLOB.boot_phase_us["dq_test: on"] >= 0, "a phase's time is never negative")
	GLOB.boot_phase_on = was_on
	GLOB.boot_phase_us = saved_us
	GLOB.boot_phase_calls = saved_calls
