// Framework gap closures (doc/rewrite/codemod_rules.md): OP_DECLINE. Fixtures: code/tests/engine/gap_fixtures.dm.

/datum/unit_test/dq_gap
	abstract_type = /datum/unit_test/dq_gap

/datum/unit_test/dq_gap/Run()
	test_driver_begin()
	run_gap()
	test_driver_end()

/datum/unit_test/dq_gap/proc/run_gap()
	return

/// A conscious person with hands.
/datum/unit_test/dq_gap/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

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

/// A plain datum's type-level every() is armed by being made, parks on its tracked gate, and ends with the datum.
/datum/unit_test/dq_gap/every_runs_on_a_plain_datum
/datum/unit_test/dq_gap/every_runs_on_a_plain_datum/run_gap()
	var/datum/gap_every_datum/D = new
	test_time(5 SECONDS)
	TEST_ASSERT(D.ticks >= 4 && D.ticks <= 5, "the ungated every() ran from creation (ran [D.ticks])")
	TEST_ASSERT_EQUAL(D.gated_ticks, 0, "the gated one has not run")
	D.set_active(TRUE)
	test_time(3 SECONDS)
	TEST_ASSERT(D.gated_ticks >= 2, "gate true: the gated one runs (ran [D.gated_ticks])")
	D.set_active(FALSE)
	var/gated = D.gated_ticks
	test_time(3 SECONDS)
	TEST_ASSERT(D.gated_ticks <= gated + 1, "gate false: it stopped")
	var/ticks = D.ticks
	qdel(D)
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(D.ticks, ticks, "a deleted datum's every() no longer runs")

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

/// interface() carries the window's tgui state: a state global by name, ADMIN_STATE of a rights mask, or the default (none).
/datum/unit_test/dq_gap/interface_carries_its_state
/datum/unit_test/dq_gap/interface_carries_its_state/run_gap()
	var/obj/gap_window_base/state/by_name = allocate(/obj/gap_window_base/state, run_loc_floor_bottom_left)
	var/obj/gap_window_base/rights/by_rights = allocate(/obj/gap_window_base/rights, run_loc_floor_bottom_left)
	var/obj/gap_window_base/plain/plain = allocate(/obj/gap_window_base/plain, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(interface_state(by_name), GLOB.tgui_always_state, "a state named by its global")
	TEST_ASSERT_EQUAL(interface_state(by_rights), ADMIN_STATE(R_ADMIN | R_EVENT), "rights with no state is the admin state of those rights")
	TEST_ASSERT_NULL(interface_state(plain), "neither: the default")
	plain.tgui_window_state = GLOB.tgui_physical_state
	TEST_ASSERT_NULL(interface_state(plain), "the host's own tgui_window_state is read by ui_open() after it, not shadowed")

/// A converted appearance proc (draw(look) over a TRACKED var): the setter alone redraws; no update_icon() follows the write.
/datum/unit_test/dq_gap/converted_draw_follows_its_tracked_var
/datum/unit_test/dq_gap/converted_draw_follows_its_tracked_var/run_gap()
	var/obj/item/multitool/ai_detector/D = allocate(/obj/item/multitool/ai_detector, run_loc_floor_bottom_left)
	var/base = initial(D.icon_state)
	D.update_icon()
	TEST_ASSERT_EQUAL(D.icon_state, "[base]", "no detection: the base state")
	D.set_detect_state("_red")
	test_time(2)
	TEST_ASSERT_EQUAL(D.icon_state, "[base]_red", "the tracked var changed: the draw showed it with no update_icon() call")
	D.set_detect_state("")
	test_time(2)
	TEST_ASSERT_EQUAL(D.icon_state, "[base]", "and back")

/// drag(): an item(T) op pinned to GESTURE_DRAG answers a mob dragged onto its holder, the dragged mob is A.held, and OP_DECLINE leaves the drag to the next taker.
/datum/unit_test/dq_gap/input_drag_puts_the_dragged_mob_in_held
/datum/unit_test/dq_gap/input_drag_puts_the_dragged_mob_in_held/run_gap()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/victim = person()
	var/obj/gap_inputs/target = allocate(/obj/gap_inputs, run_loc_floor_bottom_left)
	var/datum/op_result/R = test_drag(H, victim, target)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "the drag committed")
	TEST_ASSERT_EQUAL(target.ran_text(), "drag", "only the drag op ran (the hand ops are not a drag's)")
	TEST_ASSERT_EQUAL(target.dragged_what, victim, "the dragged mob was A.held")
	target.forget_ran()
	target.powered = FALSE
	R = test_drag(H, victim, target)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_DECLINED, "an op that declines is not handled")
	TEST_ASSERT(!length(target.ran), "and ran nothing")

