/// await(): the kernel's one wait, and the rustg_job I/O kind.

/datum/unit_test/kernel_await
	var/awaited_result
	var/awaited_done = FALSE

/datum/unit_test/kernel_await/proc/finished()
	return awaited_done

/datum/unit_test/kernel_await/proc/wait_on(datum/waiter/W)
	set waitfor = FALSE
	awaited_result = await(W)
	awaited_done = TRUE

/datum/unit_test/kernel_await/Run()
	// A waiter resolves once; the awaiting proc wakes with the result.
	var/datum/waiter/W = new
	wait_on(W)
	TEST_ASSERT(!awaited_done, "await parks until the waiter resolves")
	TEST_ASSERT(W in kernel_waiters(), "an open waiter is on the kernel's list")
	TEST_ASSERT(waiter_resolve(W, "answer"), "the first resolve wins")
	TEST_ASSERT(!waiter_resolve(W, "late"), "a second resolve is ignored")
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(finished))), "await returned after the resolve")
	TEST_ASSERT_EQUAL(awaited_result, "answer", "with the first result")
	TEST_ASSERT(!(W in kernel_waiters()), "a resolved waiter leaves the list")

	// A timeout resolves it with a null result.
	awaited_done = FALSE
	awaited_result = "unset"
	var/datum/waiter/T = new(world.tick_lag * 2)
	wait_on(T)
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(finished))), "a timed-out await returned")
	TEST_ASSERT(T.timed_out, "and says it timed out")
	TEST_ASSERT_NULL(awaited_result, "with no result")

	// A cancel wakes the waiter without a result, and is not a timeout.
	awaited_done = FALSE
	awaited_result = "unset"
	var/datum/waiter/C = new
	wait_on(C)
	TEST_ASSERT(waiter_cancel(C), "cancel resolves an open waiter")
	TEST_ASSERT(run_until(CALLBACK(src, PROC_REF(finished))), "a cancelled await returned")
	TEST_ASSERT(C.cancelled && !C.timed_out, "cancelled, not timed out")
	TEST_ASSERT(!waiter_cancel(C), "cancelling twice is a no-op")

	// The rustg_job kind decodes a job's raw text and refuses a missing id, without calling rust-g.
	var/datum/io_backend/rustg_job/K = io_backend(/datum/io_backend/rustg_job)
	TEST_ASSERT_NOTNULL(K, "rustg_job is an I/O kind")
	TEST_ASSERT_EQUAL(K.arg_count, 1, "it takes the job id")
	var/datum/io_job/J = new
	J.request = list("42")
	TEST_ASSERT_EQUAL(K.start(J), "42", "start hands back the caller's job id")
	var/datum/io_job/bad = new
	bad.request = list(null)
	TEST_ASSERT_NULL(K.start(bad), "no job id is a start failure")
	TEST_ASSERT_NOTNULL(bad.preset_error, "with an error text")
	var/list/ok = K.decode("payload")
	TEST_ASSERT_EQUAL(ok[1], "payload", "a finished job's text is the result")
	TEST_ASSERT_NULL(ok[2], "with no error")
	var/list/failed = K.decode(RUSTG_JOB_ERROR)
	TEST_ASSERT_NULL(failed[1], "a panicked job has no result")
	TEST_ASSERT_NOTNULL(failed[2], "and an error")
