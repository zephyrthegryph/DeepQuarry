// Fixtures of the progress bar on an op's wait. Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_eg2_wait_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Two timed ops reached by key: one with the default progress bar, one silent.
/obj/eg2_waiter
	name = "eg2 waiter"
	var/done = 0

CAPABILITIES(/obj/eg2_waiter, \
	op("slow", menu(), wait(3 SECONDS), then(PROC_REF(finished))), \
	op("hush", menu(), wait(3 SECONDS), silent_wait(), then(PROC_REF(finished))), 	op("careful", menu(), wait(3 SECONDS), on_interrupt(PROC_REF(broken)), then(PROC_REF(finished))))

/// How often a broken wait called back, and why the last one broke.
/obj/eg2_waiter/var/broke = 0
/obj/eg2_waiter/var/broke_reason
/obj/eg2_waiter/var/broke_actor_name

/obj/eg2_waiter/proc/broken(datum/act/op/A)
	broke++
	broke_reason = A.reason
	broke_actor_name = "[A.actor]"

/obj/eg2_waiter/proc/finished(datum/act/op/A)
	done++
	return OP_OK

#endif
