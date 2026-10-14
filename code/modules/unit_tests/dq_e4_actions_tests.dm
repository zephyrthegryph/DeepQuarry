// E4, actions and hooks: the gate fixtures of doc/rewrite/final_api.html section 19 "The seven workers" (fixtures: code/tests/engine/e4_fixtures.dm).
//
// One ACTION with an instead (its notice marked replaced), an adjusts and an on_notice; ACT_PASS allocates nothing; an outcome nobody asked for
// allocates nothing; a ninth nested notice is queued to the next drain point and fails the build, and a ninth nested action ends ACT_REFUSED
// ("too deeply nested") and fails it too; while_slotted grants and releases on exit, delete and holder delete; the twins deliver in both directions.
// (The pairing lint's own fixture is tools/analyze/fixtures/sem__handlers.)

/datum/unit_test/dq_e4
	abstract_type = /datum/unit_test/dq_e4

/// A clean driver around the test and the depth reports captured, so a deliberate one is read instead of failing the run.
/datum/unit_test/dq_e4/Run()
	test_driver_begin()
	GLOB.act_report_capture = list()
	run_e4()
	GLOB.act_report_capture = null
	test_driver_end()

/datum/unit_test/dq_e4/proc/run_e4()
	return

/datum/unit_test/dq_e4/action_instead_adjusts_on_notice

/datum/unit_test/dq_e4/action_instead_adjusts_on_notice/run_e4()
	var/obj/e4_fixture/target/T = allocate(/obj/e4_fixture/target)
	// Shield down: the adjusts halves the amount, the strike goes on, act_done publishes the committed notice.
	var/datum/act/e4_strike/F = ACT_TRY(T, e4_strike, 10)
	TEST_ASSERT_NOTNULL(F, "a hooked action returns its act")
	TEST_ASSERT(F != ACT_PASS, "a real one: something hooks it")
	TEST_ASSERT_EQUAL(ACT_FINAL(F, amount, 10), 5, "adjusts(amount, scale = 0.5) changed the act's field, and ACT_FINAL reads the final one")
	act_done(F)
	TEST_ASSERT_EQUAL(T.heard_committed, 1, "the on_notice listener heard the committed strike")
	TEST_ASSERT_EQUAL(T.last_amount, 5, "with the final amount")
	TEST_ASSERT_EQUAL(T.last_outcome, ACT_COMMITTED, "and A.outcome")
	TEST_ASSERT_EQUAL(T.heard_replaced, 0, "the listener for replaced strikes did not")
	TEST_ASSERT_EQUAL(T.heard_any, 1, "the ACT_ANY listener heard it")
	// Shield up: the instead hook takes the strike over. ACT_TRY returns null, the notice is marked replaced.
	T.shield = TRUE
	var/datum/act/e4_strike/taken = ACT_TRY(T, e4_strike, 10)
	TEST_ASSERT_NULL(taken, "a takeover returns null")
	if(taken)
		act_cancel(taken)
	TEST_ASSERT_EQUAL(T.absorbed, 1, "the instead handler ran")
	TEST_ASSERT_EQUAL(T.heard_committed, 1, "a takeover is not announced as a strike that landed")
	TEST_ASSERT_EQUAL(T.heard_replaced, 1, "the listener that asked for replaced strikes heard it")
	TEST_ASSERT_EQUAL(T.last_outcome, ACT_REPLACED, "with outcome ACT_REPLACED")
	TEST_ASSERT_EQUAL(T.heard_any, 2, "the ACT_ANY listener heard it too")
	// A path that decides not to finish.
	T.shield = FALSE
	var/datum/act/e4_strike/dropped = ACT_TRY(T, e4_strike, 10)
	TEST_ASSERT_NOTNULL(dropped, "the shield is down again")
	act_cancel(dropped)
	TEST_ASSERT_EQUAL(T.heard_committed, 1, "a cancelled strike is not a committed one")
	TEST_ASSERT_EQUAL(T.heard_any, 3, "the ACT_ANY listener heard the refusal")

/datum/unit_test/dq_e4/act_pass_allocates_nothing

