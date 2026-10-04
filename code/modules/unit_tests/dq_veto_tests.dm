// Dynamic hooks on an action (doc/rewrite/final_api.html section 8 "World actions", section 10 "Hooks and events"): observe(source, /datum/act/x,
// listener, instead(...) | adjusts_with(...)) is the runtime counterpart of extend(/datum/act/x, ...). The handler runs on the listener; the hook ends with
// unobserve(), with the listener or with the source, through the activation machinery. Fixtures: code/tests/engine/veto_fixtures.dm.

/datum/unit_test/dq_veto
	abstract_type = /datum/unit_test/dq_veto

/datum/unit_test/dq_veto/Run()
	test_driver_begin()
	GLOB.act_report_capture = list()
	run_veto()
	GLOB.act_report_capture = null
	test_driver_end()

/datum/unit_test/dq_veto/proc/run_veto()
	return

/datum/unit_test/dq_veto/instead_takes_over_and_unobserve_ends_it

/datum/unit_test/dq_veto/instead_takes_over_and_unobserve_ends_it/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/datum/veto_listener/listener = new
	TEST_ASSERT_EQUAL(ACT_TRY(target, veto_strike, 10, 0), ACT_PASS, "nothing hooks the action yet")
	TEST_ASSERT_NOTNULL(observe(target, /datum/act/veto_strike, listener, instead(when(TYPE_PROC_REF(/datum/veto_listener, blocks)), then(TYPE_PROC_REF(/datum/veto_listener, take)))), "observe on an act returns the activation")
	var/datum/act/veto_strike/strike = ACT_TRY(target, veto_strike, 10, 0)
	TEST_ASSERT_NULL(strike, "the listener's instead took the strike over")
	TEST_ASSERT(ACT_TAKEN_OVER, "taken over, not refused")
	TEST_ASSERT_EQUAL(listener.ran, 1, "its handler ran")
	TEST_ASSERT(listener.ran_on_me, "on the listener (the context held it)")
	TEST_ASSERT(listener.target_was_observed, "with A.target the observed entity")
	// The gate says no: the action goes on and the act is a real one.
	listener.blocking = FALSE
	strike = ACT_TRY(target, veto_strike, 10, 0)
	TEST_ASSERT_NOTNULL(strike, "the gate did not hold: the action goes on")
	TEST_ASSERT_EQUAL(listener.ran, 1, "and the handler did not run")
	act_done(strike)
	// unobserve ends the hook.
	listener.blocking = TRUE
	TEST_ASSERT_EQUAL(unobserve(target, /datum/act/veto_strike, listener), 1, "unobserve ended one hook")
	TEST_ASSERT_EQUAL(ACT_TRY(target, veto_strike, 10, 0), ACT_PASS, "nothing hooks the action again")
	qdel(listener)

/datum/unit_test/dq_veto/the_hook_ends_with_either_side

/datum/unit_test/dq_veto/the_hook_ends_with_either_side/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/datum/veto_listener/listener = new
	observe(target, /datum/act/veto_strike, listener, instead(when(TYPE_PROC_REF(/datum/veto_listener, blocks))))
	TEST_ASSERT_NULL(ACT_TRY(target, veto_strike, 10, 0), "the hook vetoes")
	qdel(listener)
	TEST_ASSERT_EQUAL(ACT_TRY(target, veto_strike, 10, 0), ACT_PASS, "the listener died: the hook went with it")
	TEST_ASSERT(!length(target.rx?.activations), "and its activation is gone from the source")
	var/obj/veto_fixture/doomed = allocate(/obj/veto_fixture)
	var/datum/veto_listener/survivor = new
	observe(doomed, /datum/act/veto_strike, survivor, instead(when(TYPE_PROC_REF(/datum/veto_listener, blocks))))
	TEST_ASSERT(length(survivor.rx?.sourced), "the listener is the source of the hook")
	qdel(doomed)
	TEST_ASSERT(!length(survivor.rx?.sourced), "the observed entity died: the hook went with it, and the listener keeps nothing of it")
	qdel(survivor)

/datum/unit_test/dq_veto/handlers_decline_answer_and_first_taker_wins

/datum/unit_test/dq_veto/handlers_decline_answer_and_first_taker_wins/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/datum/veto_listener/first = new
	var/datum/veto_listener/second = new
	first.answer = HOOK_DECLINE
	second.answer = 42
	observe(target, /datum/act/veto_strike, first, instead(then(TYPE_PROC_REF(/datum/veto_listener, take)), order = ORDER_EARLY))
	observe(target, /datum/act/veto_strike, second, instead(then(TYPE_PROC_REF(/datum/veto_listener, take))))
	TEST_ASSERT_NULL(ACT_TRY(target, veto_strike, 10, 0), "the second took the strike over")
	TEST_ASSERT_EQUAL(first.ran, 1, "the first was asked first")
	TEST_ASSERT_EQUAL(second.ran, 1, "and declined: the second took it over")
	TEST_ASSERT(ACT_TAKEN_OVER, "a takeover")
	TEST_ASSERT_EQUAL(ACT_REPLY, 42, "with the second's answer as the reply")
	second.answer = HOOK_DECLINE
	var/datum/act/veto_strike/strike = ACT_TRY(target, veto_strike, 10, 0)
	TEST_ASSERT_NOTNULL(strike, "both declined: the action goes on")
	act_done(strike)
	qdel(first)
	qdel(second)

