/// Records the actor at the real board construction boundary, then chains its actual base behavior.
/obj/item/circuitboard/arcade/battle/interim_construct_actor_probe
	var/construct_actor_ref
	var/construct_product_ref

/obj/item/circuitboard/arcade/battle/interim_construct_actor_probe/construct(obj/machinery/M, mob/user = null)
	construct_actor_ref = REF(user)
	construct_product_ref = REF(M)
	return ..(M, user)

/// Actual final construction runs under a different native ambient actor.
/obj/interim_frame_construct_actor_probe
	var/obj/structure/frame/frame
	var/mob/actor
	var/result

/obj/interim_frame_construct_actor_probe/Click(location, control, params)
	var/datum/construction_graph/graph = construction_graph_of(frame)
	for(var/datum/interaction/construction/edge as anything in graph.edges_for(frame))
		if(edge.type == /datum/interaction/construction/frame/connect_monitor)
			result = edge.traverse(frame, actor, null)
			return

/datum/unit_test/interim_frame_board_construct_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
	var/obj/item/circuitboard/arcade/battle/interim_construct_actor_probe/board = allocate(/obj/item/circuitboard/arcade/battle/interim_construct_actor_probe, T)
	rel_set(frame, nameof(frame.frame_type), frame_type_copy(board.board_type))
	frame.set_dir(WEST)
	var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 6)
	var/obj/item/stack/material/glass/glass = allocate(/obj/item/stack/material/glass, T, 3)
	TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/anchor), "the real computer fixture anchors through its construction edge")
	TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/insert_board, board), "the real matching board enters its frame")
	TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/fasten_board), "the real board fastens through its construction edge")
	TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/wire, cable), "the real computer wiring edge completes")
	TEST_ASSERT_EQUAL(cable.get_amount(), 1, "the actual wiring consumes exactly five cable lengths")
	TEST_ASSERT(interim_construction_step(frame, actor, /datum/interaction/construction/frame/add_glass, glass), "the real glass-panel construction edge completes")
	TEST_ASSERT_EQUAL(glass.get_amount(), 1, "the real glass edge consumes exactly two sheets")
	var/obj/interim_frame_construct_actor_probe/probe = allocate(/obj/interim_frame_construct_actor_probe, T)
	rel_set(probe, nameof(probe.frame), frame)
	rel_set(probe, nameof(probe.actor), actor)
	km_synthetic_click(bystander, probe)
	own_turf_contents(T)
	TEST_ASSERT(probe.result, "the real final construction edge succeeds under an unrelated ambient actor")
	TEST_ASSERT(QDELETED(frame), "actual completion expires the original frame")
	var/obj/machinery/computer/arcade/battle/product = locate_within(T, /obj/machinery/computer/arcade/battle)
	TEST_ASSERT_NOTNULL(product, "actual final construction creates the board's exact declared computer type")
	TEST_ASSERT_EQUAL(product.circuit, board, "the actual product owns the player's exact installed board")
	TEST_ASSERT_EQUAL(board.construct_actor_ref, REF(actor), "the actual board constructor receives the explicit construction actor rather than its ambient caller")
	TEST_ASSERT_EQUAL(board.construct_product_ref, REF(product), "the actual board constructor receives the exact resulting computer")
	TEST_ASSERT_EQUAL(product.dir, WEST, "actual final construction preserves frame direction")
	TEST_ASSERT(!QDELETED(board), "actual frame expiry preserves the installed board")