/datum/unit_test/dq_e4/act_pass_allocates_nothing/run_e4()
	var/obj/e4_fixture/plain/P = allocate(/obj/e4_fixture/plain)
	var/before = GLOB.act_taken
	var/notices_before = GLOB.notice_taken
	var/datum/act/e4_plain/F = ACT_TRY(P, e4_plain)
	TEST_ASSERT_EQUAL(F, ACT_PASS, "nothing hooks it and no one listens: ACT_PASS")
	act_done(F)
	act_cancel(F)
	TEST_ASSERT_EQUAL(ACT_FINAL(F, amount, 7), 7, "ACT_FINAL on ACT_PASS reads the caller's local")
	TEST_ASSERT_EQUAL(GLOB.act_taken, before, "no act was allocated")
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices_before, "no notice either")
	var/datum/object_pool/pool = GLOB.object_pools[/datum/act/e4_plain]
	TEST_ASSERT(!pool || pool.taken == 0, "the pool of the act type was never touched")

/datum/unit_test/dq_e4/an_outcome_nobody_asked_for_allocates_nothing

/datum/unit_test/dq_e4/an_outcome_nobody_asked_for_allocates_nothing/run_e4()
	var/obj/e4_fixture/quiet/Q = allocate(/obj/e4_fixture/quiet)
	var/datum/act/e4_quiet/F = ACT_TRY(Q, e4_quiet)
	TEST_ASSERT(F != ACT_PASS && !isnull(F), "a listener for the committed notice counts as hooking the action: a real act")
	var/notices_before = GLOB.notice_taken
	act_cancel(F)
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices_before, "the refusal builds no notice: nobody asked for it")
	TEST_ASSERT_EQUAL(Q.heard_committed, 0, "and the committed listener did not hear it")
	var/datum/act/e4_quiet/G = ACT_TRY(Q, e4_quiet)
	act_done(G)
	TEST_ASSERT_EQUAL(GLOB.notice_taken, notices_before + 1, "a committed one builds its notice")
	TEST_ASSERT_EQUAL(Q.heard_committed, 1, "and the listener hears it")

/datum/unit_test/dq_e4/a_ninth_nested_notice_is_queued

/datum/unit_test/dq_e4/a_ninth_nested_notice_is_queued/run_e4()
	test_counters_reset()
	GLOB.e0_chain_handled = 0
	e0_start_notice_chain(ACT_MAX_DEPTH + 1)
	TEST_ASSERT_EQUAL(GLOB.e0_chain_handled, ACT_MAX_DEPTH, "eight nested notices were delivered synchronously")
	TEST_ASSERT_EQUAL(test_notice_queued_count(/datum/notice/e0_chain), 1, "the ninth was queued")
	TEST_ASSERT_EQUAL(length(GLOB.act_report_capture), 1, "and reported, so a test build fails on it")
	TEST_ASSERT(findtext(GLOB.act_report_capture[1], "queued to the next drain point"), "naming what happened")
	TEST_ASSERT(findtext(GLOB.act_report_capture[1], "e0_chain"), "and the chain")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 1, "it waits for the next drain point")
	test_drain()
	TEST_ASSERT_EQUAL(GLOB.e0_chain_handled, ACT_MAX_DEPTH + 1, "the drain point delivered it, late: delayed, never dropped")
	TEST_ASSERT_EQUAL(length(GLOB.notice_late_queue), 0, "the queue is empty")
	TEST_ASSERT_EQUAL(test_notice_count(/datum/notice/e0_chain) + test_notice_queued_count(/datum/notice/e0_chain), ACT_MAX_DEPTH + 1, "the engine counted each notice, the queued one when it was queued")

/datum/unit_test/dq_e4/a_ninth_nested_action_is_refused

/datum/unit_test/dq_e4/a_ninth_nested_action_is_refused/run_e4()
	var/obj/e4_fixture/nester/N = allocate(/obj/e4_fixture/nester)
	test_record()
	var/datum/act/e4_nest/F = ACT_TRY(N, e4_nest)
	TEST_ASSERT_NULL(F, "the outermost action was taken over")
	if(F)
		act_cancel(F)
	TEST_ASSERT_EQUAL(N.runs, ACT_MAX_DEPTH, "eight nested takeovers ran")
	TEST_ASSERT_EQUAL(GLOB.act_too_deep, 1, "the ninth nested action was refused")
	TEST_ASSERT_EQUAL(length(GLOB.act_report_capture), 1, "and reported, so a test build fails on it")
	TEST_ASSERT(findtext(GLOB.act_report_capture[1], "too deeply nested"), "with the reason")
	TEST_ASSERT(findtext(GLOB.act_report_capture[1], "e4_nest"), "and the chain")
	var/refusals = 0
	for(var/datum/test_event/row as anything in test_recorded())
		if(row.kind == TEST_EVENT_OUTCOME && row.to_value == ACT_REFUSED)
			refusals++
	TEST_ASSERT_EQUAL(refusals, 1, "the recorder saw it end ACT_REFUSED")
	TEST_ASSERT_EQUAL(GLOB.act_depth, 0, "and nothing is left running")