/datum/unit_test/dq_veto/adjusts_with_writes_the_act_in_flight

/datum/unit_test/dq_veto/adjusts_with_writes_the_act_in_flight/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/datum/veto_listener/a = new
	var/datum/veto_listener/b = new
	a.flag = 1
	b.flag = 4
	observe(target, /datum/act/veto_strike, a, adjusts_with(TYPE_PROC_REF(/datum/veto_listener, add_flag)))
	observe(target, /datum/act/veto_strike, b, adjusts_with(TYPE_PROC_REF(/datum/veto_listener, add_flag)))
	var/datum/act/veto_strike/strike = ACT_TRY(target, veto_strike, 10, 2)
	TEST_ASSERT_NOTNULL(strike, "an adjustment never takes the action over")
	TEST_ASSERT_EQUAL(ACT_FINAL(strike, protection, 2), 7, "every adjusts_with ran and the flags combined (2 | 1 | 4)")
	TEST_ASSERT_EQUAL(ACT_FINAL(strike, amount, 10), 12, "and each wrote the amount")
	TEST_ASSERT(a.ran_on_me && b.ran_on_me, "each ran on its own listener")
	act_done(strike)
	qdel(a)
	var/datum/act/veto_strike/after_a = ACT_TRY(target, veto_strike, 10, 0)
	TEST_ASSERT_EQUAL(ACT_FINAL(after_a, amount, 10), 11, "with one listener gone only the other adjusts")
	act_done(after_a)
	qdel(b)

/datum/unit_test/dq_veto/unobserve_all_and_observer_counts

/datum/unit_test/dq_veto/unobserve_all_and_observer_counts/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/obj/veto_fixture/other = allocate(/obj/veto_fixture)
	var/datum/veto_listener/listener = new
	var/datum/veto_listener/second = new
	observe(target, /datum/act/veto_strike, listener, instead(when(TYPE_PROC_REF(/datum/veto_listener, blocks))))
	observe(other, /datum/act/veto_strike, listener, adjusts_with(TYPE_PROC_REF(/datum/veto_listener, add_flag)))
	observe(target, /datum/act/veto_strike, second, adjusts_with(TYPE_PROC_REF(/datum/veto_listener, add_flag)))
	TEST_ASSERT_EQUAL(observer_count(target, /datum/act/veto_strike), 2, "two listeners observe the action on the target")
	TEST_ASSERT_EQUAL(observer_count(other, /datum/act/veto_strike), 1, "one on the other")
	TEST_ASSERT_EQUAL(observer_count(target, /datum/act/hit), 0, "none observe another action")
	TEST_ASSERT_EQUAL(unobserve_all(listener), 2, "unobserve_all ends everything a listener observes, wherever it is")
	TEST_ASSERT_EQUAL(observer_count(target, /datum/act/veto_strike), 1, "the other listener's hook stays")
	TEST_ASSERT_EQUAL(observer_count(other, /datum/act/veto_strike), 0, "and the hook on the other entity is gone")
	qdel(listener)
	qdel(second)

/datum/unit_test/dq_veto/qdeleting_notice_reaches_observers_of_the_dying_entity

/datum/unit_test/dq_veto/qdeleting_notice_reaches_observers_of_the_dying_entity/run_veto()
	var/obj/veto_fixture/target = allocate(/obj/veto_fixture)
	var/datum/veto_listener/watcher = new
	observe(target, /datum/notice/qdeleting, watcher, then(TYPE_PROC_REF(/datum/veto_listener, take)))
	qdel(target)
	TEST_ASSERT_EQUAL(watcher.ran, 1, "an observer of an entity hears that its deletion has begun")
	TEST_ASSERT(watcher.ran_on_me, "on the observer")
	qdel(watcher)
	// An entity observing itself hears it too: its own deletion has begun, and nothing else runs on it from here.
	var/obj/veto_fixture/loner = allocate(/obj/veto_fixture)
	var/datum/veto_listener/self_watcher = new
	observe(self_watcher, /datum/notice/qdeleting, self_watcher, then(TYPE_PROC_REF(/datum/veto_listener, take)))
	qdel(self_watcher)
	TEST_ASSERT_EQUAL(self_watcher.ran, 1, "a datum that observes itself hears its own qdeleting")
	qdel(loner)
