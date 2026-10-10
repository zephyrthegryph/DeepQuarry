// Behaviour pins for physical paths (spaces and doors): what a click reaches through an APC's cover, an airlock's panel and a locker's door, and
// which reason a refused click gives. Written before the path system replaced the per-type when()/needs() gates, so the same file passes before
// and after (doc/rewrite/final_api.html section 8 "Spaces and doors", 16.1a).

/// The key of the op a click by `actor` on `target` with `held` would run, or null when nothing answers.
/proc/paths_winner_key(mob/actor, atom/target, obj/item/held)
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_CLICK, actor_authority(actor), GESTURE_CLICK, null)
	var/datum/op_cand/winner = op_resolution_winner(R)
	return winner?.oplan?.key

/// Did a click by `actor` on `target` with `held` run op `key` to the end? (A refused or set-aside op did not.)
/proc/paths_click_ran(mob/actor, atom/target, obj/item/held, key)
	if(held && actor.get_active_hand() != held)
		actor.drop_item()
		actor.put_in_active_hand(held)
	var/datum/op_result/result = test_click(actor, target, held)
	test_time(5 SECONDS)
	return result?.key == key && result?.outcome == ACT_COMMITTED

// ---------------------------------------------------------------------------------------------------------------------
// The APC (16.1a, cases 1 to 5, and the reasons its hatch gives)
// ---------------------------------------------------------------------------------------------------------------------

/// Case 1: an empty hand on a closed APC does not reach the cell; the window opens instead.
/datum/unit_test/dq_p2_apc/paths_closed_cover_empty_hand_opens_the_window

/datum/unit_test/dq_p2_apc/paths_closed_cover_empty_hand_opens_the_window/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	H.drop_item()
	touch(H, A, null)
	TEST_ASSERT_EQUAL(A.cell, original, "the cell stays")
	TEST_ASSERT(p2_apc_interface_opened(A, H), "the window opened")

/// Case 2: with the cover open an empty hand takes the cell.
/datum/unit_test/dq_p2_apc/paths_open_cover_empty_hand_takes_the_cell

/datum/unit_test/dq_p2_apc/paths_open_cover_empty_hand_takes_the_cell/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	open_cover(H, A)
	H.drop_item()
	TEST_ASSERT_EQUAL(paths_winner_key(H, A, null), "cell_bay.cell.take", "the take answers an open APC")

/// Case 3: a cell in hand on a closed APC is refused with the cover's reason; the cell stays in hand.
/datum/unit_test/dq_p2_apc/paths_cell_in_hand_refused_by_the_closed_cover

/datum/unit_test/dq_p2_apc/paths_cell_in_hand_refused_by_the_closed_cover/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/original = A.cell
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	open_cover(H, A)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "the cell is out")
	touch(H, A, bar)
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover is shut over the empty bay")
	H.drop_item()
	H.put_in_active_hand(original)
	var/datum/op_result/result = test_click(H, A, original)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the insert is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/cover/closed, "with the cover's reason")
	TEST_ASSERT_NULL(A.cell, "the bay stays empty")
	TEST_ASSERT(H.is_in_hands(original), "the cell stays in hand")

/// Case 4: the cell itself is out of reach behind the closed cover, and in reach behind the open one.
/datum/unit_test/dq_p2_apc/paths_cell_unreachable_behind_the_closed_cover

/datum/unit_test/dq_p2_apc/paths_cell_unreachable_behind_the_closed_cover/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT_EQUAL(reach_exposure(H, A.cell, AUTH_PHYSICAL), /datum/msg/cover/closed, "the closed cover blocks the walk to the cell")
	open_cover(H, A)
	TEST_ASSERT_NULL(reach_exposure(H, A.cell, AUTH_PHYSICAL), "the open cover lets it through")

/// Case 5: an AI's remote reach never takes or inserts the cell, whatever the cover.
/datum/unit_test/dq_p2_apc/paths_remote_ai_never_reaches_the_cell

