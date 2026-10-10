// fw-gaps3 content pins for the input kinds (drag-onto, alt-click, telekinesis, use-in-hand): written on the legacy interactions first,
// kept through the conversion to ops (doc/rewrite/intended_changes.md, "fw-gaps3 content").

/datum/unit_test/dq_fwg3
	abstract_type = /datum/unit_test/dq_fwg3

/datum/unit_test/dq_fwg3/Run()
	test_driver_begin()
	run_fwg3()
	test_driver_end()

/datum/unit_test/dq_fwg3/proc/run_fwg3()
	return

/// A conscious person with hands.
/datum/unit_test/dq_fwg3/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// The menu row of `target` labelled `label` for `actor`, picked from the final menu.
/datum/unit_test/dq_fwg3/proc/menu_pick(mob/actor, atom/target, label)
	for(var/list/row in action_options(actor, target, actor.get_active_hand()))
		if(row["label"] == label)
			return test_menu(actor, target, row["key"])
	TEST_FAIL("no menu row \"[label]\" on [target]")

/datum/unit_test/dq_fwg3/proc/menu_has(mob/actor, atom/target, label)
	for(var/list/row in action_options(actor, target, actor.get_active_hand()))
		if(row["label"] == label)
			return TRUE
	return FALSE

/// A player's drag (the adapter's path: ops first, then the legacy gesture entries and MouseDrop_T).
/datum/unit_test/dq_fwg3/proc/player_drag(mob/actor, atom/dragged, atom/over)
	var/datum/input_adapter/adapter = actor.input_adapter()
	adapter.drag(actor, dragged, over, get_turf(dragged), get_turf(over), null, null, "")
	test_time(1)

/// A player's click (ClickOn: the telekinesis adapter at range, as a player's click reaches it).
/datum/unit_test/dq_fwg3/proc/player_click(mob/actor, atom/target)
	COOLDOWN_RESET(actor, next_click)
	input_submit(new /datum/input_event/click(actor, target, null, null, "left=1"))
	test_time(1)

/// Cryo cell: a body dragged onto it goes inside; with the panel open the hand is refused; a beaker click loads it; the menu ejects.
/datum/unit_test/dq_fwg3/cryo_cell
/datum/unit_test/dq_fwg3/cryo_cell/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/mob/living/carbon/human/patient = person(T)
	var/obj/machinery/atmospherics/unary/cryo_cell/cell = allocate(/obj/machinery/atmospherics/unary/cryo_cell, T)
	cell.node = allocate(/obj/machinery/atmospherics/pipe/simple/visible, T) // put_mob() wants a pipe network; the cell's own one is not built on the test block
	TEST_ASSERT(cell.operable(), "the cell works")
	player_drag(H, patient, cell)
	TEST_ASSERT_EQUAL(cell.slot_item(OCCUPANT_SLOT_CRYO), patient, "the dragged body is the occupant")
	menu_pick(H, cell, "Eject")
	TEST_ASSERT_NULL(cell.slot_item(OCCUPANT_SLOT_CRYO), "the menu's eject lets the occupant out")
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker, T)
	H.put_in_active_hand(B)
	test_click(H, cell, B)
	TEST_ASSERT_EQUAL(cell.beaker, B, "a beaker click loads the beaker")
	var/obj/item/reagent_containers/glass/beaker/B2 = allocate(/obj/item/reagent_containers/glass/beaker, T)
	H.put_in_active_hand(B2)
	test_click(H, cell, B2)
	TEST_ASSERT_EQUAL(B2.loc, H, "a second beaker is refused and stays in hand")
	// a pen is swallowed (the old attackby never called its parent): nothing moves
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	H.drop_item()
	H.put_in_active_hand(P)
	test_click(H, cell, P)
	TEST_ASSERT_EQUAL(P.loc, H, "an unrelated item stays in hand")
	// a non-human dragged onto it is not taken
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	player_drag(H, M, cell)
	TEST_ASSERT_NULL(cell.slot_item(OCCUPANT_SLOT_CRYO), "a mouse is not put inside")
	// move inside from the menu
	menu_pick(patient, cell, "Move Inside")
	TEST_ASSERT_EQUAL(cell.slot_item(OCCUPANT_SLOT_CRYO), patient, "Move Inside puts the actor in")