/datum/unit_test/dq_e4/while_slotted_hooks_grant_and_release

/datum/unit_test/dq_e4/while_slotted_hooks_grant_and_release/run_e4()
	var/obj/e4_fixture/wearer/W = allocate(/obj/e4_fixture/wearer)
	var/obj/item/e4_fixture/amulet/amulet = allocate(/obj/item/e4_fixture/amulet)
	var/datum/act/e4_strike/F = ACT_TRY(W, e4_strike, 10)
	TEST_ASSERT_EQUAL(F, ACT_PASS, "before the amulet is worn nothing hooks the wearer")
	act_done(F)
	// Worn: its hook applies to the wearer.
	activations_slot_enter(amulet, W, "e4_slot")
	var/datum/act/e4_strike/G = ACT_TRY(W, e4_strike, 10)
	TEST_ASSERT(G != ACT_PASS && !isnull(G), "worn: the hook is the wearer's")
	TEST_ASSERT_EQUAL(ACT_FINAL(G, amount, 10), 11, "adjusts(amount, by = 1)")
	act_done(G)
	var/datum/activation/A = activations_of_cap(W, CAP_HOOK)[1]
	TEST_ASSERT(A.source == amulet && A.scope == SCOPE_SLOT, "sourced by the amulet, scoped to the slot")
	// Exit.
	activations_slot_exit(amulet, W, "e4_slot")
	TEST_ASSERT(A.dead, "it ends when the amulet leaves the slot")
	var/datum/act/e4_strike/H = ACT_TRY(W, e4_strike, 10)
	TEST_ASSERT_EQUAL(H, ACT_PASS, "and the wearer is unhooked at once")
	act_done(H)
	// Deleted.
	activations_slot_enter(amulet, W, "e4_slot")
	var/datum/activation/B = activations_of_cap(W, CAP_HOOK)[1]
	qdel(amulet)
	TEST_ASSERT(B.dead, "it ends when the amulet is deleted")
	var/datum/act/e4_strike/I = ACT_TRY(W, e4_strike, 10)
	TEST_ASSERT_EQUAL(I, ACT_PASS, "and the wearer is unhooked")
	act_done(I)
	// Holder deleted: the activation goes with it.
	var/obj/item/e4_fixture/amulet/second = allocate(/obj/item/e4_fixture/amulet)
	activations_slot_enter(second, W, "e4_slot")
	var/datum/activation/C = activations_of_cap(W, CAP_HOOK)[1]
	qdel(W)
	TEST_ASSERT(C.dead, "it ends when the holder is deleted")
	// ON_CONTENTS: what a bed gives its occupant.
	var/obj/e4_fixture/bed/bed = allocate(/obj/e4_fixture/bed)
	var/obj/e4_fixture/wearer/patient = allocate(/obj/e4_fixture/wearer)
	activations_slot_enter(patient, bed, "e4_bed")
	var/datum/act/e4_strike/J = ACT_TRY(patient, e4_strike, 10)
	TEST_ASSERT(J != ACT_PASS && !isnull(J), "buckled in: the bed's hook is the occupant's")
	TEST_ASSERT_EQUAL(ACT_FINAL(J, amount, 10), 12, "adjusts(amount, by = 2)")
	act_done(J)
	activations_slot_exit(patient, bed, "e4_bed")
	var/datum/act/e4_strike/K = ACT_TRY(patient, e4_strike, 10)
	TEST_ASSERT_EQUAL(K, ACT_PASS, "unbuckled: gone")
	act_done(K)

/datum/unit_test/dq_e4/observe_and_unobserve

