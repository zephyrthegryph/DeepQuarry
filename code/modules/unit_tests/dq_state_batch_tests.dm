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