/// Body scanner: a human dragged onto it goes inside; with the panel open the drag is refused; the menu ejects.
/datum/unit_test/dq_fwg3/body_scanner
/datum/unit_test/dq_fwg3/body_scanner/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/mob/living/carbon/human/patient = person(T)
	var/obj/machinery/bodyscanner/S = allocate(/obj/machinery/bodyscanner, T)
	S.set_panel_open(TRUE)
	player_drag(H, patient, S)
	TEST_ASSERT_NULL(S.slot_item(OCCUPANT_SLOT_BODY_SCANNER), "with the panel open nobody goes in")
	S.set_panel_open(FALSE)
	player_drag(H, patient, S)
	TEST_ASSERT_EQUAL(S.slot_item(OCCUPANT_SLOT_BODY_SCANNER), patient, "the dragged human is the occupant")
	var/mob/living/carbon/human/other = person(T)
	player_drag(H, other, S)
	TEST_ASSERT_EQUAL(S.slot_item(OCCUPANT_SLOT_BODY_SCANNER), patient, "an occupied scanner takes nobody else")
	menu_pick(H, S, "Eject")
	TEST_ASSERT_NULL(S.slot_item(OCCUPANT_SLOT_BODY_SCANNER), "the menu's eject empties it")

/// Reagent tanks: alt-click opens and closes the input; the menu sets the transfer amount (a choice question); a water cooler's hand gives a cup.
/datum/unit_test/dq_fwg3/reagent_dispenser
/datum/unit_test/dq_fwg3/reagent_dispenser/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank, T)
	TEST_ASSERT(!(tank.flags & OPENCONTAINER), "the input starts closed")
	test_click(H, tank, null, GESTURE_ALT)
	TEST_ASSERT(tank.flags & OPENCONTAINER, "alt-click opens the input")
	TEST_ASSERT(tank.open_top, "and marks the top open")
	test_click(H, tank, null, GESTURE_ALT)
	TEST_ASSERT(!(tank.flags & OPENCONTAINER), "alt-click again closes it")
	H.set_stat(UNCONSCIOUS)
	test_click(H, tank, null, GESTURE_ALT)
	TEST_ASSERT(!(tank.flags & OPENCONTAINER), "an unconscious actor opens nothing")
	H.set_stat(CONSCIOUS)
	menu_pick(H, tank, "Set transfer amount")
	test_answer(H, 50)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(tank.amount_per_transfer_from_this, 50, "the answered amount is set")
	var/obj/structure/reagent_dispensers/watertank/fixed = allocate(/obj/structure/reagent_dispensers/watertank, T)
	fixed.possible_transfer_amounts = null
	TEST_ASSERT(!menu_has(H, fixed, "Set transfer amount"), "a tank with no amounts offers no setting")
	var/obj/structure/reagent_dispensers/water_cooler/cooler = allocate(/obj/structure/reagent_dispensers/water_cooler, T)
	cooler.cups = 2
	test_click(H, cooler, null)
	TEST_ASSERT_EQUAL(cooler.cups, 1, "the cooler's hand gives a cup")
	var/found = 0
	for(var/obj/item/reagent_containers/food/drinks/sillycup/C in T)
		found++
	TEST_ASSERT_EQUAL(found, 1, "one cup is on the floor")
	for(var/obj/item/reagent_containers/food/drinks/sillycup/C in T)
		qdel(C)

/// Bedsheets: use in hand lays the sheet out (drops it, over the mob layer) and again tucks it back; a pillow's own use replaces it.
/datum/unit_test/dq_fwg3/bedsheet
/datum/unit_test/dq_fwg3/bedsheet/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/bedsheet/S = allocate(/obj/item/bedsheet, T)
	H.put_in_active_hand(S)
	test_click(H, S, S, GESTURE_SELF)
	TEST_ASSERT_EQUAL(S.loc, T, "use in hand drops the sheet")
	TEST_ASSERT_EQUAL(S.layer, ABOVE_MOB_LAYER, "laid out over the mob layer")
	H.put_in_active_hand(S)
	test_click(H, S, S, GESTURE_SELF)
	TEST_ASSERT_EQUAL(S.layer, ABOVE_MOB_LAYER, "used from the hand again it is laid out again (picking it up resets its layer)")
	var/obj/item/bedsheet/pillow/P = allocate(/obj/item/bedsheet/pillow, T)
	H.put_in_active_hand(P)
	test_click(H, P, P, GESTURE_SELF)
	TEST_ASSERT_EQUAL(P.loc, T, "a pillow's use drops it")
	TEST_ASSERT_EQUAL(P.icon_state, "[initial(P.icon_state)]_placed", "and places it, not the sheet's layering")
	TEST_ASSERT(P.layer != ABOVE_MOB_LAYER, "the sheet's own layering did not also run")

