// Object-model core S6 (doc/rewrite/object_model_core.md §4.11): om_after timers, task
// steps, typed prompt re-checks, the global owner and OM handles.

/datum/om_test_entity/bio

/datum/om_test_entity/bio/om_timer_clock()
	return CLOCK_BIO

/// Timer target: logs on the entity, and on `other` when given.
/datum/om_test_entity/proc/timer_hit(tag, datum/om_test_entity/other)
	log += tag
	other?.log += "[tag] via"

/proc/om_test_global_hit(datum/om_test_entity/L, tag)
	L.log += tag

/datum/om_test_entity/var/step_calls = 0

/datum/om_test_entity/proc/step_a(datum/om/task/T)
	log += "a"
	return STEP_NEXT

/datum/om_test_entity/proc/step_b(datum/om/task/T)
	step_calls++
	log += "b"
	return step_calls < 3 ? STEP_REPEAT(5) : STEP_NEXT

/datum/om_test_entity/proc/step_fail(datum/om/task/T)
	log += "f"
	return STEP_FAIL("nope")

/datum/om_test_entity/proc/step_done(datum/om/task/T)
	log += "d"
	return STEP_DONE

/datum/om_test_entity/proc/task_completed(datum/om/task/T)
	log += "complete"

/datum/om_test_entity/proc/task_cancelled(datum/om/task/T)
	log += "cancel:[T.reason]"

