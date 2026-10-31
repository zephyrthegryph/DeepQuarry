/// The real loose machine-frame cutting edge refuses a wrong tool and refunds its exact frame-size allowance only after welding completes.
/datum/unit_test/om/interim_machine_frame_timed_cut_refund
	parent_type = /datum/unit_test/dq_round3_frame_construction

/datum/unit_test/om/interim_machine_frame_timed_cut_refund/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	TEST_ASSERT_EQUAL(graph_current(frame), STAGE_MACHINE_FRAME_LOOSE, "the actual unanchored frame begins in its declared loose construction state")
	var/refund_size = frame.frame_type.frame_size
	TEST_ASSERT(refund_size > 0, "the actual frame's declared sheet allowance is positive")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "the actual cutting fixture begins without recovered sheets")
	var/cutting = "construction.build:machine_frame_finished.cut_apart"
	TEST_ASSERT_NOTNULL(op_plan_for(frame, cutting), "the actual loose frame exposes its declared cutting edge")
	user.drop_item()
	TEST_ASSERT(user.put_in_active_hand(wrench), "the actor holds the actual wrong construction tool")
	TEST_ASSERT_NOTNULL(interim_native_frame_reason(frame, user, cutting, wrench), "the actual cutting requirement refuses a wrench")
	TEST_ASSERT(!interim_native_frame_started(frame, user, cutting, wrench), "the actual public edge rejects the wrong tool")
	TEST_ASSERT(!QDELETED(frame), "wrong-tool refusal preserves the original frame")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "wrong-tool refusal creates no sheet refund")
	TEST_ASSERT(!LAZYLEN(GLOB.op_pending_by_actor[REF(user)]), "wrong-tool refusal starts no cutting task")
	TEST_ASSERT(user.unEquip(wrench), "the actor actually clears the wrong tool")
	user.drop_item()
	TEST_ASSERT(user.put_in_active_hand(welder), "the actor holds the real welding tool")
	TEST_ASSERT(test_op_handler(welder, "interaction_self", user, welder), "actual tool interaction lights the welder")
	TEST_ASSERT(welder.isOn(), "the real held welder is lit")
	var/cutting_delay = interim_native_frame_delay(frame, cutting, welder)
	TEST_ASSERT(cutting_delay > 0, "the actual cutting edge has a positive scaled tool delay")
	TEST_ASSERT_NULL(interim_native_frame_reason(frame, user, cutting, welder), "the actual lit welder satisfies the construction requirement")
	TEST_ASSERT(interim_native_frame_started(frame, user, cutting, welder), "the public construction edge starts actual timed cutting")
	TEST_ASSERT(LAZYLEN(GLOB.op_pending_by_actor[REF(user)]), "actual cutting creates its pending timed task")
	TEST_ASSERT(!QDELETED(frame), "starting actual cutting preserves the original frame until completion")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "starting actual cutting creates no early sheet refund")
	test_time(cutting_delay + 1 SECOND)
	test_op_handler(welder, "interaction_self", user, welder)
	own_turf_contents(T)
	TEST_ASSERT(!user.incapacitated(), "the actual safe fixture stays capable through cutting")
	TEST_ASSERT(!LAZYLEN(GLOB.op_pending_by_actor[REF(user)]), "actual completed cutting releases its pending task")
	TEST_ASSERT(QDELETED(frame), "actual completed cutting consumes the original frame")
	var/refunded_sheets = 0
	var/refund_stacks = 0
	for(var/obj/item/stack/material/refund as anything in contents_of(T, /obj/item/stack/material))
		TEST_ASSERT(istype(refund, /obj/item/stack/material/steel), "actual frame cutting refunds only its declared steel sheets")
		refunded_sheets += refund.get_amount()
		refund_stacks++
	TEST_ASSERT_EQUAL(refund_stacks, 1, "actual cutting creates exactly one material stack")
	TEST_ASSERT_EQUAL(refunded_sheets, refund_size, "actual cutting refunds exactly the original frame-type sheet allowance")
	TEST_ASSERT_EQUAL(user.get_active_hand(), welder, "actual cutting preserves the actor's original welding tool")
