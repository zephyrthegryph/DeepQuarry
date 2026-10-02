/// Exercise the actual timed cost and cancellation channels, then retry the same edge.
/datum/unit_test/om/proc/interim_frame_interruption(list/made, drop_cable)
	var/stage = "fixture setup"
	try
		var/turf/T = test_floor()
		var/turf/away = locate(T.x + 2, T.y, T.z)
		TEST_ASSERT(away, "The fixture needs a separate turf for actor interruption")
		stage = "1: var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)"
		var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
		// Only construction tasks advance here; physiological cadence belongs to Life tests.
		TEST_ASSERT(om_detach(actor, /datum/om/pipeline/life), "The isolated construction actor must detach its unrelated Life pipeline")
		stage = "2: var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)"
		var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
		stage = "3: var/obj/item/circuitboard/autolathe/board = allocate(/obj/item/circuitboard/autolathe, T)"
		var/obj/item/circuitboard/autolathe/board = allocate(/obj/item/circuitboard/autolathe, T)
		stage = "4: var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 6)"
		var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 6)
		made += list(actor, frame, board, cable)
		stage = "5: TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/anchor), \"Fixture anchoring must succeed\")"
		TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/anchor), "Fixture anchoring must succeed")
		stage = "6: TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/insert_board, board), \"Fixture board insertion must succeed\")"
		TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/insert_board, board), "Fixture board insertion must succeed")
		stage = "7: TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/fasten_board), \"Fixture board fastening must succeed\")"
		TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/fasten_board), "Fixture board fastening must succeed")
		stage = "8: TEST_ASSERT(actor.put_in_active_hand(cable), \"The actor must hold the wiring material\")"
		TEST_ASSERT(actor.put_in_active_hand(cable), "The actor must hold the wiring material")
		var/datum/interaction/construction/wire
		for(var/datum/interaction/construction/edge as anything in construction_edges_for(frame))
			if(edge.type == /datum/interaction/construction/frame/wire)
				wire = edge
		TEST_ASSERT(wire, "A fastened machine frame must offer its wiring edge")
		TEST_ASSERT_EQUAL(wire.duration, 2 SECONDS, "This test must exercise the real delayed wiring edge")
		stage = "9: var/list/machines_before = turf_contents_of_type(T, /obj/machinery/autolathe)"
		var/list/machines_before = turf_contents_of_type(T, /obj/machinery/autolathe)
		stage = "10: TEST_ASSERT(wire.perform(actor, frame, cable), \"The real timed wiring interaction must start\")"
		TEST_ASSERT(wire.perform(actor, frame, cable), "The real timed wiring interaction must start")
		TEST_ASSERT(LAZYLEN(actor.do_afters), "Wiring must register an actual pending action")
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "Starting wiring must not complete the frame state change")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "Starting wiring must not consume cable before completion")
		if(drop_cable)
			TEST_ASSERT(actor.drop_from_inventory(cable), "Dropping the held cable must succeed")
			TEST_ASSERT_NULL(actor.get_active_hand(), "The cable interruption must change the active hand")
		else
			actor.forceMove(away)
			TEST_ASSERT_EQUAL(actor.loc, away, "The actor interruption must actually move the actor")
		stage = "11: scheduler_advance((3 SECONDS) / SECONDS)"
		scheduler_advance((3 SECONDS) / SECONDS)
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "Interrupted wiring must preserve the fastened frame")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "Interrupted wiring must consume no cable")
		TEST_ASSERT_EQUAL(frame.circuit, board, "Interrupted wiring must preserve the frame's board reference")
		TEST_ASSERT_EQUAL(board.loc, frame, "Interrupted wiring must leave the board owned by the frame")
		TEST_ASSERT(!LAZYLEN(actor.do_afters), "The interrupted action must release its pending-action entry")
		stage = "12: var/list/machines_after = turf_contents_of_type(T, /obj/machinery/autolathe)"
		var/list/machines_after = turf_contents_of_type(T, /obj/machinery/autolathe)
		TEST_ASSERT_EQUAL(length(machines_after - machines_before), 0, "Interrupted construction must create no finished machine")
		if(drop_cable)
			TEST_ASSERT(actor.put_in_active_hand(cable), "The actor must recover the cable before retrying")
		else
			actor.forceMove(T)
		stage = "13: TEST_ASSERT(wire.perform(actor, frame, cable), \"Retrying the interrupted edge must start a fresh timed action\")"
		TEST_ASSERT(wire.perform(actor, frame, cable), "Retrying the interrupted edge must start a fresh timed action")
		stage = "14: scheduler_advance((0.5 SECONDS) / SECONDS)"
		scheduler_advance((0.5 SECONDS) / SECONDS)
		TEST_ASSERT_EQUAL(frame.state, FRAME_FASTENED, "The retry must still wait for the real wiring delay")
		TEST_ASSERT_EQUAL(cable.get_amount(), 6, "The pending retry must preserve its cable")
		stage = "15: scheduler_advance((2 SECONDS) / SECONDS)"
		scheduler_advance((2 SECONDS) / SECONDS)
		TEST_ASSERT_EQUAL(frame.state, FRAME_WIRED, "An uninterrupted retry must finish wiring")
		TEST_ASSERT_EQUAL(cable.get_amount(), 1, "The successful retry must consume exactly five cable lengths")
		TEST_ASSERT_EQUAL(frame.circuit, board, "Successful wiring must retain the original board")
		TEST_ASSERT_EQUAL(board.loc, frame, "Successful wiring must retain board ownership")
		TEST_ASSERT(!LAZYLEN(actor.do_afters), "The successful retry must release its pending-action entry")
	catch(var/exception/e)
		TEST_FAIL("Timed frame runtime during [stage]: [e] ([e.file]:[e.line])\n[e.desc]")

/datum/unit_test/om/interim_frame_wiring_actor_interruption/run_om(list/made)
	interim_frame_interruption(made, FALSE)

/datum/unit_test/om/interim_frame_wiring_cable_interruption/run_om(list/made)
	interim_frame_interruption(made, TRUE)
