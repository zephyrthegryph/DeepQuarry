/obj/item/organ/dq_test_decay_clock
	decays = FALSE

/// Detached organs use one decay-clock deadline and pause without lost work.
/datum/unit_test/dq_organ_detached_decay_clock

/datum/unit_test/dq_organ_detached_decay_clock/Run()
	var/obj/item/organ/dq_test_decay_clock/O = allocate(/obj/item/organ/dq_test_decay_clock)
	O.start_detached_decay()
	var/datum/object_model/behaviour_runtime/R = O.om_state?.behaviour_runtime
	var/path = /datum/object_model/behaviour/organ_detached_decay
	TEST_ASSERT_NOTNULL(R, "detached organ needs a behaviour runtime")
	TEST_ASSERT(R.active[path], "detached decay behaviour activates")
	TEST_ASSERT(!(O in SSobj.processing), "detached organ does not also poll in SSobj")
	R.run_ready()
	TEST_ASSERT_EQUAL(O.germ_level, 0, "activation waits one period before decay")
	TEST_ASSERT_NOTNULL(R.run_clock_due?[path], "detached organ has a local decay deadline")
	var/datum/object_model/clock_state/C = om_clock_for(O, /datum/object_model/clock_domain/decay)
	C.last_world -= LIFE_NOMINAL_SECONDS SECONDS
	R.wake(path)
	R.run_ready()
	TEST_ASSERT_EQUAL(O.germ_level, 1, "one local period runs detached organ process")
	O.set_preserved(TRUE)
	TEST_ASSERT(!R.active[path], "preservation deactivates detached decay")
	TEST_ASSERT_NULL(R.run_clock_due?[path], "preservation removes its local deadline")
	O.set_preserved(FALSE)
	TEST_ASSERT(R.active[path], "release reactivates detached decay")
	R.run_ready()
	var/datum/source = new
	TEST_ASSERT(om_clock_set(O, /datum/object_model/clock_domain/decay, source, 1, 1), "decay clock can be paused by a source")
	TEST_ASSERT_EQUAL(C.rate, 0, "source pauses detached decay")
	TEST_ASSERT_NULL(R.run_due?[path], "paused decay has no world deadline")
	qdel(source)
	TEST_ASSERT_EQUAL(C.rate, 1, "deleting the source resumes decay")
	TEST_ASSERT_NOTNULL(R.run_due?[path], "resumed decay re-arms its deadline")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	O.owner = H
	om_behaviour_refresh(O)
	TEST_ASSERT(!R.active[path], "reattachment deactivates detached decay")