/// alt_click: a hand() op pinned to GESTURE_ALT answers an alt-click, and a plain click does not reach it.
/datum/unit_test/dq_gap/input_alt_is_a_pinned_hand_op
/datum/unit_test/dq_gap/input_alt_is_a_pinned_hand_op/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_inputs/target = allocate(/obj/gap_inputs, run_loc_floor_bottom_left)
	var/datum/op_result/R = test_click(H, target, null, GESTURE_ALT)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "the alt-click committed")
	TEST_ASSERT_EQUAL(target.ran_text(), "alt", "the alt op ran")
	target.forget_ran()
	test_click(H, target, null, GESTURE_CLICK)
	TEST_ASSERT_EQUAL(target.ran_text(), "pet", "a plain click is the hand's Use, not the alt-click")
	// an unconscious actor is refused by the actor half of the hand gate, ungated() or not
	target.forget_ran()
	H.set_stat(UNCONSCIOUS)
	test_click(H, target, null, GESTURE_ALT)
	TEST_ASSERT(!length(target.ran), "an unconscious actor alt-clicks nothing")

/// A stance variant is the same op with stance(): the actor's stance picks the one that answers, and two ops of disjoint stances are no clash.
/datum/unit_test/dq_gap/input_stance_picks_the_variant
/datum/unit_test/dq_gap/input_stance_picks_the_variant/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_inputs/target = allocate(/obj/gap_inputs, run_loc_floor_bottom_left)
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "pet", "peaceful: the stance(I_HELP) op")
	target.forget_ran()
	H.set_combat_mode(TRUE)
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "bite", "hostile: the stance(I_HURT) op")

/// tk(): a telekinetic actor does a tk() op on what its hands do not reach, and only then; a hand op is reached at range through the same provider.
/datum/unit_test/dq_gap/input_tk_is_a_provider_for_what_no_hand_reaches
/datum/unit_test/dq_gap/input_tk_is_a_provider_for_what_no_hand_reaches/run_gap()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/away = locate(home.x + 3, home.y, home.z)
	TEST_ASSERT_NOTNULL(away, "a turf three tiles away")
	var/mob/living/carbon/human/H = person(home)
	var/obj/gap_inputs/far = allocate(/obj/gap_inputs, away)
	var/obj/gap_touch/far_both = allocate(/obj/gap_touch, away)
	test_click(H, far, null)
	TEST_ASSERT(!length(far.ran), "without telekinesis nothing reaches three tiles")
	H.add_mutation(TK)
	TEST_ASSERT(H.tk_ready(), "the mutation makes the actor tk_ready()")
	var/datum/op_result/R = test_click(H, far, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "with it the click committed")
	TEST_ASSERT_EQUAL(far.ran_text(), "tk", "the tk op went first, ahead of the hand ops the same provider reaches")
	test_click(H, far_both, null)
	TEST_ASSERT_EQUAL(far_both.ran_text(), "touch", "with no tk op, the hand op is done through the telekinesis provider")
	// next to the actor the hand's op answers and the tk op is not offered
	var/obj/gap_inputs/near = allocate(/obj/gap_inputs, home)
	test_click(H, near, null)
	TEST_ASSERT_EQUAL(near.ran_text(), "pet", "adjacent: the hand's op, not the tk one")
	H.remove_mutation(TK)
	far.forget_ran()
	test_click(H, far, null)
	TEST_ASSERT(!length(far.ran), "without the mutation it is out of reach again")
	// an unconscious telekinetic actor does nothing: the actor half of the hand gate holds for tk()
	H.add_mutation(TK)
	far.forget_ran()
	H.set_stat(UNCONSCIOUS)
	test_click(H, far, null)
	TEST_ASSERT(!length(far.ran), "an unconscious actor reaches with nothing")

