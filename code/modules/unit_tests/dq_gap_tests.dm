// Framework gap closures (doc/rewrite/codemod_rules.md): OP_DECLINE. Fixtures: code/tests/engine/gap_fixtures.dm.

/datum/unit_test/dq_gap
	abstract_type = /datum/unit_test/dq_gap

/datum/unit_test/dq_gap/Run()
	test_driver_begin()
	run_gap()
	test_driver_end()

/datum/unit_test/dq_gap/proc/run_gap()
	return

/// A handler that answers OP_DECLINE leaves the click to the next candidate; one that does not decline is the only one that runs.
/datum/unit_test/dq_gap/op_decline_falls_through
/datum/unit_test/dq_gap/op_decline_falls_through/run_gap()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/gap_decline/target = allocate(/obj/gap_decline, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	var/datum/op_result/R = test_click(H, target, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(target.second, 1, "the declined click went to the next candidate")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "which committed")
	target.declines = FALSE
	test_click(H, target, thing)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(target.first, 1, "not declining, the first op took the click")
	TEST_ASSERT_EQUAL(target.second, 1, "and the second did not run")

/// Every candidate declining leaves the driver the declined result and tells nobody.
/datum/unit_test/dq_gap/op_decline_alone_is_not_handled
/datum/unit_test/dq_gap/op_decline_alone_is_not_handled/run_gap()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	var/obj/gap_decline_alone/target = allocate(/obj/gap_decline_alone, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	var/datum/op_result/R = test_click(H, target, thing)
	TEST_ASSERT_EQUAL(target.first, 1, "the handler ran once")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_DECLINED, "the result says declined, not refused or committed")

/// A type-level every() with when = a tracked var: parked while false (no timer), runs on its interval while true, parks again when it clears.
/datum/unit_test/dq_gap/every_parks_and_wakes
/datum/unit_test/dq_gap/every_parks_and_wakes/run_gap()
	var/obj/gap_every/E = allocate(/obj/gap_every, run_loc_floor_bottom_left)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(E.ticks, 0, "false: it never ran")
	TEST_ASSERT(length(E.rx?.every_parked), "and it is parked, holding no timer")
	E.set_active(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(E.ticks >= 4 && E.ticks <= 5, "true: it ran on its interval (ran [E.ticks])")
	TEST_ASSERT(!length(E.rx?.every_parked), "no longer parked")
	E.set_active(FALSE)
	var/seen = E.ticks
	test_time(5 SECONDS)
	TEST_ASSERT(E.ticks <= seen + 1, "false again: it stopped (ran [E.ticks - seen] more)")
	TEST_ASSERT(length(E.rx?.every_parked), "and parked")
	E.set_active(TRUE)
	seen = E.ticks
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks > seen, "woken again")

/// An instance that starts true arms at once.
/datum/unit_test/dq_gap/every_starts_when_true
/datum/unit_test/dq_gap/every_starts_when_true/run_gap()
	var/obj/gap_every/running/E = allocate(/obj/gap_every/running, run_loc_floor_bottom_left)
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks >= 2, "running from creation (ran [E.ticks])")
	TEST_ASSERT(!length(E.rx?.every_parked), "never parked")

