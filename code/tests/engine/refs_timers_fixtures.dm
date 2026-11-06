// Fixtures of the timer and borrow tests of the refs lane (code/tests/unit_tests/dq_refs_timers_tests.dm). Compiled under UNIT_TESTS only.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Counts the timers that reached it. A timer's argument, so the tests can tell a fire from a drop.
/datum/refs_timer_probe
	var/fired = 0
	var/last_arg

/// A global-proc timer handler: the probe it was handed counts the fire.
/proc/refs_timer_probe_fire(datum/refs_timer_probe/probe, tag)
	if(probe)
		probe.fired++
		probe.last_arg = tag

/// A tool whose op waits on a target other than itself and wants to hear when the wait is broken (K8): the target is deleted mid-wait.
/obj/item/refs_k8_tool
	name = "k8 tool"
	var/broke = 0
	var/done = 0
	var/broke_target_was_null = FALSE
	var/broke_reason

CAPABILITIES(/obj/item/refs_k8_tool)
	op("k8_probe", ai(), reach(REACH_ANY), wait(5 SECONDS), on_interrupt(PROC_REF(probe_broken)), then(PROC_REF(probe_done)))

/obj/item/refs_k8_tool/proc/probe_broken(datum/act/op/A)
	broke++
	broke_target_was_null = isnull(A.target)
	broke_reason = A.reason

/obj/item/refs_k8_tool/proc/probe_done(datum/act/op/A)
	done++
	return OP_OK

#endif