/// observer(): a ghost's click reaches the observer() op from anywhere and never a hand op; a living actor never reaches the observer() op.
/datum/unit_test/dq_gap/input_observe_is_the_ghosts_only
/datum/unit_test/dq_gap/input_observe_is_the_ghosts_only/run_gap()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/away = locate(home.x + 4, home.y, home.z)
	TEST_ASSERT_NOTNULL(away, "a turf four tiles away")
	var/mob/living/carbon/human/H = person(home)
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, away)
	var/obj/gap_observe/target = allocate(/obj/gap_observe, home)
	var/datum/op_result/R = test_click(ghost, target, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "the ghost's click committed")
	TEST_ASSERT_EQUAL(target.ran_text(), "haunt", "from four tiles away, the observer() op and not the hand op")
	target.ran = null
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "touch", "a living actor's click is the hand op")
	target.ran = null
	R = test_menu(H, target, "haunt")
	TEST_ASSERT(!test_op_committed(R), "a living actor cannot pick the observer() op from the menu")
	TEST_ASSERT(!length(target.ran), "and nothing ran")
	var/obj/gap_touch/plain = allocate(/obj/gap_touch, away)
	test_click(ghost, plain, null)
	TEST_ASSERT(!length(plain.ran), "a ghost next to a hand-only target touches nothing")

/// req_mutation(): the actor's mutation picks the op; it comes and goes with add_mutation()/remove_mutation().
/datum/unit_test/dq_gap/req_mutation_reads_the_actor
/datum/unit_test/dq_gap/req_mutation_reads_the_actor/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_hulk/target = allocate(/obj/gap_hulk, run_loc_floor_bottom_left)
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "touch", "without the mutation, the plain touch")
	target.ran = null
	H.add_mutation(HULK)
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "smash", "a hulk smashes")
	target.ran = null
	H.remove_mutation(HULK)
	test_click(H, target, null)
	TEST_ASSERT_EQUAL(target.ran_text(), "touch", "and not once the mutation is gone")

/// OP_PASS: handled, the input not used up: the op commits and the next candidate answers too; a handler that does not pass ends the click.
/datum/unit_test/dq_gap/op_pass_hands_the_click_on
/datum/unit_test/dq_gap/op_pass_hands_the_click_on/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_pass/target = allocate(/obj/gap_pass, run_loc_floor_bottom_left)
	var/obj/item/pen/thing = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	H.put_in_active_hand(thing)
	var/datum/op_result/R = test_click(H, target, thing)
	TEST_ASSERT_EQUAL(target.first, 1, "the first op ran")
	TEST_ASSERT_EQUAL(target.second, 1, "and, having passed, so did the second")
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "the chain's last result committed")
	target.passes_it = FALSE
	test_click(H, target, thing)
	TEST_ASSERT_EQUAL(target.first, 2, "the first op ran again")
	TEST_ASSERT_EQUAL(target.second, 1, "not passing, it took the click and the second did not run")