/// A proc gate cannot be trusted to announce every change, so the every() polls (never parks) and still follows the condition.
/datum/unit_test/dq_gap/every_with_a_proc_gate_polls
/datum/unit_test/dq_gap/every_with_a_proc_gate_polls/run_gap()
	var/obj/gap_every_proc/E = allocate(/obj/gap_every_proc, run_loc_floor_bottom_left)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(E.ticks, 0, "false: it did not run")
	TEST_ASSERT(!length(E.rx?.every_parked), "and it is polling, not parked")
	E.set_on(TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT(E.ticks >= 2, "true: it runs (ran [E.ticks])")

/// Converted periodic (a tracked var plus every()): a pinpointer steps (and shows what it found) only while active.
/datum/unit_test/dq_gap/periodic_pinpointer_steps_while_active
/datum/unit_test/dq_gap/periodic_pinpointer_steps_while_active/run_gap()
	var/obj/item/pinpointer/P = allocate(/obj/item/pinpointer, run_loc_floor_bottom_left)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(P.icon_state, "pinoff", "off: it never stepped")
	P.set_active(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(P.icon_state != "pinoff", "active: its step ran and set what it points at ([P.icon_state])")
	P.set_active(FALSE)
	P.icon_state = "pinoff"
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(P.icon_state, "pinoff", "off again: it stopped stepping")

/// Converted periodic: a radio jammer drains its cell on its 2 s step only while switched on.
/datum/unit_test/dq_gap/periodic_jammer_drains_while_on
/datum/unit_test/dq_gap/periodic_jammer_drains_while_on/run_gap()
	var/obj/item/radio_jammer/J = allocate(/obj/item/radio_jammer, run_loc_floor_bottom_left)
	var/start = J.power_source.charge
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(J.power_source.charge, start, "off: nothing drained")
	J.set_on(TRUE)
	test_time(6 SECONDS)
	TEST_ASSERT(J.power_source.charge < start, "on: the step drained the cell ([start] to [J.power_source.charge])")
	J.set_on(FALSE)
	var/seen = J.power_source.charge
	test_time(6 SECONDS)
	TEST_ASSERT_EQUAL(J.power_source.charge, seen, "off again: it stopped")

/// verb_entry(): always and inherited-then-hidden verbs are on at init, a `when` verb follows its tracked var, a login verb waits for a player.
/datum/unit_test/dq_gap/verb_entries_follow_their_conditions
/datum/unit_test/dq_gap/verb_entries_follow_their_conditions/run_gap()
	var/mob/gap_verb_mob/M = allocate(/mob/gap_verb_mob, run_loc_floor_bottom_left)
	TEST_ASSERT(/mob/gap_verb_mob/proc/gv_always in M.verbs, "an always entry is on at init")
	TEST_ASSERT(!(/mob/gap_verb_mob/proc/gv_when in M.verbs), "a when entry is off while its var is false")
	TEST_ASSERT(!(/mob/gap_verb_mob/verb/gv_inherited in M.verbs), "a hidden entry takes the type's own verb off")
	TEST_ASSERT(!(/mob/gap_verb_mob/proc/gv_login in M.verbs), "a login entry is off with no player")
	M.set_flag(TRUE)
	test_time(2)
	TEST_ASSERT(/mob/gap_verb_mob/proc/gv_when in M.verbs, "the var turning true put the verb on")
	M.set_flag(FALSE)
	test_time(2)
	TEST_ASSERT(!(/mob/gap_verb_mob/proc/gv_when in M.verbs), "and false took it off")
	M.key = "gap_verb_test_key"
	verb_store_login(M)
	TEST_ASSERT(/mob/gap_verb_mob/proc/gv_login in M.verbs, "a player has the mob: the login verb is on")
	M.key = null

/// grant(M, granted_verb(path), source): the verb is on while the source holds it and ends with revoke() or the source.
/datum/unit_test/dq_gap/granted_verb_follows_its_source
/datum/unit_test/dq_gap/granted_verb_follows_its_source/run_gap()
	var/mob/gap_verb_mob/M = allocate(/mob/gap_verb_mob, run_loc_floor_bottom_left)
	var/path = /mob/gap_verb_mob/proc/gv_runtime
	var/datum/other = new
	TEST_ASSERT(!(path in M.verbs), "no verb yet")
	grant(M, granted_verb(path), other)
	TEST_ASSERT(path in M.verbs, "granted")
	TEST_ASSERT(granted(M, granted_verb(path)), "granted() says so")
	TEST_ASSERT(revoke(M, granted_verb(path), other), "revoke finds it")
	TEST_ASSERT(!(path in M.verbs), "revoked")
	grant(M, granted_verb(path), other)
	qdel(other)
	TEST_ASSERT(!(path in M.verbs), "the source died: the verb went with it")
	var/datum/second = new
	grant(M, hidden_verb(/mob/gap_verb_mob/proc/gv_always), second)
	TEST_ASSERT(!(/mob/gap_verb_mob/proc/gv_always in M.verbs), "a hidden verb is off while its source holds the hide")
	revoke(M, hidden_verb(/mob/gap_verb_mob/proc/gv_always), second)
	TEST_ASSERT(/mob/gap_verb_mob/proc/gv_always in M.verbs, "and back when it lets go")
	qdel(second)

/// A verb_entry inside a capability is a grant: on while the capability is granted, gone when it ends.
/datum/unit_test/dq_gap/verb_entry_in_a_capability_is_a_grant
/datum/unit_test/dq_gap/verb_entry_in_a_capability_is_a_grant/run_gap()
	var/mob/gap_verb_mob/M = allocate(/mob/gap_verb_mob, run_loc_floor_bottom_left)
	var/path = /mob/gap_verb_mob/proc/gv_runtime
	var/datum/source = new
	grant(M, gap_verb_cap(), source)
	TEST_ASSERT(path in M.verbs, "the capability brought its verb")
	revoke(M, gap_verb_cap(), source)
	TEST_ASSERT(!(path in M.verbs), "and took it away")
	qdel(source)
