// Native frame graph regressions through real tool and item inputs.
/datum/unit_test/dq_round3_frame_construction
	parent_type = /datum/unit_test/dq_hc_struct
	abstract_type = /datum/unit_test/dq_round3_frame_construction

/datum/unit_test/dq_round3_frame_construction/proc/frame_click(mob/living/carbon/human/H, obj/structure/frame/F, obj/item/I, delay = 0)
	H.drop_item()
	TEST_ASSERT(H.put_in_active_hand(I), "the builder holds the actual input")
	var/datum/op_result/R = test_click(H, F, I)
	if(delay)
		test_time(delay)
	return R

/datum/unit_test/dq_round3_frame_construction/board_roundtrip
/datum/unit_test/dq_round3_frame_construction/board_roundtrip/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/F = allocate(/obj/structure/frame, tile(3, 2))
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, H.loc)
	var/obj/item/tool/crowbar/C = allocate(/obj/item/tool/crowbar, H.loc)
	var/obj/item/circuitboard/food_replicator/B = allocate(/obj/item/circuitboard/food_replicator, H.loc)
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_LOOSE, "a real loose frame starts at the native graph's loose stage")
	var/datum/op_result/R = frame_click(H, F, W, 2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "wrenching completes through the actual native graph")
	TEST_ASSERT(F.anchored && F.state == FRAME_PLACED, "the first transition anchors the real frame")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_PLACED, "the graph and legacy appearance state agree after anchoring")
	R = frame_click(H, F, B)
	TEST_ASSERT(test_op_committed(R), "the compatible board is accepted through its real click")
	TEST_ASSERT_EQUAL(F.circuit, B, "insertion records the actual circuit relation")
	TEST_ASSERT_EQUAL(B.loc, F, "the actual board moves into the frame")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_BOARD_IN, "the graph advances with board custody")
	R = frame_click(H, F, C)
	TEST_ASSERT(test_op_committed(R), "crowbarring takes the real board back out")
	TEST_ASSERT_NULL(F.circuit, "board removal clears the actual relation")
	TEST_ASSERT_EQUAL(B.loc, F.loc, "removal returns the original board to the floor")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_PLACED, "the reverse edge returns to placed")
	R = frame_click(H, F, W, 2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "wrenching reverses anchoring")
	TEST_ASSERT(!F.anchored && graph_current(F) == STAGE_MACHINE_FRAME_LOOSE, "the roundtrip restores a real loose frame")

/datum/unit_test/dq_round3_frame_construction/wiring_roundtrip
/datum/unit_test/dq_round3_frame_construction/wiring_roundtrip/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/F = allocate(/obj/structure/frame, tile(3, 2))
	var/obj/item/circuitboard/food_replicator/B = allocate(/obj/item/circuitboard/food_replicator, F)
	rel_set(F, nameof(F.circuit), B)
	F.set_anchored(TRUE)
	F.state = FRAME_FASTENED
	F.check_components()
	F.update_desc()
	F.seed_native_frame_graph()
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_FASTENED, "a supplied board-fastened frame seeds the actual declared path")
	var/obj/item/stack/cable_coil/S = allocate(/obj/item/stack/cable_coil, H.loc, 8)
	var/datum/op_result/R = frame_click(H, F, S)
	TEST_ASSERT_EQUAL(F.state, FRAME_FASTENED, "wiring does not advance before its real wait")
	test_time(2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "five-unit wiring commits after its real wait")
	TEST_ASSERT_EQUAL(S.get_amount(), 3, "wiring spends exactly five cable units")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_WIRED, "the cable edge reaches wired")
	var/obj/item/tool/wirecutters/W = allocate(/obj/item/tool/wirecutters, H.loc)
	R = frame_click(H, F, W)
	TEST_ASSERT(test_op_committed(R), "the real wirecutters reverse wiring")
	TEST_ASSERT_EQUAL(F.state, FRAME_FASTENED, "unwiring restores the appearance-facing state")
	var/obj/item/stack/cable_coil/refund = locate() in F.loc
	TEST_ASSERT(refund && refund.get_amount() == 5, "unwiring returns exactly the five installed cable units")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_FASTENED, "the graph follows the reverse edge")

