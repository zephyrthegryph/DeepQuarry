// Clicks on table-top machines through the real input path: a wrench bolts and unbolts every kind, the hot plate and condenser answer an empty hand and a beaker.

/// A machine made the way a map makes it (mapload TRUE), so it starts bolted.
/datum/unit_test/dq_p2_reagents/proc/tt_map_made(path)
	var/list/made = list()
	SSatoms.map_loader_begin("dq_tabletop_clicks")
	made += new path(run_loc_floor_bottom_left)
	SSatoms.map_loader_stop("dq_tabletop_clicks")
	SSatoms.InitializeAtoms(made.Copy())
	return made[1]

/datum/unit_test/dq_p2_reagents/dq_tabletop_wrench_bolts_and_unbolts

/datum/unit_test/dq_p2_reagents/dq_tabletop_wrench_bolts_and_unbolts/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/path in list(/obj/machinery/chem_hot_plate, /obj/machinery/chem_condenser, /obj/machinery/optable, /obj/machinery/processor))
		var/obj/machinery/M = tt_map_made(path)
		TEST_ASSERT(M.anchored, "[path]: a map-made one starts bolted")
		var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, run_loc_floor_bottom_left)
		var/list/rows = list()
		for(var/list/row in action_options(H, M, W))
			rows += "[row["key"]]=[row["enabled"]]/[row["reason"]]"
		rc_click(H, M, W)
		TEST_ASSERT(!M.anchored, "[path]: a wrench unbolts it (result [rc_last_click ? "[rc_last_click.key] [rc_last_click.outcome] [rc_last_click.reason]" : "none"]; options [jointext(rows, ", ")]; powered [M.operable()])")
		rc_click(H, M, W)
		TEST_ASSERT(M.anchored, "[path]: a wrench bolts it again ([rc_last_click?.reason])")
		qdel(M)

/datum/unit_test/dq_p2_reagents/dq_tabletop_hot_plate_clicks

/datum/unit_test/dq_p2_reagents/dq_tabletop_hot_plate_clicks/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_hot_plate/P = tt_map_made(/obj/machinery/chem_hot_plate)
	TEST_ASSERT(P.anchored, "a map-made plate is bolted")
	// bolted: a beaker is placed
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, P, B)
	TEST_ASSERT_EQUAL(P.held_container, B, "bolted, a beaker click stands it on the plate ([rc_last_click?.reason])")
	// bolted, a beaker on it: an alternate click opens the window and leaves the beaker; an empty hand takes the beaker into the hand, with no window
	rc_click_alt(H, P)
	TEST_ASSERT_EQUAL(rc_last_click?.key, "open_window_alt", "an alternate click opens the window ([rc_last_click ? "[rc_last_click.key] [rc_last_click.outcome] [rc_last_click.reason]" : "none"])")
	TEST_ASSERT_EQUAL(P.held_container, B, "and leaves the beaker on the plate")
	test_prompts_reset()
	rc_click(H, P, null)
	TEST_ASSERT_EQUAL(rc_last_click?.key, "hand_plate", "an empty hand on a plate with a beaker takes it off ([rc_last_click ? "[rc_last_click.key] [rc_last_click.outcome] [rc_last_click.reason]" : "none"])")
	TEST_ASSERT_NULL(P.held_container, "the beaker leaves the plate")
	TEST_ASSERT_EQUAL(B.loc, H, "into the hand")
	TEST_ASSERT(!length(GLOB.test_prompts), "with no question asked")
	// bolted, nothing on it: an empty hand opens the window
	H.drop_item()
	rc_click(H, P, null)
	TEST_ASSERT_EQUAL(rc_last_click?.key, "hand_plate", "an empty hand on a bare plate opens the window ([rc_last_click ? "[rc_last_click.key] [rc_last_click.outcome] [rc_last_click.reason]" : "none"])")
	// unbolted: an empty hand picks it up, a beaker is refused with a reason
	P.set_anchored(FALSE)
	rc_click(H, P, null)
	TEST_ASSERT(locate(/obj/item/tabletop_pack) in H.contents, "unbolted, an empty hand picks it up ([rc_last_click?.reason])")

/datum/unit_test/dq_p2_reagents/dq_tabletop_condenser_clicks

/datum/unit_test/dq_p2_reagents/dq_tabletop_condenser_clicks/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_condenser/C = tt_map_made(/obj/machinery/chem_condenser)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	rc_click(H, C, B)
	TEST_ASSERT_EQUAL(C.held_container, B, "bolted, a beaker click stands it under the spout ([rc_last_click?.reason])")
	rc_click(H, C, null)
	TEST_ASSERT_NULL(C.held_container, "bolted, an empty hand takes it back ([rc_last_click?.reason])")
	C.set_anchored(FALSE)
	rc_click(H, C, null)
	TEST_ASSERT(locate(/obj/item/tabletop_pack) in H.contents, "unbolted, an empty hand picks it up ([rc_last_click?.reason])")

// ---- Examining what is inside a container ----

/// An item that remembers who examined it.
/obj/item/dq_examine_probe
	name = "examine probe"
	var/mob/examined_by

/// A shift click reaches an atom here (a test mob has no client, so the examine itself is not run by it); the examine verb reaches examine().
/obj/item/dq_examine_probe/inspected_by(mob/user)
	examined_by = user
	return ..()

/obj/item/dq_examine_probe/examine(mob/user)
	. = ..()
	examined_by = user

/datum/unit_test/dq_p2_reagents/dq_storage_slot_shift_click_examines

/datum/unit_test/dq_p2_reagents/dq_storage_slot_shift_click_examines/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack, run_loc_floor_bottom_left)
	var/obj/item/dq_examine_probe/probe = allocate(/obj/item/dq_examine_probe, run_loc_floor_bottom_left)
	bag.handle_item_insertion(probe, TRUE)
	TEST_ASSERT_EQUAL(probe.loc, bag, "the probe is in the bag")
	var/atom/movable/storage_slot/slot = allocate(/atom/movable/storage_slot, null, probe)
	H.drop_item()
	STATE_SET(H, cooldowns, next_click, 0)
	input_submit(new /datum/input_event/click(H, slot, null, null, "left=1;shift=1"))
	rc_settle()
	TEST_ASSERT_EQUAL(probe.examined_by, H, "a shift click on its slot examines the stored item")
	TEST_ASSERT_EQUAL(probe.loc, bag, "and does not take it out")
	probe.examined_by = null
	STATE_SET(H, cooldowns, next_click, 0)
	input_submit(new /datum/input_event/click(H, probe, null, null, "left=1;shift=1"))
	rc_settle()
	TEST_ASSERT_EQUAL(probe.examined_by, H, "a shift click on the stored item itself examines it")
	probe.examined_by = null
	H.examinate(probe)
	TEST_ASSERT_EQUAL(probe.examined_by, H, "the examine verb reaches it")
