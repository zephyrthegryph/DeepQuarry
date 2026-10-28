// req_answer() and asks(optional = TRUE, default =) (code/engine/parts/answers.dm, code/engine/parts/run.dm), and the sites converted onto them: an op that asks
// refuses on what it was told through a requirement, never a message and a return in its effect; a cancelled optional step takes its declared default.

MSG_DEF_SELF(ar/too_many, "That is too many.")

/// A machine whose ops ask for a count (refused above `limit`) or a pick (optional, with a default).
/obj/ar_machine
	name = "ar machine"
	anchored = TRUE
	var/limit = 5
	var/ran = 0
	var/counted_value
	var/picked_value
	var/asked_value

CAPABILITIES(/obj/ar_machine)
	op("ask_carrier", ui_act("ask_carrier"), asks(/datum/prompt/yes_no, fields = list("question" = "Allow?", "timeout" = 0), step = "ok", answerer = PROC_REF(carrier_of)), then(PROC_REF(asked)))
	op("check", ui_act("check"), asks(/datum/prompt/number, fields = list("question" = "How many?", "timeout" = 0), step = "n"), needs(req_answer(PROC_REF(n_refusal), step = "n")), then(PROC_REF(counted)))
	op("late", ui_act("late"), asks(/datum/prompt/number, fields = list("question" = "How many?", "timeout" = 0), step = "n"), asks(/datum/prompt/text, fields = list("question" = "Note?", "timeout" = 0), step = "note"), needs(req_answer(PROC_REF(n_refusal), step = "n")), then(PROC_REF(counted)))
	op("pick", ui_act("pick"), asks(/datum/prompt/choice, fields = list("choices" = list("a", "b"), "timeout" = 0), step = "pick", optional = TRUE, default = "fallback"), then(PROC_REF(picked)))
	op("pick_computed", ui_act("pick_computed"), asks(/datum/prompt/choice, fields = list("choices" = list("a", "b"), "timeout" = 0), step = "pick", optional = TRUE, default = computed(PROC_REF(computed_pick))), then(PROC_REF(picked)))
	op("pick_required", ui_act("pick_required"), asks(/datum/prompt/choice, fields = list("choices" = list("a", "b"), "timeout" = 0), step = "pick"), then(PROC_REF(picked)))

/obj/ar_machine/proc/n_refusal(datum/act/op/A)
	var/n = A.step_value("n")
	return (isnum(n) && n > limit) ? MSG(ar/too_many) : null

/// The mob that carries the actor: the actor's container sits in its hands.
/obj/ar_machine/proc/carrier_of(datum/act/op/A)
	var/atom/where = A.actor?.loc
	while(where && !ismob(where))
		where = where.loc
	return where

/obj/ar_machine/proc/asked(datum/act/op/A)
	ran++
	asked_value = A.step_value("ok")
	return OP_OK

/obj/ar_machine/proc/computed_pick(datum/act/op/A)
	return "computed"

/obj/ar_machine/proc/counted(datum/act/op/A)
	ran++
	counted_value = A.step_value("n")
	return OP_OK

/obj/ar_machine/proc/picked(datum/act/op/A)
	ran++
	picked_value = A.step_value("pick")
	return OP_OK

/datum/unit_test/dq_ar
	abstract_type = /datum/unit_test/dq_ar

/datum/unit_test/dq_ar/Run()
	test_driver_begin()
	test_prompts_reset()
	run_ar()
	GLOB.test_prompts = null
	test_driver_end()

/datum/unit_test/dq_ar/proc/run_ar()
	return

/datum/unit_test/dq_ar/proc/actor()
	return allocate(/mob/living/simple_mob/e0_fixture)

/// `held` in the active hand of `user`, and a click on `target` with it.
/datum/unit_test/dq_ar/proc/click_with(mob/living/user, atom/target, obj/item/held)
	if(user.get_active_hand() != held)
		if(user.get_active_hand())
			user.drop_item()
		user.put_in_active_hand(held)
	cooldown_set_end(user, next_click, 0)
	return test_click(user, target, held)

/datum/unit_test/dq_ar/answer_requirement_refuses_with_a_reason

/datum/unit_test/dq_ar/answer_requirement_refuses_with_a_reason/run_ar()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/ar_machine/C = allocate(/obj/ar_machine)
	var/datum/op_result/waiting = test_ui(M, C, "check", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the requirement holds while the question is unanswered: the op waits on it")
	var/datum/op_result/done = test_answer(M, 9)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_REFUSED, "an answer the requirement refuses ends the op")
	TEST_ASSERT_EQUAL(done?.reason, /datum/msg/ar/too_many, "with the reason the requirement returned")
	TEST_ASSERT_EQUAL(C.ran, 0, "and the effect never ran")
	test_ui(M, C, "check", list())
	var/datum/op_result/fine = test_answer(M, 3)
	TEST_ASSERT_EQUAL(fine?.outcome, ACT_COMMITTED, "an answer it allows commits")
	TEST_ASSERT_EQUAL(C.counted_value, 3, "and the effect read the answer")