/datum/unit_test/dq_round3_frame_construction/computer_glass_roundtrip
/datum/unit_test/dq_round3_frame_construction/computer_glass_roundtrip/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/computer/F = allocate(/obj/structure/frame/computer, tile(3, 2))
	F.state = FRAME_WIRED
	F.seed_native_frame_graph()
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_WIRED, "a placed wired computer frame is seeded in the native graph")
	var/obj/item/stack/material/glass/G = allocate(/obj/item/stack/material/glass, H.loc, 4)
	var/datum/op_result/R = frame_click(H, F, G, 2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "real plain glass completes the panel edge")
	TEST_ASSERT_EQUAL(G.get_amount(), 2, "the panel uses exactly two real glass sheets")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_PANELED, "the native graph reaches paneled")
	var/obj/item/tool/crowbar/C = allocate(/obj/item/tool/crowbar, H.loc)
	R = frame_click(H, F, C)
	TEST_ASSERT(test_op_committed(R), "crowbar removal takes the panel back out")
	var/obj/item/stack/material/glass/refund = locate() in F.loc
	TEST_ASSERT(refund && refund.get_amount() == 2, "panel removal returns exactly two glass sheets")
	TEST_ASSERT_EQUAL(F.state, FRAME_WIRED, "panel removal restores the current frame state")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_WIRED, "the reverse graph edge restores wired")

/datum/unit_test/dq_round3_frame_construction/missing_parts_refuse_finish
/datum/unit_test/dq_round3_frame_construction/missing_parts_refuse_finish/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/F = allocate(/obj/structure/frame, tile(3, 2))
	var/obj/item/circuitboard/food_replicator/B = allocate(/obj/item/circuitboard/food_replicator, F)
	rel_set(F, nameof(F.circuit), B)
	F.set_anchored(TRUE)
	F.state = FRAME_WIRED
	F.check_components()
	F.update_desc()
	F.seed_native_frame_graph()
	TEST_ASSERT(length(F.req_components), "the real board declares nonempty required parts")
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, H.loc)
	var/datum/op_result/R = frame_click(H, F, S)
	TEST_ASSERT(!test_op_committed(R), "a real screwdriver cannot finish while required parts are absent")
	TEST_ASSERT(!QDELETED(F) && F.circuit == B, "refusal preserves the frame and its real board")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_WIRED, "refusal cannot advance the graph")

/datum/unit_test/dq_round3_frame_construction/finish_transfers_real_parts
/datum/unit_test/dq_round3_frame_construction/finish_transfers_real_parts/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/F = allocate(/obj/structure/frame, tile(3, 2))
	var/turf/spot = get_turf(F)
	var/obj/item/circuitboard/food_replicator/B = allocate(/obj/item/circuitboard/food_replicator, F)
	rel_set(F, nameof(F.circuit), B)
	F.set_anchored(TRUE)
	F.state = FRAME_WIRED
	F.check_components()
	F.update_desc()
	F.seed_native_frame_graph()
	var/list/installed = list()
	for(var/path in B.req_components)
		var/amount = B.req_components[path]
		if(ispath(path, /obj/item/stack))
			var/obj/item/stack/P = allocate(path, H.loc, amount)
			TEST_ASSERT(F.install_part(H, P), "the actual stack is installed through the frame's current insertion path")
		else
			for(var/i in 1 to amount)
				var/obj/item/P = allocate(path, H.loc)
				TEST_ASSERT(F.install_part(H, P), "each actual stock part is installed through the current insertion path")
	for(var/obj/item/P in F.components)
		installed += P
	TEST_ASSERT(length(installed), "the real frame contains physical installed components")
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, H.loc)
	var/datum/op_result/R = frame_click(H, F, S)
	TEST_ASSERT(test_op_committed(R), "the completed board and actual components allow the native finish edge")
	var/obj/machinery/food_replicator/M = locate() in spot
	TEST_ASSERT(QDELETED(F) && M, "finishing replaces the frame with the board's real machine")
	TEST_ASSERT_EQUAL(M.circuit, B, "the original circuit is handed over to the finished machine")
	for(var/obj/item/P in installed)
		TEST_ASSERT(P in M.component_parts, "each original installed part is transferred into the built machine")

/// Shared fixture adapter: a named public native op with a real held input.
/datum/unit_test/proc/interim_native_frame_input(obj/structure/frame/F, mob/actor, key, obj/item/held)
	if(!held)
		var/tool_type
		if(findtext(key, ".anchor") || findtext(key, ".unanchor"))
			tool_type = /obj/item/tool/wrench
		else if(findtext(key, ".remove_board") || findtext(key, ".remove_components") || findtext(key, ".remove_glass"))
			tool_type = /obj/item/tool/crowbar
		else if(findtext(key, ".unwire"))
			tool_type = /obj/item/tool/wirecutters
		else
			tool_type = /obj/item/tool/screwdriver
		held = allocate(tool_type, get_turf(actor))
	if(actor.get_active_hand() != held)
		actor.drop_item()
		if(!actor.put_in_active_hand(held))
			return null
	return held

