// Held busy work (code/engine/kernel/tasks.dm).

/// task_hold_busy(): an action whose continuation is a timer holds its worker busy for a duration; the
/// hold ends by its deadline, by task_release_busy(), or when the worker is deleted, and runs on_end.
/datum/unit_test/om/timed_action_hold

/datum/unit_test/om/timed_action_hold/run_om(list/made)
	var/datum/om_test_entity/holder = entity(made)
	var/datum/task/H = task_hold_busy(holder, 1 SECOND, /datum/om_test_entity/proc/timer_hit)
	TEST_ASSERT(istype(H), "the hold starts: [H]")
	TEST_ASSERT(task_claiming(holder), "the hold claims its holder")
	TEST_ASSERT(istext(task_hold_busy(holder, 1 SECOND)), "a second hold is refused while busy")
	scheduler_advance(1.5)
	TEST_ASSERT(!task_claiming(holder), "the hold ends at its deadline")
	TEST_ASSERT_EQUAL(length(holder.log), 1, "on_end ran once")
	task_hold_busy(holder, 5 SECONDS)
	TEST_ASSERT(task_release_busy(holder), "task_release_busy() ends a hold early")
	TEST_ASSERT(!task_claiming(holder), "released")