/// ui_act("*") answers every window action no op names (an embedded controller's program commands); the named button wins, and the op's own requirement
/// says which of the rest it takes. A.window_action() is the action that reached it.
/datum/unit_test/dq_gap/ui_fallback_answers_the_actions_nothing_names
/datum/unit_test/dq_gap/ui_fallback_answers_the_actions_nothing_names/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_window/W = allocate(/obj/gap_window, run_loc_floor_bottom_left)
	test_ui(H, W, "named")
	test_ui(H, W, "alpha")
	test_ui(H, W, "gamma")
	TEST_ASSERT_EQUAL(W.log_text(), "named,program:alpha", "the named button ran, the fallback took the listed action and left the unlisted one alone")

/// A window action the holder has no op for goes to the unit its interface forwards to (the sleeper console); a subtype's own handler overrides the type's.
/datum/unit_test/dq_gap/ui_forward_and_override_route_the_button
/datum/unit_test/dq_gap/ui_forward_and_override_route_the_button/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_window/W = allocate(/obj/gap_window, run_loc_floor_bottom_left)
	var/obj/gap_window/locked/L = allocate(/obj/gap_window/locked, run_loc_floor_bottom_left)
	var/obj/gap_console/C = allocate(/obj/gap_console, run_loc_floor_bottom_left)
	rel_set(C, nameof(C.unit), W)
	test_ui(H, C, "named")
	TEST_ASSERT_EQUAL(W.log_text(), "named", "the console's button was the unit's op")
	test_ui(H, C, "alpha")
	TEST_ASSERT_EQUAL(W.log_text(), "named,program:alpha", "and so was its fallback")
	test_ui(H, C, "nothing_names_this")
	TEST_ASSERT_EQUAL(W.log_text(), "named,program:alpha", "an action neither knows does nothing")
	test_ui(H, L, "named")
	TEST_ASSERT_EQUAL(L.log_text(), "locked", "the subtype's own handler answered the type's op")

/// A modal is a question shown in the window: modal_open runs the op named "modal:<id>", the question is the window's data["modal"], the window's modal_answer
/// answers it and modal_close cancels it; a yes/no carries its own labels.
/datum/unit_test/dq_gap/modal_is_a_question_in_the_window
/datum/unit_test/dq_gap/modal_is_a_question_in_the_window/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_window/W = allocate(/obj/gap_window, run_loc_floor_bottom_left)
	test_ui(H, W, OP_UI_MODAL_OPEN, list("id" = "note", "arguments" = list("x" = 1)))
	var/list/modal = tgui_modal_data(W)
	TEST_ASSERT_NOTNULL(modal, "the question is the window's modal")
	TEST_ASSERT_EQUAL(modal["id"], "note", "under the id the client opened")
	TEST_ASSERT_EQUAL(modal["type"], "input", "a text question is an input modal")
	TEST_ASSERT_EQUAL(modal["text"], "Note?", "asking its question")
	TEST_ASSERT_EQUAL(modal["value"], "none", "with its default")
	TEST_ASSERT_EQUAL(modal["args"]["x"], 1, "and the arguments the client passed")
	var/list/window_data = list()
	present_tgui_data(W, H, window_data)
	TEST_ASSERT_NOTNULL(window_data["modal"], "present_tgui_data() puts it in the window's data")
	W.act_modal_answer(H, "note", "hello", null)
	TEST_ASSERT_EQUAL(W.log_text(), "note:hello", "the answer ran the op")
	TEST_ASSERT_NULL(tgui_modal_data(W), "and the modal is gone")
	test_ui(H, W, OP_UI_MODAL_OPEN, list("id" = "note"))
	W.act_modal_close(H, "note")
	TEST_ASSERT_EQUAL(W.log_text(), "note:hello", "closed without an answer, nothing ran")
	TEST_ASSERT_NULL(tgui_modal_data(W), "and the modal is gone")
	test_ui(H, W, OP_UI_MODAL_OPEN, list("id" = "style"))
	modal = tgui_modal_data(W)
	TEST_ASSERT_EQUAL(modal["type"], "bentospritesheet", "a bento choice is a bento modal")
	TEST_ASSERT_EQUAL(length(modal["choices"]), 3, "with its choices")
	W.act_modal_answer(H, "style", "9", null)
	TEST_ASSERT_EQUAL(W.log_text(), "note:hello", "an index outside the choices answers nothing")
	TEST_ASSERT_NOTNULL(tgui_modal_data(W), "and the question stays")
	W.act_modal_answer(H, "style", "2", null)
	TEST_ASSERT_EQUAL(W.log_text(), "note:hello,style:b", "the index is the choice at it")
	test_ui(H, W, OP_UI_MODAL_OPEN, list("id" = "confirm"))
	modal = tgui_modal_data(W)
	TEST_ASSERT_EQUAL(modal["type"], "boolean", "a yes/no is a boolean modal")
	TEST_ASSERT_EQUAL(modal["yes_text"], "Do it", "with its own yes label")
	TEST_ASSERT_EQUAL(modal["no_text"], "Leave it", "and its own no label")
	W.act_modal_answer(H, "confirm", "1", null)
	TEST_ASSERT_EQUAL(W.log_text(), "note:hello,style:b,confirmed:1", "yes was answered")

