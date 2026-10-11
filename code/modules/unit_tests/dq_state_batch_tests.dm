#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/dq_state_batch_fixture
	var/left = 0
	var/right = 0

TRACKED(/datum/dq_state_batch_fixture, left)
TRACKED(/datum/dq_state_batch_fixture, right)
STAT(/datum/dq_state_batch_fixture, state_batch_sum, SUM)

CAPABILITIES(/datum/dq_state_batch_fixture)
	contributes(STAT_STATE_BATCH_SUM, PROC_REF(sum_value))

/datum/dq_state_batch_fixture/proc/sum_value(datum/act/A)
	return left + right

/datum/dq_state_batch_fixture/proc/outer_write()
	set_left(1)
	state_batch(src, PROC_REF(inner_write))
	set_left(3)

/datum/dq_state_batch_fixture/proc/inner_write()
	set_right(2)
	set_left(2)

/datum/dq_state_batch_fixture/proc/throwing_write()
	set_left(4)
	throw EXCEPTION("Expected state batch writer failure")

/datum/dq_state_batch_fixture/proc/deleted_write()
	set_left(1)
	END_SCOPE(src)

/datum/dq_state_batch_fixture/proc/pure_write()
	set_left(5)

/datum/unit_test/dq_state_publication_batch_nested/Run()
	var/datum/dq_state_batch_fixture/F = allocate(/datum/dq_state_batch_fixture)
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 0, "the actual derived stat is not initialized to its real inputs")
	var/before = GLOB.stat_evals
	state_batch(F, TYPE_PROC_REF(/datum/dq_state_batch_fixture, outer_write))
	TEST_ASSERT_EQUAL(F.left, 3, "outer writer did not retain its last actual setter value")
	TEST_ASSERT_EQUAL(F.right, 2, "nested writer's actual setter value was lost")
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 5, "the real dependent stat did not settle from the completed cohort")
	TEST_ASSERT_EQUAL(GLOB.stat_evals - before, 2, "the repeated nested left writes published more than one actual input key")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "nested completion left the publication batch open")
	TEST_ASSERT(!GLOB.state_batch_flushing && !length(GLOB.state_batch_pending), "nested completion left a delivery or pending queue behind")

/datum/unit_test/dq_state_publication_batch_exception/Run()
	var/datum/dq_state_batch_fixture/F = allocate(/datum/dq_state_batch_fixture)
	stat_value(F, STAT_STATE_BATCH_SUM)
	var/caught = FALSE
	try
		state_batch(F, TYPE_PROC_REF(/datum/dq_state_batch_fixture, throwing_write))
	catch(var/exception/fault)
		caught = findtext(fault.name, "Expected state batch writer failure") > 0
	TEST_ASSERT(caught, "the writer's real exception did not propagate")
	TEST_ASSERT_EQUAL(F.left, 4, "a completed setter was silently rolled back on writer failure")
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 4, "exception cleanup dropped the completed setter's publication")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "writer failure left the batch depth raised")
	TEST_ASSERT(!GLOB.state_batch_flushing && !length(GLOB.state_batch_pending), "writer failure left publication work or flags behind")
	F.set_right(2)
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 6, "a later real setter did not publish after exception cleanup")

/datum/unit_test/dq_state_publication_batch_dead_receiver/Run()
	var/datum/dq_state_batch_fixture/F = allocate(/datum/dq_state_batch_fixture)
	state_batch(F, TYPE_PROC_REF(/datum/dq_state_batch_fixture, deleted_write))
	TEST_ASSERT(QDELETED(F), "the real queued receiver was not deleted inside the writer")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "deleted receiver left its batch open")
	TEST_ASSERT(!GLOB.state_batch_flushing && !length(GLOB.state_batch_pending), "deleted receiver retained weak publication records")

/datum/unit_test/dq_state_publication_batch_purity/Run()
	var/datum/dq_state_batch_fixture/F = allocate(/datum/dq_state_batch_fixture)
	stat_value(F, STAT_STATE_BATCH_SUM)
	set_global(nameof(GLOB.op_pure_expected), TRUE)
	set_global(nameof(GLOB.op_pure_violations), list())
	op_pure_begin()
	state_batch(F, TYPE_PROC_REF(/datum/dq_state_batch_fixture, pure_write))
	op_pure_end()
	TEST_ASSERT(length(GLOB.op_pure_violations) > 0, "batching suppressed the real setter's condition-purity guard")
	TEST_ASSERT_EQUAL(GLOB.op_pure_depth, 0, "batch completion changed the caller's balanced purity scope")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "purity diagnostic left the publication batch open")