/datum/unit_test/dq_ar/answer_requirement_is_asked_again_at_commit

/datum/unit_test/dq_ar/answer_requirement_is_asked_again_at_commit/run_ar()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/ar_machine/C = allocate(/obj/ar_machine)
	test_ui(M, C, "late", list())
	var/datum/op_result/waiting = test_answer(M, 3)
	TEST_ASSERT_NULL(waiting?.outcome, "an answer the requirement allows leaves the op waiting on its next question")
	C.set_limit(2) // the world changed while the second question was open
	var/datum/op_result/done = test_answer(M, "a note")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_REFUSED, "the requirement judges the earlier answer again before the effect")
	TEST_ASSERT_EQUAL(done?.reason, /datum/msg/ar/too_many, "with its reason")
	TEST_ASSERT_EQUAL(C.ran, 0, "and the effect did not run")

/datum/unit_test/dq_ar/optional_pick_takes_its_default_on_cancel

/datum/unit_test/dq_ar/optional_pick_takes_its_default_on_cancel/run_ar()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/ar_machine/C = allocate(/obj/ar_machine)
	test_ui(M, C, "pick", list())
	var/datum/op_result/done = test_answer(M, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "a cancelled optional step does not end the op")
	TEST_ASSERT_EQUAL(C.picked_value, "fallback", "the effect read the declared default")
	test_ui(M, C, "pick", list())
	test_answer(M, "b")
	TEST_ASSERT_EQUAL(C.picked_value, "b", "a real answer still wins over the default")
	test_ui(M, C, "pick_computed", list())
	var/datum/op_result/late = test_answer(M, null, REQ_TIMED_OUT)
	TEST_ASSERT_EQUAL(late?.outcome, ACT_COMMITTED, "a timeout takes the default too")
	TEST_ASSERT_EQUAL(C.picked_value, "computed", "a computed default is read when the step ends")
	test_ui(M, C, "pick_required", list())
	var/datum/op_result/ended = test_answer(M, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(ended?.outcome, ACT_REFUSED, "a step that is not optional still ends the op")

// ---------------------------------------------------------------- converted sites

/datum/unit_test/dq_ar/camera_board_refuses_a_network_answer_that_names_none

/datum/unit_test/dq_ar/camera_board_refuses_a_network_answer_that_names_none/run_ar()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/circuitboard/security/board = allocate(/obj/item/circuitboard/security, T)
	var/obj/item/multitool/tool = allocate(/obj/item/multitool, T)
	board.set_locked(FALSE)
	var/list/before = board.network?.Copy()
	click_with(user, board, tool)
	var/datum/op_result/blank = test_answer(user, "")
	TEST_ASSERT_EQUAL(blank?.outcome, ACT_REFUSED, "a blank answer is refused")
	TEST_ASSERT_EQUAL(blank?.reason, /datum/msg/camera_board/no_input, "with the no-input line")
	TEST_ASSERT_EQUAL(json_encode(board.network), json_encode(before), "and the networks are unchanged")
	click_with(user, board, tool)
	var/datum/op_result/good = test_answer(user, "Test Net")
	TEST_ASSERT_EQUAL(good?.outcome, ACT_COMMITTED, "a network answer commits")
	TEST_ASSERT_EQUAL(json_encode(board.network), json_encode(list("Test Net")), "and sets the networks")

/datum/unit_test/dq_ar/stack_split_refuses_a_count_that_takes_the_whole_stack

/datum/unit_test/dq_ar/stack_split_refuses_a_count_that_takes_the_whole_stack/run_ar()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/lib_fixture/sheets/S = allocate(/obj/item/lib_fixture/sheets, T) // the stackable() capability (a real stack splits through its own hand op)
	S.amount = 10
	cooldown_set_end(user, next_click, 0)
	test_menu(user, S, "stackable.split")
	var/datum/op_result/whole = test_answer(user, 10)
	TEST_ASSERT_EQUAL(whole?.outcome, ACT_REFUSED, "a split of the whole stack is refused")
	TEST_ASSERT_EQUAL(whole?.reason, /datum/msg/stackable/bad_split, "with the bad-split line")
	TEST_ASSERT_EQUAL(S.amount, 10, "and nothing moved")
	test_menu(user, S, "stackable.split")
	var/datum/op_result/part = test_answer(user, 4)
	TEST_ASSERT_EQUAL(part?.outcome, ACT_COMMITTED, "a smaller count splits")
	TEST_ASSERT_EQUAL(S.amount, 6, "the stack keeps the rest")

/datum/unit_test/dq_ar/pill_bottle_label_over_fifty_letters_is_refused

/datum/unit_test/dq_ar/pill_bottle_label_over_fifty_letters_is_refused/run_ar()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/pill_bottle/bottle = allocate(/obj/item/storage/pill_bottle, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	click_with(user, bottle, pen)
	var/datum/op_result/long = test_answer(user, "abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij")
	TEST_ASSERT_EQUAL(long?.outcome, ACT_REFUSED, "a label of more than 50 letters is refused")
	TEST_ASSERT_EQUAL(long?.reason, /datum/msg/pill_bottle/label_too_long, "with the label line")
	TEST_ASSERT_EQUAL(bottle.label_text, "", "and no label is set")
	click_with(user, bottle, pen)
	var/datum/op_result/short = test_answer(user, "ok")
	TEST_ASSERT_EQUAL(short?.outcome, ACT_COMMITTED, "a short label commits")
	TEST_ASSERT_EQUAL(bottle.label_text, "ok", "and is kept")

// ---------------------------------------------------------------- the RCD mode radial: optional sub-pick

/datum/unit_test/dq_ar/rcd_mode_radial_cancelled_sub_pick_still_switches_the_mode

/datum/unit_test/dq_ar/rcd_mode_radial_cancelled_sub_pick_still_switches_the_mode/run_ar()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/rcd/tool = allocate(/obj/item/rcd, T)
	user.put_in_active_hand(tool)
	tool.mode_index = tool.rcd_mode_index(RCD_DECONSTRUCT)
	perform_op(user, tool, "rcd_self", tool, ORIGIN_CLICK)
	test_answer(user, "Floors & Walls")
	TEST_ASSERT(istype(SSrequests.open_for(user), /datum/prompt/choice/rcd_option_review), "the floors-and-walls pick asks its girder sub-radial")
	test_answer(user, "ERIS")
	TEST_ASSERT_EQUAL(tool.girder_type, /obj/structure/girder/eris, "an accepted pick sets the girder type")
	TEST_ASSERT_EQUAL(tool.mode_index, tool.rcd_mode_index(RCD_FLOORWALL), "and switches the mode")
	tool.mode_index = tool.rcd_mode_index(RCD_DECONSTRUCT)
	perform_op(user, tool, "rcd_self", tool, ORIGIN_CLICK)
	test_answer(user, "Floors & Walls")
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(tool.girder_type, /obj/structure/girder/eris, "a cancelled sub-pick keeps the girder type")
	TEST_ASSERT_EQUAL(tool.mode_index, tool.rcd_mode_index(RCD_FLOORWALL), "but still switches the mode")
	tool.mode_index = tool.rcd_mode_index(RCD_DECONSTRUCT)
	perform_op(user, tool, "rcd_self", tool, ORIGIN_CLICK)
	test_answer(user, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(tool.mode_index, tool.rcd_mode_index(RCD_DECONSTRUCT), "a cancelled mode radial changes nothing")

// ---------------------------------------------------------------- a question put to the actor's carrier, and the mine's countdown

/datum/unit_test/dq_ar/question_to_a_carrier_survives_the_carrier_moving

/datum/unit_test/dq_ar/question_to_a_carrier_survives_the_carrier_moving/run_ar()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/carrier = allocate(/mob/living/carbon/human, T)
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/obj/item/storage/box/card = allocate(/obj/item/storage/box, T) // stands for a pAI card: the actor is adjacent to its container only
	var/obj/ar_machine/C = allocate(/obj/ar_machine, T)
	M.forceMove(card)
	card.forceMove(carrier)
	TEST_ASSERT(op_answerer_reach(M, carrier), "the carrier is up the actor's loc chain")
	var/datum/op_result/waiting = test_ui(M, C, "ask_carrier", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the carrier is asked")
	carrier.forceMove(locate(T.x + 5, T.y, T.z))
	var/datum/op_result/done = test_answer(carrier, TRUE)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op goes on after the carrier walked off with the actor")
	TEST_ASSERT_EQUAL(C.asked_value, TRUE, "and read the answer")

/datum/unit_test/dq_ar/mine_delay_wire_repulse_keeps_the_earliest_countdown

/datum/unit_test/dq_ar/mine_delay_wire_repulse_keeps_the_earliest_countdown/run_ar()
	var/obj/effect/mine/mine = allocate(/obj/effect/mine, test_floor())
	mine.delay_wire_pulsed(null)
	test_time(1 SECOND)
	var/left = after_left(mine, "explode")
	mine.delay_wire_pulsed(null)
	TEST_ASSERT(after_left(mine, "explode") <= left, "a second pulse does not push the blast back")
