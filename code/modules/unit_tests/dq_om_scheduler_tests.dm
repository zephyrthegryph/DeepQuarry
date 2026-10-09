// Object-model core S6 (doc/rewrite/object_model_core.md Â§4.11): om_after timers, task
// steps, typed prompt re-checks, the global owner and OM handles.

/datum/om_test_entity/bio

/datum/om_test_entity/bio/timer_clock()
	return CLOCK_BIO

/// Timer target: logs on the entity, and on `other` when given.
/datum/om_test_entity/proc/timer_hit(tag, datum/om_test_entity/other)
	LAZYADD(log, tag)
	if(other)
		LAZYADD(other.log, "[tag] via")

/proc/om_test_global_hit(datum/om_test_entity/L, tag)
	LAZYADD(L.log, tag)

/datum/om_test_entity/var/step_calls = 0

/datum/om_test_entity/proc/step_a(datum/task/T)
	LAZYADD(log, "a")
	return STEP_NEXT

/datum/om_test_entity/proc/step_b(datum/task/T)
	step_calls++
	LAZYADD(log, "b")
	return step_calls < 3 ? STEP_REPEAT(5) : STEP_NEXT

/datum/om_test_entity/proc/step_fail(datum/task/T)
	LAZYADD(log, "f")
	return STEP_FAIL("nope")

/datum/om_test_entity/proc/step_done(datum/task/T)
	LAZYADD(log, "d")
	return STEP_DONE

/datum/om_test_entity/proc/task_completed(datum/task/T)
	LAZYADD(log, "complete")

/datum/om_test_entity/proc/task_cancelled(datum/task/T)
	LAZYADD(log, "cancel:[T.reason]")

/datum/task/test_steps
	name = "test_steps"
	steps = list(/datum/om_test_entity/proc/step_a = 1 SECONDS, /datum/om_test_entity/proc/step_b = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled
	var/datum/thing

/datum/task/test_steps_fail
	name = "test_steps_fail"
	steps = list(/datum/om_test_entity/proc/step_a = 1 SECONDS, /datum/om_test_entity/proc/step_fail = 1 SECONDS, /datum/om_test_entity/proc/step_b = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

/datum/task/test_steps_done
	name = "test_steps_done"
	steps = list(/datum/om_test_entity/proc/step_done = 1 SECONDS, /datum/om_test_entity/proc/step_a = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

// ---------------------------------------------------------------- om_after

/datum/unit_test/om/timer_cancel_on_delete

/datum/unit_test/om/timer_cancel_on_delete/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om_test_entity/live = entity(made)
	var/id = after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("gone", witness))
	TEST_ASSERT(id, "om_after with a proc returns a timer id")
	TEST_ASSERT(timer_pending(E, id), "the timer is pending")
	after(live, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("live", witness))
	after(null, 1 SECONDS, /proc/om_test_global_hit, with = list(witness, "global"))
	qdel(E)
	scheduler_advance(2)
	TEST_ASSERT(!("gone via" in witness.log), "a deleted owner's timer never runs")
	TEST_ASSERT("live" in live.log, "a live owner's timer runs")
	TEST_ASSERT("global" in witness.log, "the global owner runs unowned timers")
	var/cancel_id = after(live, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("cancelled"))
	TEST_ASSERT(timer_cancel(live, cancel_id), "cancel finds the timer")
	scheduler_advance(2)
	TEST_ASSERT(!("cancelled" in live.log), "a cancelled timer never runs")

/// TIMER_UNIQUE and TIMER_OVERRIDE as keyed om_after: the key is (owner, proc, arguments).
/datum/unit_test/om/timer_keyed

/datum/unit_test/om/timer_keyed/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/first = time_scheduler().after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once")
	TEST_ASSERT_EQUAL(time_scheduler().after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once"), first, "a pending identical call is not scheduled twice")
	time_scheduler().after_unique(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "other")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(E), 2, "different arguments are a different key")
	scheduler_advance(0.6)
	var/replaced = time_scheduler().after_replace(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, "once")
	TEST_ASSERT(replaced != first && !timer_pending(E, first), "replace cancels the pending call")
	scheduler_advance(0.6)
	TEST_ASSERT(!("once" in E.log), "a replaced call restarts its delay")
	TEST_ASSERT("other" in E.log, "the other key ran on time")
	scheduler_advance(0.6)
	var/runs = 0
	for(var/entry in E.log)
		if(entry == "once")
			runs++
	TEST_ASSERT_EQUAL(runs, 1, "the replaced call ran once")
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("a"))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("b"))
	TEST_ASSERT_EQUAL(time_scheduler().cancel_calls(E, /datum/om_test_entity/proc/timer_hit), 2, "cancel_calls drops every call of the proc")
	TEST_ASSERT_EQUAL(time_scheduler().timer_count(E), 0, "nothing is left pending")

