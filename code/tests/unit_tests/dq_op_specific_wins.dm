// The more specific held-item op always wins (final_api.html section 1 "Precedence"): an op bound to a tool, item or stack is OP_PRIORITY_PART and answers
// a click with that thing in hand before the holder's own hand() op, whoever declared it and whatever priority it pinned (code/engine/parts/plan.dm,
// op_plan_finish()). The compiled click and the full resolver agree (op_click_parity_check() runs on every click of the test build).

/obj/dq_specific_base
	var/ran = ""

CAPABILITIES(/obj/dq_specific_base)
	op("base_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(ran_wrench)))
	op("base_wrench_pinned", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(ran_crowbar)))

/obj/dq_specific_base/proc/ran_wrench(datum/act/op/A)
	ran = "wrench"
	return OP_OK

/obj/dq_specific_base/proc/ran_crowbar(datum/act/op/A)
	ran = "crowbar"
	return OP_OK

/obj/dq_specific_base/child

CAPABILITIES(/obj/dq_specific_base/child)
	op("child_hand", hand(), wait(0), then(PROC_REF(ran_hand)))

/obj/dq_specific_base/child/proc/ran_hand(datum/act/op/A)
	ran = "hand"
	return OP_OK

/datum/unit_test/dq_op_specific_wins_over_hand

/datum/unit_test/dq_op_specific_wins_over_hand/proc/click_with(mob/living/carbon/human/H, obj/dq_specific_base/target, obj/item/held)
	H.drop_item()
	if(held)
		H.put_in_active_hand(held)
	H.set_use_stance(I_HELP)
	STATE_SET(H, cooldowns, next_click, 0)
	target.ran = ""
	input_submit(new /datum/input_event/click(H, target, null, null, "left=1"))
	test_time(1 SECOND)
	return target.ran

/datum/unit_test/dq_op_specific_wins_over_hand/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/dq_specific_base/child/C = allocate(/obj/dq_specific_base/child, T)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, T)
	var/obj/item/tool/crowbar/B = allocate(/obj/item/tool/crowbar, T)
	TEST_ASSERT_EQUAL(click_with(H, C, W), "wrench", "a wrench click runs the inherited tool op, not the type's own hand op")
	TEST_ASSERT_EQUAL(click_with(H, C, B), "crowbar", "a tool op that pinned a legacy low priority still beats the hand op")
	TEST_ASSERT_EQUAL(click_with(H, C, null), "hand", "an empty-hand click runs the hand op")
