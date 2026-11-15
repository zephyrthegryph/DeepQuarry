// The mob service's two-minute profile dump writes its lines within the tick's budget (dump_profile()), the same lines as before, and keeps what it
// has not written for the next step.

/datum/unit_test/dq_mob_profile_dump_writes_and_clears

/datum/unit_test/dq_mob_profile_dump_writes_and_clears/Run()
	var/datum/system/mobs/S = SSmobs
	S.profile_lines = null
	var/queued_before = log_file_counts()[1]
	var/result = S.dump_profile(0)
	TEST_ASSERT(result == STEP_DONE || result == STEP_YIELD, "a dump ends its step or asks to resume")
	var/guard = 0
	while(result == STEP_YIELD && ++guard < 10)
		result = S.dump_profile(0)
	TEST_ASSERT_EQUAL(result, STEP_DONE, "a dump finishes within a few steps")
	TEST_ASSERT_NULL(S.profile_lines, "and holds no line back")
	TEST_ASSERT(log_file_counts()[1] > queued_before, "its lines were handed to the log writer")