/datum/unit_test/om/timer_follows_clock

/datum/unit_test/om/timer_follows_clock/run_om(list/made)
	var/datum/om_test_entity/bio/E = entity(made, /datum/om_test_entity/bio)
	// Stasis on the bio clock: life_om/bio_clock_follows_its_stat (a stat of living mobs).
	after(E, 2 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("suspended"))
	scheduler_advance(1)
	hold(E, STAT_SUSPENDED, TRUE, E)
	scheduler_advance(5)
	TEST_ASSERT(!("suspended" in E.log), "suspension pauses the timer")
	release(E, STAT_SUSPENDED, E)
	scheduler_advance(1.5)
	TEST_ASSERT("suspended" in E.log, "the timer resumes with the time it had left")

/// keeps_dead = TRUE: a deleted argument arrives as null and the call still runs, counted and logged (cleanup like vend_ready = TRUE
/// always happens).
/datum/unit_test/om/timer_arg_deleted_keeps_dead_is_nulled

/datum/unit_test/om/timer_arg_deleted_keeps_dead_is_nulled/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/arg = entity(made)
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("weak", arg), keeps_dead = TRUE)
	var/nulled = sched.timers_nulled
	var/dropped = sched.timers_dropped
	qdel(arg)
	scheduler_advance(2)
	TEST_ASSERT("weak" in E.log, "a keeps_dead timer whose argument was deleted still runs (the argument arrives as null)")
	TEST_ASSERT_EQUAL(sched.timers_nulled, nulled + 1, "the nulled call is counted")
	TEST_ASSERT_EQUAL(sched.timers_dropped, dropped, "and not dropped")
	TEST_ASSERT(after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("late", arg), keeps_dead = TRUE), "an already-deleted argument is scheduled as null")
	scheduler_advance(2)
	TEST_ASSERT("late" in E.log, "and the call runs")

/// The default: a timer whose datum argument has been deleted drops the call (counted and logged), keyed or not, and an already-deleted
/// argument is refused up front.
/datum/unit_test/om/timer_arg_deleted_default_drops

/datum/unit_test/om/timer_arg_deleted_default_drops/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/arg = entity(made)
	var/datum/om_test_entity/arg2 = entity(made)
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("plain", arg))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, key = "keyed_slot", with = list("keyed", arg2))
	var/dropped = sched.timers_dropped
	qdel(arg)
	qdel(arg2)
	scheduler_advance(2)
	TEST_ASSERT(!("plain" in E.log), "the default after() drops the call when a datum argument was deleted")
	TEST_ASSERT(!("keyed" in E.log), "a keyed after() drops it too")
	TEST_ASSERT(sched.timers_dropped >= dropped + 1, "the dropped call is counted")
	TEST_ASSERT(!after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("x", arg)), "an already-deleted argument is refused up front")

/// after_if_alive(): a pure effect is dropped when an argument is gone, and refused up front when
/// one is already deleted.
/datum/unit_test/om/timer_arg_deleted_if_alive_drops