#endif

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// A real status-source hook is synchronous, effectful, and not fault-swallowed.
// This exercises state_changed -> stat input recompute -> stat_status_changed.
/datum/dq_state_batch_hook_fixture
	parent_type = /datum/dq_state_batch_fixture

STAT(/datum/dq_state_batch_hook_fixture, state_batch_pulse, MAX, base = 0, units = LIFE_CYCLE, virtual = TRUE)
CAPABILITIES(/datum/dq_state_batch_hook_fixture)
	contributes(STAT_STATE_BATCH_PULSE, PROC_REF(pulse_value))

/datum/dq_state_batch_hook_fixture/proc/pulse_value(datum/act/A)
	return left

/datum/dq_state_batch_hook_fixture/fault/stat_status_changed(id, active)
	. = ..()
	if(id == STAT_STATE_BATCH_PULSE && active)
		throw EXCEPTION("Expected batch delivery status-hook failure")

/datum/unit_test/dq_state_publication_batch_delivery_fault/proc/write_receivers(datum/dq_state_batch_fixture/first, datum/dq_state_batch_fixture/second)
	first.set_left(1)
	second.set_left(2)

/datum/unit_test/dq_state_publication_batch_delivery_fault/Run()
	var/datum/dq_state_batch_hook_fixture/fault/first = allocate(/datum/dq_state_batch_hook_fixture/fault)
	var/datum/dq_state_batch_fixture/second = allocate(/datum/dq_state_batch_fixture)
	stat_value(first, STAT_STATE_BATCH_PULSE)
	stat_value(second, STAT_STATE_BATCH_SUM)
	var/prior_settle_depth = GLOB.stat_settle_depth
	var/prior_writing = GLOB.stat_writing
	var/caught = FALSE
	try
		state_batch(src, PROC_REF(write_receivers), list(first, second))
	catch(var/exception/fault)
		caught = findtext(fault.name, "Expected batch delivery status-hook failure") > 0
	TEST_ASSERT_EQUAL(GLOB.stat_settle_depth, prior_settle_depth, "Delivery fault leaked the real stat settle nesting depth")
	TEST_ASSERT_EQUAL(GLOB.stat_writing, prior_writing, "Delivery fault leaked the stat publication guard")
	TEST_ASSERT(caught, "The actual synchronous status-hook delivery fault was swallowed")
	TEST_ASSERT_EQUAL(stat_value(first, STAT_STATE_BATCH_PULSE), 1, "First receiver's real settled contribution was lost")
	TEST_ASSERT_EQUAL(stat_value(second, STAT_STATE_BATCH_SUM), 2, "A later live receiver lost its publication after the first delivery fault")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "Delivery fault left the writer boundary raised")
	TEST_ASSERT(!GLOB.state_batch_flushing && !length(GLOB.state_batch_pending), "Delivery fault left queued publication work")
	second.set_right(3)
	TEST_ASSERT_EQUAL(stat_value(second, STAT_STATE_BATCH_SUM), 5, "Subsequent ordinary publication stopped after the fault")

/datum/dq_state_batch_hook_fixture/reentrant
	var/active_edges = 0

/datum/dq_state_batch_hook_fixture/reentrant/stat_status_changed(id, active)
	. = ..()
	if(id == STAT_STATE_BATCH_PULSE && active)
		active_edges++
		state_batch(src, PROC_REF(write_right))

/datum/dq_state_batch_hook_fixture/reentrant/proc/write_left()
	set_left(1)

/datum/dq_state_batch_hook_fixture/reentrant/proc/write_right()
	set_right(2)

/datum/unit_test/dq_state_publication_batch_reentrant_delivery/Run()
	var/datum/dq_state_batch_hook_fixture/reentrant/F = allocate(/datum/dq_state_batch_hook_fixture/reentrant)
	stat_value(F, STAT_STATE_BATCH_PULSE)
	stat_value(F, STAT_STATE_BATCH_SUM)
	state_batch(F, TYPE_PROC_REF(/datum/dq_state_batch_hook_fixture/reentrant, write_left))
	TEST_ASSERT_EQUAL(F.active_edges, 1, "Real status-source delivery did not execute exactly once")
	TEST_ASSERT_EQUAL(F.right, 2, "Reentrant status-hook writer never installed its tracked value")
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 3, "Reentrant publication cohort was replaced or lost during flush")
	TEST_ASSERT_EQUAL(GLOB.state_batch_depth, 0, "Reentrant delivery left a nested boundary open")
	TEST_ASSERT(!GLOB.state_batch_flushing && !length(GLOB.state_batch_pending), "Reentrant delivery left the second cohort undelivered")
	F.set_right(4)
	TEST_ASSERT_EQUAL(stat_value(F, STAT_STATE_BATCH_SUM), 5, "Normal tracked publication failed after reentrant delivery")

#endif