/datum/unit_test/proc/interim_native_frame_begin(obj/structure/frame/F, mob/actor, key, obj/item/held)
	held = interim_native_frame_input(F, actor, key, held)
	if(!held)
		return null
	return test_menu(actor, F, key)

/datum/unit_test/proc/interim_native_frame_step(obj/structure/frame/F, mob/actor, key, obj/item/held)
	var/datum/op_result/R = interim_native_frame_begin(F, actor, key, held)
	if(R && isnull(R.outcome))
		test_time(interim_native_frame_delay(F, key, actor.get_active_hand()))
	return test_op_committed(R)

/// Inspect the same match/require stages used by the public operation, without starting work.
/datum/unit_test/proc/interim_native_frame_reason(obj/structure/frame/F, mob/actor, key, obj/item/held)
	held = interim_native_frame_input(F, actor, key, held)
	if(!held)
		return "not holding the input"
	var/datum/op_resolution/R = own(op_resolve(actor, F, held, ORIGIN_MENU, AUTH_PHYSICAL, key = key))
	for(var/datum/op_cand/C as anything in R.ordered)
		if(C.oplan.key == key && op_cand_when(R, C))
			return op_cand_require_reason(R, C)
	return "no matching construction input"

/datum/unit_test/proc/interim_native_frame_driver_end()
	test_driver_end()

/datum/unit_test/proc/interim_native_frame_started(obj/structure/frame/F, mob/actor, key, obj/item/held)
	var/datum/op_result/R = interim_native_frame_begin(F, actor, key, held)
	return R && R.key == key && R.outcome != ACT_REFUSED && R.outcome != ACT_DECLINED

/datum/unit_test/proc/interim_native_frame_delay(obj/structure/frame/F, key, obj/item/held)
	var/datum/op_plan/P = op_plan_for(F, key)
	if(!P)
		return null
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = F
	A.target = F
	A.set_held_provider(held)
	A.binding = P.bindings[1]
	var/delay = 0
	for(var/datum/entry/part/wait/W in P.steps)
		delay += W.wait_time(A)
	A.release()
	return delay

/datum/unit_test/dq_round3_frame_construction/fitted_board_anchor
/datum/unit_test/dq_round3_frame_construction/fitted_board_anchor/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/F = allocate(/obj/structure/frame, tile(3, 2), SOUTH, TRUE, new /datum/frame/frame_types/conveyor)
	TEST_ASSERT(!F.need_circuit && F.circuit, "the actual conveyor frame constructor supplies its built-in board")
	var/obj/item/circuitboard/B = F.circuit
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, H.loc)
	var/datum/op_result/R = frame_click(H, F, W, 2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "the native fitted-board anchor branch completes with the real constructor board")
	TEST_ASSERT_EQUAL(F.circuit, B, "anchoring preserves the original fitted board")
	TEST_ASSERT(F.anchored && F.state == FRAME_FASTENED, "anchoring closes the fitted-board frame's outer cover")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_FASTENED, "the native graph reaches fastened directly from loose")

/datum/unit_test/dq_round3_frame_construction/generic_plain_glass_material
/datum/unit_test/dq_round3_frame_construction/generic_plain_glass_material/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/frame/computer/F = allocate(/obj/structure/frame/computer, tile(3, 2))
	F.state = FRAME_WIRED
	F.seed_native_frame_graph()
	var/obj/item/stack/material/G = allocate(/obj/item/stack/material, H.loc, 3)
	TEST_ASSERT(!istype(G, /obj/item/stack/material/glass), "the actual generic stack is not the glass subtype")
	TEST_ASSERT(G.set_stack_material(MAT_GLASS), "the real public material setter assigns registered plain glass")
	TEST_ASSERT_EQUAL(G.get_material_name(), MAT_GLASS, "the stack is physically composed of plain glass")
	var/datum/op_result/R = frame_click(H, F, G, 2 SECONDS)
	TEST_ASSERT(test_op_committed(R), "the real native click accepts plain-glass material independently of the item subtype")
	TEST_ASSERT_EQUAL(G.get_amount(), 1, "generic plain glass supplies exactly two real sheets")
	TEST_ASSERT_EQUAL(graph_current(F), STAGE_MACHINE_FRAME_PANELED, "material-based admission advances the native panel stage")