/datum/unit_test/om/timer_arg_deleted_if_alive_drops/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/arg = entity(made)
	after_if_alive(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("weak", arg))
	var/dropped = sched.timers_dropped
	qdel(arg)
	scheduler_advance(2)
	TEST_ASSERT(!("weak" in E.log), "an after_if_alive() call whose argument was deleted does not run")
	TEST_ASSERT_EQUAL(sched.timers_dropped, dropped + 1, "the dropped call is counted")
	TEST_ASSERT(!after_if_alive(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("x", arg)), "a deleted argument is refused up front")

/datum/om_test_entity/proc/timer_hit_list(tag, list/others)
	LAZYADD(log, tag)
	for(var/datum/om_test_entity/other in others)
		LAZYADD(other.log, "[tag] via")

/// A datum inside a list argument (one level deep, as a member or under a text
/// key) is captured as a handle too: the pending record holds no reference to
/// it, so deleting it can't hard-delete; after_if_alive() drops the call when it fires, keeps_dead = TRUE
/// passes the member as null.
/datum/unit_test/om/timer_list_arg_deleted_is_dropped

/datum/unit_test/om/timer_list_arg_deleted_is_dropped/run_om(list/made)
	set_global("om_resolve_nulled", 7)
	var/datum/om_test_entity/E = entity(made)
	var/datum/om_test_entity/member = entity(made)
	var/datum/om_test_entity/keyed = entity(made)
	var/datum/om_test_entity/kept = entity(made)
	var/datum/om_test_entity/nulled = entity(made)
	after_if_alive(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, with = list("listed", list(member)))
	after_if_alive(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, with = list("keyed", list("who" = keyed)))
	after_if_alive(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, with = list("kept", list(kept)))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit_list, with = list("defaulted", list(nulled, kept)), keeps_dead = TRUE)
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
	qdel(nulled)
	scheduler_advance(2)
	TEST_ASSERT(!("listed" in E.log), "a call whose list member was deleted does not run")
	TEST_ASSERT(!("keyed" in E.log), "a call whose keyed list value was deleted does not run")
	TEST_ASSERT("kept" in E.log, "a call whose list member lives runs")
	TEST_ASSERT("kept via" in kept.log, "and gets the resolved datum back")
	TEST_ASSERT_EQUAL(sched.timers_dropped, dropped + 2, "both dropped calls are counted")
	TEST_ASSERT("defaulted" in E.log, "keeps_dead runs with the deleted member passed as null")
	TEST_ASSERT("defaulted via" in kept.log, "and the live member still resolves")
	TEST_ASSERT_EQUAL(GLOB.om_resolve_nulled, 7, "Timer resolution restores the caller scratch count after deleted arguments")

// ---------------------------------------------------------------- task steps

/datum/unit_test/om/task_step_results

/datum/unit_test/om/task_step_results/run_om(list/made)
	var/datum/om_test_entity/E = entity(made)
	var/datum/task/T = task_start(/datum/task/test_steps, E)
	TEST_ASSERT(istype(T), "the steps task starts: [T]")
	scheduler_advance(1.1)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "a", "step a runs after its delay")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "a,b", "step b runs after its delay")
	scheduler_advance(0.3)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "a,b", "STEP_REPEAT(5) waits")
	scheduler_advance(1.2)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "a,b,b,b,complete", "repeats, then STEP_NEXT past the last step completes")
	TEST_ASSERT_EQUAL(T.state, TASK_DONE, "the task is done")

	LAZYCLEARLIST(E.log)
	var/datum/task/F = task_start(/datum/task/test_steps_fail, E)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "a,f,cancel:nope", "STEP_FAIL cancels with its reason and later steps never run")
	TEST_ASSERT_EQUAL(F.reason, "nope", "the reason is kept")

	LAZYCLEARLIST(E.log)
	task_start(/datum/task/test_steps_done, E)
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "d,complete", "STEP_DONE completes early")

	LAZYCLEARLIST(E.log)
	var/datum/task/C = task_start(/datum/task/test_steps, E)
	scheduler_advance(0.5)
	TEST_ASSERT(task_cancel(C, "stop"), "cancelling mid-task is safe")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "cancel:stop", "no step runs after a cancel")

	LAZYCLEARLIST(E.log)
	var/datum/om_test_entity/thing = entity(made)
	var/datum/task/W = task_start(/datum/task/test_steps, E, null, thing = thing)
	var/datum/task/test_steps/WS = W
	TEST_ASSERT_EQUAL(WS.thing, thing, "a datum param is task state")
	qdel(thing)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "cancel:gone", "deleting a datum in the task's state cancels it at once")
	TEST_ASSERT_NULL(WS.thing, "and clears the var, so on_cancel never sees a deleted datum")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(jointext(E.log || list(), ","), "cancel:gone", "no step runs after")