/datum/om/task/test_steps
	name = "test_steps"
	steps = list(/datum/om_test_entity/proc/step_a = 1 SECONDS, /datum/om_test_entity/proc/step_b = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled
	var/datum/thing

/datum/om/task/test_steps_fail
	name = "test_steps_fail"
	steps = list(/datum/om_test_entity/proc/step_a = 1 SECONDS, /datum/om_test_entity/proc/step_fail = 1 SECONDS, /datum/om_test_entity/proc/step_b = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

/datum/om/task/test_steps_done
	name = "test_steps_done"
	steps = list(/datum/om_test_entity/proc/step_done = 1 SECONDS, /datum/om_test_entity/proc/step_a = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

/// Passes while the target's `enabled` is set.
/datum/om/check/test_target_enabled

/datum/om/check/test_target_enabled/why_not(datum/actor, datum/om_test_entity/target)
	if(!istype(target) || !target.enabled)
		return "disabled"

/datum/om/prompt/confirm/test_recheck
	message = "go?"
	requires = list(/datum/om/check/test_target_enabled)

/datum/om/prompt/confirm/test_recheck/refused(reason)
	var/datum/om_test_entity/E = subject
	E?.log += "refused:[reason]"

/datum/om_test_entity/proc/prompt_answered(datum/om/prompt/confirm/test_recheck/ask)
	log += "answer:[ask.yes ? "Yes" : "No"]"

// ---------------------------------------------------------------- om_after

/datum/unit_test/om/timer_cancel_on_delete

/datum/unit_test/om/timer_cancel_on_delete/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om_test_entity/live = entity(made)
	var/id = om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "gone", witness)
	TEST_ASSERT(id, "om_after with a proc returns a timer id")
	TEST_ASSERT(om_timer_pending(E, id), "the timer is pending")
	om_after(live, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "live", witness)
	om_after(null, 1 SECONDS, /proc/om_test_global_hit, witness, "global")
	qdel(E)
	scheduler_advance(2)
	TEST_ASSERT(!("gone via" in witness.log), "a deleted owner's timer never runs")
	TEST_ASSERT("live" in live.log, "a live owner's timer runs")
	TEST_ASSERT("global" in witness.log, "the global owner runs unowned timers")
	var/cancel_id = om_after(live, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "cancelled")
	TEST_ASSERT(om_cancel_timer(live, cancel_id), "cancel finds the timer")
	scheduler_advance(2)
	TEST_ASSERT(!("cancelled" in live.log), "a cancelled timer never runs")

/// TIMER_UNIQUE and TIMER_OVERRIDE as keyed om_after: the key is (owner, proc, arguments).
/datum/unit_test/om/timer_keyed

/datum/unit_test/om/timer_keyed/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/first = om_after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once")
	TEST_ASSERT_EQUAL(om_after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once"), first, "a pending identical call is not scheduled twice")
	om_after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "other")
	TEST_ASSERT_EQUAL(om_timer_count(E), 2, "different arguments are a different key")
	scheduler_advance(0.6)
	var/replaced = om_after_replace(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once")
	TEST_ASSERT(replaced != first && !om_timer_pending(E, first), "replace cancels the pending call")
	scheduler_advance(0.6)
	TEST_ASSERT(!("once" in E.log), "a replaced call restarts its delay")
	TEST_ASSERT("other" in E.log, "the other key ran on time")
	scheduler_advance(0.6)
	var/runs = 0
	for(var/entry in E.log)
		if(entry == "once")
			runs++
	TEST_ASSERT_EQUAL(runs, 1, "the replaced call ran once")
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "a")
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "b")
	TEST_ASSERT_EQUAL(om_cancel_calls(E, /datum/om_test_entity/proc/timer_hit), 2, "cancel_calls drops every call of the proc")
	TEST_ASSERT_EQUAL(om_timer_count(E), 0, "nothing is left pending")

/datum/unit_test/om/timer_follows_clock

/datum/unit_test/om/timer_follows_clock/run_om(list/made)
	var/datum/om_test_entity/bio/E = entity(made, /datum/om_test_entity/bio)
	var/datum/om_test_entity/source = entity(made)
	om_after(E, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, "stasis")
	om_hold(E, EFFECT_CLOCK_BIO_INHIBIT, source, 1)
	scheduler_advance(5)
	TEST_ASSERT(!("stasis" in E.log), "stasis (an inhibited bio clock) pauses the timer")
	qdel(source)
	scheduler_advance(1)
	TEST_ASSERT(!("stasis" in E.log), "the paused time does not count")
	scheduler_advance(1.5)
	TEST_ASSERT("stasis" in E.log, "the timer runs once its clock has advanced 2 s")

	om_after(E, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, "suspended")
	scheduler_advance(1)
	om_suspend(E, E)
	scheduler_advance(5)
	TEST_ASSERT(!("suspended" in E.log), "suspension pauses the timer")
	om_unsuspend(E, E)
	scheduler_advance(1.5)
	TEST_ASSERT("suspended" in E.log, "the timer resumes with the time it had left")

	var/datum/om_test_entity/fast_source = entity(made)
	om_hold(E, EFFECT_CLOCK_BIO_MULT, fast_source, 2)
	om_after(E, 4 SECONDS, /datum/om_test_entity/proc/timer_hit, "fast")
	scheduler_advance(2.5)
	TEST_ASSERT("fast" in E.log, "a doubled clock halves the wait")

/datum/unit_test/om/timer_arg_deleted_cancels

/datum/unit_test/om/timer_arg_deleted_cancels/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/arg = entity(made)
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "weak", arg)
	var/dropped = sched.timers_dropped
	qdel(arg)
	scheduler_advance(2)
	TEST_ASSERT(!("weak" in E.log), "a timer whose argument was deleted does not run")
	TEST_ASSERT_EQUAL(sched.timers_dropped, dropped + 1, "the dropped call is counted")
	TEST_ASSERT(!om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "x", arg), "a deleted argument is refused up front")

/datum/om_test_entity/proc/timer_hit_list(tag, list/others)
	log += tag
	for(var/datum/om_test_entity/other in others)
		other.log += "[tag] via"

/// A datum inside a list argument (one level deep, as a member or under a text
/// key) is captured as a handle too: the pending record holds no reference to
/// it, so deleting it can't hard-delete, and the call is dropped when it fires.
/datum/unit_test/om/timer_list_arg_deleted_is_dropped

