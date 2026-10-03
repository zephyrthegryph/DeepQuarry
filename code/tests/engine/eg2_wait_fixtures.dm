// Fixtures of the progress bar on an op's wait. Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_eg2_wait_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Two timed ops reached by key: one with the default progress bar, one silent.
/obj/eg2_waiter
	name = "eg2 waiter"
	var/done = 0

CAPABILITIES(/obj/eg2_waiter, \
	op("slow", menu(), wait(3 SECONDS), then(PROC_REF(finished))), \
	op("hush", menu(), wait(3 SECONDS), silent_wait(), then(PROC_REF(finished))))

/obj/eg2_waiter/proc/finished(datum/act/op/A)
	done++
	return OP_OK

#endif