/// The yes/no kind answers by its own labels: the button with the yes label is a yes.
/datum/unit_test/dq_gap/yes_no_carries_its_labels
/datum/unit_test/dq_gap/yes_no_carries_its_labels/run_gap()
	var/datum/prompt/yes_no/gap_labelled/labelled = new
	TEST_ASSERT(labelled.answer_of_button("Launch"), "the yes label is a yes")
	TEST_ASSERT(!labelled.answer_of_button("Cancel"), "the no label is a no")
	TEST_ASSERT(!labelled.answer_of_button("Yes"), "the default label is not the button any more")
	var/datum/prompt/yes_no/plain = new
	TEST_ASSERT(plain.answer_of_button("Yes"), "a prompt with no labels keeps Yes")
	TEST_ASSERT(!plain.answer_of_button("No"), "and No")
	qdel(labelled)
	qdel(plain)

/// A question of an op is asked again until the answer is one the kind takes: a choice that is not on the list leaves the op waiting, no handler loop.
/datum/unit_test/dq_gap/ask_a_refused_answer_asks_again
/datum/unit_test/dq_gap/ask_a_refused_answer_asks_again/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_asker/asker = allocate(/obj/gap_asker, run_loc_floor_bottom_left)
	H.put_in_active_hand(asker)
	var/datum/op_result/R = test_click(H, asker, asker)
	TEST_ASSERT_NULL(R?.outcome, "the op waits for the answer")
	test_answer(H, "green")
	TEST_ASSERT_NULL(R.outcome, "an answer that is not one of the choices leaves the question open")
	test_answer(H, "blue")
	TEST_ASSERT_EQUAL(R.outcome, ACT_COMMITTED, "a choice answers it and the effect runs once")
	TEST_ASSERT_EQUAL(asker.log_text(), "picked:blue", "with the answer of the step")

/// The fields of a step: a literal as written, a var of the holder as nameof(var) (what the player saw when it was asked), anything else computed.
/datum/unit_test/dq_gap/ask_fields_are_literal_var_or_computed
/datum/unit_test/dq_gap/ask_fields_are_literal_var_or_computed/run_gap()
	var/mob/living/carbon/human/H = person()
	var/obj/gap_asker/asker = allocate(/obj/gap_asker, run_loc_floor_bottom_left)
	test_menu(H, asker, "name")
	var/datum/prompt/text/P = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(P, "the question is open")
	TEST_ASSERT_EQUAL(P.question, "Name?", "a literal field")
	TEST_ASSERT_EQUAL(P.default, "Bae", "a var of the holder")
	TEST_ASSERT_EQUAL(P.title, "Name [asker]", "a computed field")
	TEST_ASSERT(P.name_text, "name_text as declared")
	test_answer(H, "Rex")
	TEST_ASSERT_EQUAL(asker.log_text(), "named:Rex", "the answer reaches the effect")