/// Linen bin: the hand takes a sheet; telekinesis at range pulls one out onto the bin's tile.
/datum/unit_test/dq_fwg3/bedsheet_bin
/datum/unit_test/dq_fwg3/bedsheet_bin/run_fwg3()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/away = locate(home.x + 3, home.y, home.z)
	var/mob/living/carbon/human/H = person(home)
	var/obj/structure/bedsheetbin/bin = allocate(/obj/structure/bedsheetbin, home)
	var/start = bin.amount
	test_click(H, bin, null)
	TEST_ASSERT_EQUAL(bin.amount, start - 1, "the hand takes a sheet")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/bedsheet), "into the hand")
	var/obj/structure/bedsheetbin/far = allocate(/obj/structure/bedsheetbin, away)
	var/far_start = far.amount
	test_click(H, far, null)
	TEST_ASSERT_EQUAL(far.amount, far_start, "without telekinesis nothing reaches three tiles")
	H.add_mutation(TK)
	H.drop_item()
	player_click(H, far)
	TEST_ASSERT_EQUAL(far.amount, far_start - 1, "telekinesis pulls a sheet out")
	var/obj/item/bedsheet/pulled = locate() in away
	TEST_ASSERT_NOTNULL(pulled, "onto the bin's own tile")
	H.remove_mutation(TK)
	for(var/obj/item/bedsheet/B in home.contents + away.contents + H.contents)
		qdel(B)

/// Inflatables: use in hand inflates on the actor's tile; the structure's menu deflates it to a folded wall after the hiss; a torn one cannot be inflated.
/datum/unit_test/dq_fwg3/inflatable
/datum/unit_test/dq_fwg3/inflatable/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/item/inflatable/I = allocate(/obj/item/inflatable, T)
	H.put_in_active_hand(I)
	test_click(H, I, I, GESTURE_SELF)
	var/obj/structure/inflatable/W = locate(/obj/structure/inflatable) in T
	TEST_ASSERT_NOTNULL(W, "use in hand inflates a wall on the actor's tile")
	TEST_ASSERT(QDELETED(I), "the folded wall is used up")
	menu_pick(H, W, "Deflate")
	TEST_ASSERT(W.deflating, "Deflate starts the deflation")
	test_time(6 SECONDS)
	TEST_ASSERT(QDELETED(W), "the wall is gone after the hiss")
	TEST_ASSERT_NOTNULL(locate(/obj/item/inflatable) in T, "a folded wall is left")
	var/obj/item/inflatable/door/D = allocate(/obj/item/inflatable/door, T)
	H.put_in_active_hand(D)
	test_click(H, D, D, GESTURE_SELF)
	var/obj/structure/inflatable/door/door = locate(/obj/structure/inflatable/door) in T
	TEST_ASSERT_NOTNULL(door, "an inflatable door inflates")
	for(var/atom/movable/AM in T)
		if(istype(AM, /obj/item/inflatable) || istype(AM, /obj/structure/inflatable))
			qdel(AM)

/// Filing cabinet: an empty one refuses the hand; a records cabinet fills itself first, then opens; telekinesis rummages in an anchored one at range.
/datum/unit_test/dq_fwg3/filing_cabinet
/datum/unit_test/dq_fwg3/filing_cabinet/run_fwg3()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/away = locate(home.x + 3, home.y, home.z)
	var/mob/living/carbon/human/H = person(home)
	var/obj/structure/filingcabinet/F = allocate(/obj/structure/filingcabinet, home)
	var/datum/op_result/R = test_click(H, F, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "an empty cabinet refuses the hand")
	var/obj/item/paper/P = allocate(/obj/item/paper, home)
	H.put_in_active_hand(P)
	test_click(H, F, P)
	TEST_ASSERT_EQUAL(P.loc, F, "a paper is filed")
	R = test_click(H, F, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "a cabinet with files opens")
	var/obj/structure/filingcabinet/far = allocate(/obj/structure/filingcabinet, away)
	far.set_anchored(TRUE)
	H.add_mutation(TK)
	R = test_click(H, far, null)
	TEST_ASSERT_EQUAL(R?.outcome, ACT_COMMITTED, "telekinesis rummages in an anchored cabinet at range")
	H.remove_mutation(TK)