/datum/unit_test/dq_e4/observe_and_unobserve/run_e4()
	var/obj/e4_fixture/plain/source = allocate(/obj/e4_fixture/plain)
	var/obj/e4_fixture/listener/listener = allocate(/obj/e4_fixture/listener)
	var/datum/act/e4_quiet/before = ACT_TRY(source, e4_quiet)
	TEST_ASSERT_EQUAL(before, ACT_PASS, "nobody listens to the source yet")
	act_done(before)
	var/datum/activation/A = listener.watch(source)
	TEST_ASSERT_NOTNULL(A, "observe is an activation of a hook capability on the source")
	TEST_ASSERT(A.source == listener && A.holder == source, "sourced by the listener, held by the observed entity")
	var/datum/act/e4_quiet/F = ACT_TRY(source, e4_quiet)
	TEST_ASSERT(F != ACT_PASS && !isnull(F), "an observer makes the action a real one")
	act_done(F)
	TEST_ASSERT_EQUAL(listener.seen, 1, "the handler ran")
	TEST_ASSERT(listener.seen_holder_was_me, "on the listener: A.holder is the listener")
	TEST_ASSERT_EQUAL(listener.seen_target_ref, REF(source), "and A.target is the observed source")
	TEST_ASSERT_EQUAL(unobserve(source, /datum/notice/e4_hushed, listener), 1, "unobserve ends it")
	TEST_ASSERT(A.dead, "the activation is dead at once")
	var/datum/act/e4_quiet/G = ACT_TRY(source, e4_quiet)
	TEST_ASSERT_EQUAL(G, ACT_PASS, "and the source is unhooked")
	act_done(G)
	// Either end dying ends it.
	var/datum/activation/B = listener.watch(source)
	qdel(listener)
	TEST_ASSERT(B.dead, "deleting the listener ends it")
	var/obj/e4_fixture/listener/second = allocate(/obj/e4_fixture/listener)
	var/datum/activation/C = second.watch(source)
	qdel(source)
	TEST_ASSERT(C.dead, "deleting the observed entity ends it")

/datum/unit_test/dq_e4/on_change_and_on_op

/datum/unit_test/dq_e4/on_change_and_on_op/run_e4()
	var/obj/e4_fixture/switch/S = allocate(/obj/e4_fixture/switch)
	S.set_powered(TRUE)
	TEST_ASSERT_EQUAL(S.entered, 0, "an on_change hook runs at the drain, not in the setter")
	test_drain()
	TEST_ASSERT_EQUAL(S.entered, 1, "ENTER: the condition became true")
	TEST_ASSERT_EQUAL(S.exited, 0, "and not EXIT")
	S.set_powered(FALSE)
	test_drain()
	TEST_ASSERT_EQUAL(S.exited, 1, "EXIT: it became false")
	TEST_ASSERT_EQUAL(S.entered, 1, "ENTER did not run again")
	S.set_charge_level(3)
	S.set_charge_level(5)
	test_drain()
	TEST_ASSERT_EQUAL(S.charge_changes, 1, "ANY on a key: once per drain however many writes")
	S.set_charge_level(5)
	test_drain()
	TEST_ASSERT_EQUAL(S.charge_changes, 1, "a write that changes nothing runs nothing")
	// on_op: sugar for on_notice(/datum/notice/op_done, op = key).
	var/datum/notice/op_done/other = notice_take(/datum/notice/op_done)
	other.op_key = "e4.other"
	notice_publish(S, other)
	TEST_ASSERT_EQUAL(S.ops_heard, 0, "another op key is not heard")
	var/datum/notice/op_done/mine = notice_take(/datum/notice/op_done)
	mine.op_key = "e4.toggle"
	notice_publish(S, mine)
	TEST_ASSERT_EQUAL(S.ops_heard, 1, "its own key is")

/datum/unit_test/om/dq_e4_twins_deliver_both_ways

/datum/unit_test/om/dq_e4_twins_deliver_both_ways/run_om(list/made)
	var/datum/om_test_entity/e4_twin/listener = entity(made, /datum/om_test_entity/e4_twin)
	var/obj/e4_fixture/plain/bumped_thing = new
	made += bumped_thing
	// Emitting the event reaches the on_notice listener through the twin notice.
	PUBLISH_LEGACY(listener, /datum/notice/atom_bumped, bumped_thing)
	TEST_ASSERT_EQUAL(listener.notices_heard, 1, "Emitting the event published its twin notice to the on_notice listener")
	TEST_ASSERT_EQUAL(listener.last_bumped, bumped_thing, "with the payload")
	// It does not bounce: the notice the event published is not emitted back as an event.
	TEST_ASSERT_EQUAL(listener.notices_heard, 1, "the twin did not bounce back")