/// req_actor_kind(): picks and refuses by the kind of the actor; not = TRUE inverts it.
/datum/unit_test/dq_gap/req_actor_kind_gates_on_the_actor
/datum/unit_test/dq_gap/req_actor_kind_gates_on_the_actor/run_gap()
	var/mob/living/carbon/human/H = person()
	var/mob/living/simple_mob/animal/passive/mouse/rat = allocate(/mob/living/simple_mob/animal/passive/mouse, run_loc_floor_bottom_left)
	var/obj/gap_actor_kind/target = allocate(/obj/gap_actor_kind, run_loc_floor_bottom_left)
	TEST_ASSERT(test_op_committed(test_menu(H, target, "humans_only")), "a human passes the human gate")
	var/datum/op_result/R = test_menu(H, target, "not_humans")
	TEST_ASSERT(!test_op_committed(R), "a human is refused by the inverted gate")
	TEST_ASSERT_EQUAL(reason_text(R?.reason), "You can't do that right now.", "with the reason the declaration gave")
	R = test_menu(rat, target, "humans_only")
	TEST_ASSERT(!test_op_committed(R), "a mouse is refused the human gate")
	TEST_ASSERT_EQUAL(reason_text(R?.reason), "That isn't something you can do.", "with the default reason")
	TEST_ASSERT(test_op_committed(test_menu(rat, target, "not_humans")), "and passes the inverted one")
	TEST_ASSERT_EQUAL(target.ran_text(), "humans_only,not_humans", "only the two committed ops ran")