/datum/unit_test/om/timer_list_arg_deleted_is_dropped/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/member = entity(made)
	var/datum/om_test_entity/keyed = entity(made)
	var/datum/om_test_entity/kept = entity(made)
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, "listed", list(member))
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, "keyed", list("who" = keyed))
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, "kept", list(kept))
	var/list/T = E.om_rec.timers
	for(var/i in 1 to length(T) step OM_TIMER_STRIDE)
		var/list/captured = T[i + 3]
		var/list/inner = captured[2]
		for(var/entry in inner)
			TEST_ASSERT(!isdatum(entry), "a pending timer holds no datum in its list argument")
			if(istext(entry))
				TEST_ASSERT(!isdatum(inner[entry]), "nor as a keyed value")
	var/dropped = sched.timers_dropped
	qdel(member)
	qdel(keyed)
	scheduler_advance(2)
	TEST_ASSERT(!("listed" in E.log), "a call whose list member was deleted does not run")
	TEST_ASSERT(!("keyed" in E.log), "a call whose keyed list value was deleted does not run")
	TEST_ASSERT("kept" in E.log, "a call whose list member lives runs")
	TEST_ASSERT("kept via" in kept.log, "and gets the resolved datum back")
	TEST_ASSERT_EQUAL(sched.timers_dropped, dropped + 2, "both dropped calls are counted")

// ---------------------------------------------------------------- task steps

/datum/unit_test/om/task_step_results

/datum/unit_test/om/task_step_results/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om/task/T = om_task_start(/datum/om/task/test_steps, E)
	TEST_ASSERT(istype(T), "the steps task starts: [T]")
	scheduler_advance(1.1)
	TEST_ASSERT_EQUAL(E.log.Join(","), "a", "step a runs after its delay")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(E.log.Join(","), "a,b", "step b runs after its delay")
	scheduler_advance(0.3)
	TEST_ASSERT_EQUAL(E.log.Join(","), "a,b", "STEP_REPEAT(5) waits")
	scheduler_advance(1.2)
	TEST_ASSERT_EQUAL(E.log.Join(","), "a,b,b,b,complete", "repeats, then STEP_NEXT past the last step completes")
	TEST_ASSERT_EQUAL(T.state, OM_TASK_DONE, "the task is done")

	E.log.Cut()
	var/datum/om/task/F = om_task_start(/datum/om/task/test_steps_fail, E)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.log.Join(","), "a,f,cancel:nope", "STEP_FAIL cancels with its reason and later steps never run")
	TEST_ASSERT_EQUAL(F.reason, "nope", "the reason is kept")

	E.log.Cut()
	om_task_start(/datum/om/task/test_steps_done, E)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.log.Join(","), "d,complete", "STEP_DONE completes early")

	E.log.Cut()
	var/datum/om/task/C = om_task_start(/datum/om/task/test_steps, E)
	scheduler_advance(0.5)
	TEST_ASSERT(om_task_cancel(C, "stop"), "cancelling mid-task is safe")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(E.log.Join(","), "cancel:stop", "no step runs after a cancel")

	E.log.Cut()
	var/datum/om_test_entity/thing = entity(made)
	var/datum/om/task/W = om_task_start(/datum/om/task/test_steps, E, null, thing = thing)
	var/datum/om/task/test_steps/WS = W
	TEST_ASSERT_EQUAL(WS.thing, thing, "a datum param is task state")
	qdel(thing)
	TEST_ASSERT_EQUAL(E.log.Join(","), "cancel:gone", "deleting a datum in the task's state cancels it at once")
	TEST_ASSERT_NULL(WS.thing, "and clears the var, so on_cancel never sees a deleted datum")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(E.log.Join(","), "cancel:gone", "no step runs after")

// ---------------------------------------------------------------- prompts

/datum/unit_test/om/prompt_rechecks