// ---------------------------------------------------------------- handles

/datum/unit_test/om/handles_resolve

/datum/unit_test/om/handles_resolve/run_om(list/made)
	var/datum/om_test_entity/A = entity(made)
	var/h = entity_handle(A)
	TEST_ASSERT(istext(h), "a handle is text")
	TEST_ASSERT_EQUAL(entity_handle(A), h, "the same datum gets the same handle")
	TEST_ASSERT_EQUAL(resolve_handle(h), A, "a handle resolves to its datum")
	var/id = copytext(h, 1, findtext(h, ":"))
	qdel(A)
	TEST_ASSERT_NULL(resolve_handle(h), "a deleted datum's handle resolves to null")
	var/datum/om_test_entity/B = entity(made)
	var/hb = entity_handle(B)
	TEST_ASSERT_EQUAL(copytext(hb, 1, findtext(hb, ":")), id, "the freed id is reused")
	TEST_ASSERT(hb != h, "with a new generation")
	TEST_ASSERT_NULL(resolve_handle(h), "the stale handle does not resolve to the id's new owner")
	TEST_ASSERT_EQUAL(resolve_handle(hb), B, "the new handle resolves")
	TEST_ASSERT_NULL(resolve_handle("junk"), "junk resolves to null")
	TEST_ASSERT_NULL(resolve_handle(null), "null resolves to null")

// ---------------------------------------------------------------- sleep guard

/datum/om_test_entity/proc/sleepy_hit(tag)
	sleep(1)
	LAZYADD(log, "[tag] woke")

/datum/om_test_entity/proc/step_sleepy(datum/task/T)
	sleep(1)
	return STEP_NEXT

/datum/task/test_steps_sleepy
	name = "test_steps_sleepy"
	steps = list(/datum/om_test_entity/proc/step_sleepy = 1 SECONDS, /datum/om_test_entity/proc/step_a = 1 SECONDS)
	complete_proc = /datum/om_test_entity/proc/task_completed
	cancel_proc = /datum/om_test_entity/proc/task_cancelled

/// A sleeping timer or step callee can't stall the scheduler: it is cut loose, counted and
/// logged (and fails any test that doesn't expect it), and a sleeping step fails its task.
/datum/unit_test/om/sleeping_callee_is_caught

/datum/unit_test/om/sleeping_callee_is_caught/run_om(list/made)
	var/datum/om/scheduler/sched = time_scheduler()
	var/datum/om_test_entity/E = entity(made)
	set_global("om_expect_sleep", TRUE)
	var/before = sched.callees_slept
	after(E, 1 SECONDS, /datum/om_test_entity/proc/sleepy_hit, with = list("sleepy"))
	after(E, 1 SECONDS, /datum/om_test_entity/proc/timer_hit, with = list("after"))
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(sched.callees_slept, before + 1, "the sleeping timer callee is counted")
	TEST_ASSERT("after" in E.log, "a timer due with the sleeping one still runs in the same pass")

	LAZYCLEARLIST(E.log)
	var/datum/task/T = task_start(/datum/task/test_steps_sleepy, E)
	scheduler_advance(1.5)
	set_global("om_expect_sleep", FALSE)
	TEST_ASSERT_EQUAL(sched.callees_slept, before + 2, "the sleeping step is counted")
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "a sleeping step fails its task")
	TEST_ASSERT_EQUAL(T.reason, "slept", "with the reason 'slept'")