/datum/unit_test/dq_p2_apc/paths_remote_ai_never_reaches_the_cell/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, run_loc_floor_top_right, null, null, null, TRUE)
	var/obj/item/cell/original = A.cell
	TEST_ASSERT(!paths_click_ran(AI, A, null, "cell_bay.cell.take"), "closed: the AI does not take the cell")
	open_cover(H, A)
	TEST_ASSERT(!paths_click_ran(AI, A, null, "cell_bay.cell.take"), "open: the AI still does not take the cell")
	TEST_ASSERT_EQUAL(A.cell, original, "the cell stays")

/// The cover lock holds the cover shut over a charged cell, with its reason.
/datum/unit_test/dq_p2_apc/paths_cover_lock_reason

/datum/unit_test/dq_p2_apc/paths_cover_lock_reason/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	H.drop_item()
	H.put_in_active_hand(bar)
	var/datum/op_result/result = test_click(H, A, bar)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the crowbar is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/apc/cover_locked, "because the cover is locked")
	TEST_ASSERT(!p2_apc_cover_open(A), "the cover stays shut")

/// A broken APC's cover is held shut with its own reason.
/datum/unit_test/dq_p2_apc/paths_broken_cover_reason

/datum/unit_test/dq_p2_apc/paths_broken_cover_reason/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	A.coverlocked = FALSE
	A.take_damage(A.max_integrity * 0.75)
	p2_settle()
	H.drop_item()
	H.put_in_active_hand(bar)
	var/datum/op_result/result = test_click(H, A, bar)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the crowbar is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/apc/cover_broken, "because it is broken")

/// A loose board keeps the cover from closing, with its reason.
/datum/unit_test/dq_p2_apc/paths_loose_board_reason

/datum/unit_test/dq_p2_apc/paths_loose_board_reason/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/crowbar/bar = tool(/obj/item/tool/crowbar)
	touch(H, A, allocate(/obj/item/module/power_control, run_loc_floor_bottom_left))
	TEST_ASSERT_EQUAL(p2_apc_stage(A), "board", "the board is in")
	TEST_ASSERT(p2_apc_cover_open(A), "the cover is open")
	H.drop_item()
	H.put_in_active_hand(bar)
	var/datum/op_result/result = test_click(H, A, bar)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the crowbar is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/apc/board_first, "because the board is loose")
	TEST_ASSERT(p2_apc_cover_open(A), "the cover stays open")

/// A cell in hand on an unfinished frame is refused: the electronics are not in yet.
/datum/unit_test/dq_p2_apc/paths_cell_needs_the_electronics

/datum/unit_test/dq_p2_apc/paths_cell_needs_the_electronics/run_gate()
	var/obj/machinery/power/apc/A = p2_frame()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/apc/spare = allocate(/obj/item/cell/apc, run_loc_floor_bottom_left)
	TEST_ASSERT(p2_apc_cover_open(A), "the frame's cover is open")
	H.drop_item()
	H.put_in_active_hand(spare)
	var/datum/op_result/result = test_click(H, A, spare)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the cell is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/apc/needs_electronics, "until the electronics are in")
	TEST_ASSERT_NULL(A.cell, "the bay stays empty")

/// A device cell is refused with a size reason.
/datum/unit_test/dq_p2_apc/paths_small_cell_reason

/datum/unit_test/dq_p2_apc/paths_small_cell_reason/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/cell/small = allocate(/obj/item/cell/device, run_loc_floor_bottom_left)
	open_cover(H, A)
	touch(H, A, null)
	TEST_ASSERT_NULL(A.cell, "bay empty")
	H.drop_item()
	H.put_in_active_hand(small)
	var/datum/op_result/result = test_click(H, A, small)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the device cell is refused")
	TEST_ASSERT_NOTNULL(result?.reason, "with a reason")
	TEST_ASSERT_NULL(A.cell, "the bay stays empty")

/// The panel will not open while the cover is open, with its reason (asked by key: a screwdriver click on an open hatch works the build steps).
/datum/unit_test/dq_p2_apc/paths_panel_needs_the_cover_closed_reason