/// interface(observe = TRUE): a ghost's click opens the window read-only (the ui_observe op), a living actor never reaches it,
/// and the window's own requirements (extend) apply to it.
/datum/unit_test/dq_gap/interface_observe_is_the_ghosts_view
/datum/unit_test/dq_gap/interface_observe_is_the_ghosts_view/run_gap()
	var/mob/living/carbon/human/H = person()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/obj/gap_observed_window/target = allocate(/obj/gap_observed_window, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(op_plan_for(target, "ui_observe", list()), "interface(observe = TRUE) declares the ui_observe op")
	var/datum/op_result/R = test_click(ghost, target, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "the ghost's click opens the view (refused: [reason_text(R?.reason)])")
	R = test_menu(H, target, "ui_observe")
	TEST_ASSERT(!test_op_committed(R), "a living actor cannot pick the ghost's view")
	target.blocked = TRUE
	R = test_click(ghost, target, null)
	TEST_ASSERT_NOTEQUAL(R?.outcome, ACT_COMMITTED, "the window's requirement (extend on ui_observe) stops the view too")

/// A window's ui_data(A) sees A.observer: TRUE for a ghost's read-only view, FALSE for a living viewer; a ghost without a window is an observer view.
/datum/unit_test/dq_gap/ui_data_sees_the_observer_flag
/datum/unit_test/dq_gap/ui_data_sees_the_observer_flag/run_gap()
	var/mob/living/carbon/human/H = person()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/obj/gap_observed_window/target = allocate(/obj/gap_observed_window, run_loc_floor_bottom_left)
	TEST_ASSERT(tgui_is_observer_view(ghost, null), "a ghost's window is the read-only view")
	TEST_ASSERT(!tgui_is_observer_view(H, null), "a living viewer's is not")
	var/list/seen = list()
	present_tgui_data(target, ghost, seen, tgui_is_observer_view(ghost, null))
	TEST_ASSERT(seen["saw_observer"], "ui_data reads A.observer = TRUE for the ghost")
	var/list/living = list()
	present_tgui_data(target, H, living, tgui_is_observer_view(H, null))
	TEST_ASSERT(!living["saw_observer"], "and FALSE for a living viewer")

/// The chemical dispenser and synthesizer give a ghost the read-only view; a broken dispenser shows nothing.
/datum/unit_test/dq_gap/reagent_machines_show_the_ghost_view
/datum/unit_test/dq_gap/reagent_machines_show_the_ghost_view/run_gap()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/obj/machinery/chemical_dispenser/disp = allocate(/obj/machinery/chemical_dispenser, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(op_plan_for(disp, "ui_observe", list()), "the dispenser declares the ghost's view")
	TEST_ASSERT_EQUAL(test_click(ghost, disp, null)?.outcome, ACT_COMMITTED, "the ghost's click on a working dispenser opens the view")
	disp.atom_break()
	TEST_ASSERT_NOTEQUAL(test_click(ghost, disp, null)?.outcome, ACT_COMMITTED, "a broken dispenser shows the ghost nothing")
	var/obj/machinery/chemical_synthesizer/synth = allocate(/obj/machinery/chemical_synthesizer, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(op_plan_for(synth, "ui_observe", list()), "the synthesizer declares the ghost's view")
	for(var/obj/item/paper/leftover in run_loc_floor_bottom_left) // the machines print their instructions
		qdel(leftover)

/// The hydroponics tray's ghost harvest: an observer() op, offered to a ghost only for a ripe tray whose plant is a creature.
/datum/unit_test/dq_gap/hydroponics_tray_has_the_ghost_harvest
/datum/unit_test/dq_gap/hydroponics_tray_has_the_ghost_harvest/run_gap()
	var/obj/machinery/portable_atmospherics/hydroponics/tray = allocate(/obj/machinery/portable_atmospherics/hydroponics, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(op_plan_for(tray, "ghost_harvest", list()), "the tray declares the ghost harvest as an op")
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/datum/op_result/R = test_menu(ghost, tray, "ghost_harvest")
	TEST_ASSERT(!test_op_committed(R), "an empty tray offers a ghost nothing to harvest")

/// owns_one(on_destroy = ON_DESTROY_HAND_OVER, to =, to_var =): the part goes to the successor with its holder; with no successor it is deleted.
/// only_if: a conditional policy (spill while the flag is set, else deleted).
/datum/unit_test/dq_gap/owns_hands_over_to_a_successor
/datum/unit_test/dq_gap/owns_hands_over_to_a_successor/run_gap()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/gap_handover_successor/heir = allocate(/obj/gap_handover_successor, T)
	var/obj/gap_handover_holder/with_heir = new(T)
	var/obj/item/pen/p1 = new(with_heir)
	var/obj/item/pen/k1 = new(with_heir)
	rel_set(with_heir, nameof(with_heir.part), p1)
	rel_set(with_heir, nameof(with_heir.kept), k1)
	with_heir.heir = heir
	with_heir.going_out = TRUE
	qdel(with_heir)
	TEST_ASSERT(!QDELETED(p1), "the handed-over part survives its holder")
	TEST_ASSERT_EQUAL(p1.loc, heir, "it moved into the successor")
	TEST_ASSERT(p1 in heir.salvage, "and the successor holds it under the declared var")
	TEST_ASSERT(!QDELETED(k1), "with the flag set the other part is spilled, not deleted")
	TEST_ASSERT_EQUAL(k1.loc, T, "onto the holder's turf")
	qdel(p1)
	qdel(k1)
	var/obj/gap_handover_holder/alone = new(T)
	var/obj/item/pen/p2 = new(alone)
	var/obj/item/pen/k2 = new(alone)
	rel_set(alone, nameof(alone.part), p2)
	rel_set(alone, nameof(alone.kept), k2)
	qdel(alone)
	TEST_ASSERT(QDELETED(p2), "with no successor the part is deleted with its holder")
	TEST_ASSERT(QDELETED(k2), "with the flag clear the other part is deleted")

/// A mech destroyed in play hands its cell to the wreckage as salvage; a plain qdel leaves no wreckage and deletes it.
/datum/unit_test/dq_gap/mecha_wreck_takes_the_cell
/datum/unit_test/dq_gap/mecha_wreck_takes_the_cell/run_gap()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/wrecked = new(T)
	var/obj/item/cell/cell = wrecked.cell
	TEST_ASSERT_NOTNULL(cell, "a ripley starts with a cell")
	wrecked.wrecked = TRUE
	qdel(wrecked)
	var/obj/effect/decal/mecha_wreckage/WR = locate(/obj/effect/decal/mecha_wreckage) in T
	TEST_ASSERT_NOTNULL(WR, "a mech destroyed in play leaves wreckage")
	var/list/salvage = WR?.crowbar_salvage?.Copy()
	TEST_ASSERT(!QDELETED(cell), "its cell survives")
	TEST_ASSERT(cell in WR.crowbar_salvage, "as the wreckage's salvage")
	TEST_ASSERT_EQUAL(cell.loc, WR, "inside the wreckage")
	for(var/datum/part as anything in salvage)
		qdel(part)
	qdel(WR)
	var/obj/mecha/working/ripley/plain = new(T)
	var/obj/item/cell/cell2 = plain.cell
	qdel(plain)
	TEST_ASSERT(QDELETED(cell2), "a plain qdel deletes the cell")
	TEST_ASSERT_NULL(locate(/obj/effect/decal/mecha_wreckage) in T, "and leaves no wreckage")

/// A borg destroyed with a mind and a place gives its MMI to the turf (the declared conditional policy: mmi_ejects); a mindless borg's goes with it.
/datum/unit_test/dq_gap/robot_mmi_leaves_with_a_minded_borg
/datum/unit_test/dq_gap/robot_mmi_leaves_with_a_minded_borg/run_gap()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/silicon/robot/minded = new(T)
	var/obj/item/mmi/kept = new(minded)
	rel_set(minded, nameof(minded.mmi), kept)
	var/datum/mind/who = own(new /datum/mind("robot_mmi_test"))
	minded.mind = who
	qdel(minded)
	TEST_ASSERT(!QDELETED(kept), "the MMI of a destroyed borg that had a mind survives")
	TEST_ASSERT_EQUAL(kept.loc, T, "on the borg's turf")
	qdel(kept)
	var/mob/living/silicon/robot/mindless = new(T)
	var/obj/item/mmi/lost = new(mindless)
	rel_set(mindless, nameof(mindless.mmi), lost)
	qdel(mindless)
	TEST_ASSERT(QDELETED(lost), "a mindless borg's MMI goes with it")

/// Converted datum periodics (J1): a turbolift parks while it has no busy state, steps once a second while it has one, and parks again.
/datum/unit_test/dq_gap/datum_periodic_turbolift_steps_while_busy
/datum/unit_test/dq_gap/datum_periodic_turbolift_steps_while_busy/run_gap()
	var/datum/turbolift/lift = new
	test_time(3 SECONDS)
	TEST_ASSERT(length(lift.rx?.every_parked), "idle lift: its step is parked, holding no timer")
	lift.set_busy_state(LIFT_WAITING_B)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(lift.busy_state, "its step ran and settled the state (nothing was queued)")
	TEST_ASSERT(length(lift.rx?.every_parked), "settled: parked again")
	qdel(lift)

/// Converted datum periodic: a changeling's camouflage drain runs on its 4 s step while camo_draining is set and ends it when the owner cannot hold it.
/datum/unit_test/dq_gap/datum_periodic_changeling_drain_follows_its_flag
/datum/unit_test/dq_gap/datum_periodic_changeling_drain_follows_its_flag/run_gap()
	var/datum/changeling/ling = new
	test_time(5 SECONDS)
	TEST_ASSERT(length(ling.rx?.every_parked), "not draining: both drains are parked")
	ling.set_camo_draining(TRUE)
	test_time(5 SECONDS)
	TEST_ASSERT(!ling.camo_draining, "the drain ran and found no human owner, so it ended the camouflage")
	qdel(ling)