/datum/unit_test/om/prompt_rechecks/run_om(list/made)
	sched.test_prompts = list()
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/user = entity(made)
	var/datum/om/prompt/P = om_ask_begin(E, user, /datum/om/prompt/confirm/test_recheck, /datum/om_test_entity/proc/prompt_answered, list("subject" = E))
	TEST_ASSERT(istype(P), "om_ask returns the pending prompt")
	TEST_ASSERT_EQUAL(length(sched.test_prompts), 1, "the test scheduler collected it")
	E.enabled = FALSE
	TEST_ASSERT_EQUAL(P.answer("Yes"), "disabled", "the requires are re-checked when the answer arrives")
	TEST_ASSERT_EQUAL(E.log.Join(","), "refused:disabled", "on_answer did not run; on_refused did")
	TEST_ASSERT_EQUAL(P.answer("Yes"), "answered", "a prompt is answered once")

	E.enabled = TRUE
	E.log.Cut()
	var/datum/om/prompt/P2 = om_ask_begin(E, user, /datum/om/prompt/confirm/test_recheck, /datum/om_test_entity/proc/prompt_answered, list("subject" = E))
	TEST_ASSERT_NULL(P2.answer("Yes"), "a passing re-check delivers the answer")
	TEST_ASSERT_EQUAL(E.log.Join(","), "answer:Yes", "on_answer ran with the answer")

	E.log.Cut()
	var/datum/om/prompt/P3 = om_ask_begin(E, user, /datum/om/prompt/confirm/test_recheck, /datum/om_test_entity/proc/prompt_answered, list("subject" = E))
	qdel(user)
	TEST_ASSERT_EQUAL(P3.answer("Yes"), "gone", "an answer after the user is deleted does nothing")
	TEST_ASSERT_EQUAL(length(E.log), 0, "nothing ran")

// ---------------------------------------------------------------- handles

/datum/unit_test/om/handles_resolve

/datum/unit_test/om/handles_resolve/run_om(list/made)
	var/datum/om_test_entity/A = entity(made)
	var/h = om_handle(A)
	TEST_ASSERT(istext(h), "a handle is text")
	TEST_ASSERT_EQUAL(om_handle(A), h, "the same datum gets the same handle")
	TEST_ASSERT_EQUAL(om_resolve(h), A, "a handle resolves to its datum")
	var/id = copytext(h, 1, findtext(h, ":"))
	qdel(A)
	TEST_ASSERT_NULL(om_resolve(h), "a deleted datum's handle resolves to null")
	var/datum/om_test_entity/B = entity(made)
	var/hb = om_handle(B)
	TEST_ASSERT_EQUAL(copytext(hb, 1, findtext(hb, ":")), id, "the freed id is reused")
	TEST_ASSERT(hb != h, "with a new generation")
	TEST_ASSERT_NULL(om_resolve(h), "the stale handle does not resolve to the id's new owner")
	TEST_ASSERT_EQUAL(om_resolve(hb), B, "the new handle resolves")
	TEST_ASSERT_NULL(om_resolve("junk"), "junk resolves to null")
	TEST_ASSERT_NULL(om_resolve(null), "null resolves to null")

// ---------------------------------------------------------------- sleep guard

/datum/om_test_entity/proc/sleepy_hit(tag)
	sleep(1)
	log += "[tag] woke"

/datum/om_test_entity/proc/step_sleepy(datum/om/task/T)
	sleep(1)
	return STEP_NEXT

/datum/om/task/test_steps_sleepy
	name = "test_steps_sleepy"
	steps = list(/datum/om_test_entity/proc/step_sleepy = 1 SECONDS, /datum/om_test_entity/proc/step_a = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

/// A sleeping timer or step callee can't stall the scheduler: it is cut loose, counted and
/// logged (and fails any test that doesn't expect it), and a sleeping step fails its task.
/datum/unit_test/om/sleeping_callee_is_caught

/datum/unit_test/om/sleeping_callee_is_caught/run_om(list/made)
	var/datum/om/scheduler/sched = om_scheduler()
	var/datum/om_test_entity/E = entity(made)
	GLOB.om_expect_sleep = TRUE
	var/before = sched.callees_slept
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/sleepy_hit, "sleepy")
	om_after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "after")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(sched.callees_slept, before + 1, "the sleeping timer callee is counted")
	TEST_ASSERT("after" in E.log, "a timer due with the sleeping one still runs in the same pass")

	E.log.Cut()
	var/datum/om/task/T = om_task_start(/datum/om/task/test_steps_sleepy, E)
	scheduler_advance(1.5)
	GLOB.om_expect_sleep = FALSE
	TEST_ASSERT_EQUAL(sched.callees_slept, before + 2, "the sleeping step is counted")
	TEST_ASSERT_EQUAL(T.state, OM_TASK_CANCELLED, "a sleeping step fails its task")
	TEST_ASSERT_EQUAL(T.reason, "slept", "with the reason 'slept'")
