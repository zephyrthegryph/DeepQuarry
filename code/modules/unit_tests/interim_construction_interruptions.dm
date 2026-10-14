/// Exercise actual native timed cost and cancellation, then retry the same public operation.
/datum/unit_test/proc/interim_frame_interruption(drop_cable)
	var/stage = "fixture setup"
	try
		var/turf/T = test_floor()
		var/turf/away = locate(T.x + 2, T.y, T.z)
		TEST_ASSERT(away, "The fixture needs a separate turf for actor interruption")
		var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
		actor.enable_godmode()
		var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
		var/obj/item/circuitboard/autolathe/board = allocate(/obj/item/circuitboard/autolathe, T)
		var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 6)
		stage = "anchoring and inserting the actual board"
		TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_placed.anchor"), "Fixture anchoring must succeed")
		TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_board_in.insert_board", board), "Fixture board insertion must succeed")
		TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_fastened.fasten_board"), "Fixture board fastening must succeed")
		var/list/machines_before = turf_contents_of_type(T, /obj/machinery/autolathe)
		stage = "starting the actual native wiring wait"
		var/datum/op_result/first = interim_native_frame_begin(frame, actor, "construction.build:machine_frame_wired.wire", cable)
		TEST_ASSERT_NOTNULL(first, "The real public wiring operation must start")
		TEST_ASSERT_NULL(first.outcome, "The real operation remains pending during its wiring wait")
		TEST_ASSERT(length(op_pendings_of(actor)), "Wiring must register an actual native pending operation")
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "Starting wiring must not complete the frame state change")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "Starting wiring must not consume cable before completion")
		if(drop_cable)
			TEST_ASSERT(actor.drop_from_inventory(cable), "Dropping the held cable must succeed")
			TEST_ASSERT_NULL(actor.get_active_hand(), "The cable interruption must change the active hand")
		else
			actor.forceMove(away)
			TEST_ASSERT_EQUAL(actor.loc, away, "The actor interruption must actually move the actor")
		stage = "advancing past the cancelled wiring deadline"
		test_time(3 SECONDS)
		TEST_ASSERT_EQUAL(first.outcome, ACT_REFUSED, "The actual native pending operation is refused after its input is interrupted")
		TEST_ASSERT(!QDELETED(frame), "Cancellation must preserve the frame fixture")
		TEST_ASSERT(!QDELETED(actor), "Cancellation must preserve the actor fixture")
		TEST_ASSERT(!QDELETED(cable), "Cancellation must preserve the cable fixture")
		TEST_ASSERT(!QDELETED(board), "Cancellation must preserve the board fixture")
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "Interrupted wiring must preserve the fastened frame")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "Interrupted wiring must consume no cable")
		TEST_ASSERT_EQUAL(frame.circuit, board, "Interrupted wiring must preserve the frame's board reference")
		TEST_ASSERT_EQUAL(board.loc, frame, "Interrupted wiring must leave the board owned by the frame")
		TEST_ASSERT(!length(op_pendings_of(actor)), "The interrupted operation must release its pending entry")
		var/list/machines_after = turf_contents_of_type(T, /obj/machinery/autolathe)
		TEST_ASSERT_EQUAL(length(machines_after - machines_before), 0, "Interrupted construction must create no finished machine")
		if(drop_cable)
			TEST_ASSERT(actor.put_in_active_hand(cable), "The actor must recover the cable before retrying")
		else
			actor.forceMove(T)
		stage = "retrying the actual native operation"
		var/datum/op_result/retry = interim_native_frame_begin(frame, actor, "construction.build:machine_frame_wired.wire", cable)
		TEST_ASSERT(retry && isnull(retry.outcome), "Retrying must start a fresh timed operation")
		test_time(0.5 SECONDS)
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "The retry must still wait for the real wiring delay")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "The pending retry must preserve its cable")
		stage = "advancing past the retry deadline"
		test_time(2 SECONDS)
		TEST_ASSERT(test_op_committed(retry), "The uninterrupted actual retry commits")
		TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "An uninterrupted retry must finish wiring")
		TEST_ASSERT_EQUAL(cable.get_amount(), 1, "The successful retry must consume exactly five cable lengths")
		TEST_ASSERT_EQUAL(frame.circuit, board, "Successful wiring must retain the original board")
		TEST_ASSERT_EQUAL(board.loc, frame, "Successful wiring must retain board ownership")
		TEST_ASSERT(!length(op_pendings_of(actor)), "The successful retry must release its pending entry")
	catch(var/exception/e)
		TEST_FAIL("Timed frame runtime during [stage]: [e] ([e.file]:[e.line])\n[e.desc]")

/datum/unit_test/om/interim_frame_wiring_actor_interruption
	parent_type = /datum/unit_test/dq_round3_frame_construction
/datum/unit_test/om/interim_frame_wiring_actor_interruption/run_gate()
	interim_frame_interruption(FALSE)

/datum/unit_test/om/interim_frame_wiring_cable_interruption
	parent_type = /datum/unit_test/dq_round3_frame_construction
/datum/unit_test/om/interim_frame_wiring_cable_interruption/run_gate()
	interim_frame_interruption(TRUE)