/datum/unit_test/dq_p2_apc/paths_panel_needs_the_cover_closed_reason/run_gate()
	var/obj/machinery/power/apc/A = p2_apc()
	var/mob/living/carbon/human/H = p2_actor()
	var/obj/item/tool/screwdriver/driver = tool(/obj/item/tool/screwdriver)
	open_cover(H, A)
	H.drop_item()
	H.put_in_active_hand(driver)
	var/datum/op_result/result = perform_op(H, A, "panel.open", driver)
	p2_settle()
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "opening the panel is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/hatch/close_cover, "until the cover is closed")
	TEST_ASSERT(!p2_apc_panel_open(A), "the panel stays shut")

// ---------------------------------------------------------------------------------------------------------------------
// The airlock's panel and wires
// ---------------------------------------------------------------------------------------------------------------------

/// The wires answer a multitool, a wirecutter and an empty hand only behind the open panel.
/datum/unit_test/dq_p2_door/paths_airlock_wires_behind_the_panel

/datum/unit_test/dq_p2_door/paths_airlock_wires_behind_the_panel/run_gate()
	var/obj/machinery/door/airlock/D = make_door()
	var/mob/living/carbon/human/H = make_person(null)
	var/obj/item/multi = give_tool(H, /obj/item/multitool)
	TEST_ASSERT(!paths_click_ran(H, D, multi, "wires.pulse"), "closed: a multitool does not reach the wires")
	var/obj/item/cutters = give_tool(H, /obj/item/tool/wirecutters)
	TEST_ASSERT(!paths_click_ran(H, D, cutters, "wires.cut"), "closed: nor do wirecutters")
	H.drop_item()
	TEST_ASSERT(!paths_click_ran(H, D, null, "wires_window"), "closed: nor does a hand")
	TEST_ASSERT(!p2_door_panel_open(D), "the panel is still shut")
	click(H, D, give_tool(H, /obj/item/tool/screwdriver))
	TEST_ASSERT(p2_door_panel_open(D), "panel open")
	multi = give_tool(H, /obj/item/multitool)
	TEST_ASSERT_EQUAL(paths_winner_key(H, D, multi), "wires.pulse", "open: a multitool reaches the wires")
	cutters = give_tool(H, /obj/item/tool/wirecutters)
	TEST_ASSERT_EQUAL(paths_winner_key(H, D, cutters), "wires.cut", "open: so do wirecutters")
	H.drop_item()
	TEST_ASSERT_EQUAL(paths_winner_key(H, D, null), "wires_window", "open: a hand opens the wires window")

// ---------------------------------------------------------------------------------------------------------------------
// A locker
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_paths_locker
	var/list/made

/datum/unit_test/dq_paths_locker/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, locate(T.x + 1, T.y, T.z))
	H.enable_godmode()
	var/obj/item/thing = allocate(/obj/item/tool/screwdriver, H.loc)
	TEST_ASSERT(!C.opened, "the locker starts shut")
	H.put_in_active_hand(thing)
	TEST_ASSERT(!paths_click_ran(H, C, thing, "set_down"), "shut: a held thing is not set down inside")
	TEST_ASSERT(H.is_in_hands(thing), "shut: the thing stays in hand")
	H.drop_item()
	thing.forceMove(H.loc)
	test_click(H, C, null)
	test_time(5 SECONDS)
	TEST_ASSERT(C.opened, "a hand opens it")
	H.put_in_active_hand(thing)
	TEST_ASSERT_EQUAL(paths_winner_key(H, C, thing), "set_down", "open: a held thing is set down inside")
	test_click(H, C, thing)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(thing.loc, C.loc, "it lands on the locker's tile")
	var/obj/item/welder = allocate(/obj/item/weldingtool, H.loc)
	H.put_in_active_hand(welder)
	TEST_ASSERT_EQUAL(paths_winner_key(H, C, welder), "cut_apart", "open: a welder cuts it apart")
	H.drop_item()
	test_click(H, C, null)
	test_time(5 SECONDS)
	TEST_ASSERT(!C.opened, "a hand shuts it")
	H.put_in_active_hand(welder)
	TEST_ASSERT_NOTEQUAL(paths_winner_key(H, C, welder), "cut_apart", "shut: the welder does not cut it apart")
	TEST_ASSERT(!QDELETED(C), "the locker stands")
	own_turf_contents(T)
	own_turf_contents(H.loc)
	test_driver_end()
