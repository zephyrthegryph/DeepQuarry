// Table-top machines are portable and need bolting (code/content/machinery/tabletop.dm): loose, an empty hand picks the machine up with everything it holds;
// bolted, a click uses it as before; loose, it does not work. The bulky ones (operating table, ice cream vat, processors) are never picked up.

/// The portable kinds.
#define DQ_TABLETOP_PORTABLE list(/obj/machinery/chem_hot_plate, /obj/machinery/chem_condenser, /obj/machinery/bunsen_burner, /obj/machinery/scale, /obj/machinery/microscope, /obj/machinery/libraryscanner, /obj/machinery/bookbinder, /obj/machinery/gear_painter, /obj/machinery/radiocarbon_spectrometer)
/// The bulky kinds.
#define DQ_TABLETOP_BULKY list(/obj/machinery/optable, /obj/machinery/icecream_vat, /obj/machinery/processor, /obj/machinery/processor/monkey)

/// The pack the actor holds, if any.
/datum/unit_test/dq_p2_reagents/proc/dq_tt_pack_in_hand(mob/living/carbon/human/H)
	for(var/obj/item/tabletop_pack/P in H.contents)
		return P
	return null

/// A loose machine of every portable kind is picked up by an empty hand: it is in a pack in the hand, not on the floor.
/datum/unit_test/dq_p2_reagents/dq_tabletop_loose_machine_is_picked_up

/datum/unit_test/dq_p2_reagents/dq_tabletop_loose_machine_is_picked_up/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/path in DQ_TABLETOP_PORTABLE)
		var/obj/machinery/M = allocate(path, run_loc_floor_bottom_left)
		M.set_anchored(FALSE)
		rc_click(H, M, null)
		var/obj/item/tabletop_pack/P = dq_tt_pack_in_hand(H)
		TEST_ASSERT_NOTNULL(P, "[path]: an empty hand picks a loose one up ([rc_last_click?.reason])")
		TEST_ASSERT_EQUAL(P.machine, M, "[path]: the pack holds the machine itself")
		TEST_ASSERT_EQUAL(M.loc, P, "[path]: the machine is inside the pack, not on the floor")
		qdel(P)

/// What a hot plate held and was set to is still there after it is picked up and set down, and it is still loose; it works only once it is bolted again.
/datum/unit_test/dq_p2_reagents/dq_tabletop_contents_and_settings_survive_the_carry

/datum/unit_test/dq_p2_reagents/dq_tabletop_contents_and_settings_survive_the_carry/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	TEST_ASSERT(move_into(P, nameof(P.held_container), B), "the beaker stands on the plate")
	P.set_dial(T0C + 90)
	rc_click(H, P, null)
	var/obj/item/tabletop_pack/pack = dq_tt_pack_in_hand(H)
	TEST_ASSERT_NOTNULL(pack, "the loose plate is picked up")
	TEST_ASSERT_EQUAL(P.held_container, B, "the beaker stays on the plate while it is carried")
	TEST_ASSERT_EQUAL(B.loc, P, "inside it")
	TEST_ASSERT(!P.operable(), "a carried machine does not work")
	rc_use(H, pack)
	TEST_ASSERT(QDELETED(pack), "the pack is used up when the machine is set down")
	TEST_ASSERT(isturf(P.loc), "the plate is on the floor again")
	TEST_ASSERT_EQUAL(P.held_container, B, "with its beaker")
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_WATER), 30, "and what is in it")
	TEST_ASSERT(dq_pur_near(P.target_temp, T0C + 90, 0.01), "at the dial it was set to")
	TEST_ASSERT(!P.anchored, "it is still loose")
	TEST_ASSERT(!P.operable(), "so it still does not work")
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	TEST_ASSERT(P.operable(), "bolted down it works")

/// A pack set down by clicking a floor tile with it puts the machine on that tile.
/datum/unit_test/dq_p2_reagents/dq_tabletop_pack_sets_down_on_a_clicked_tile

/datum/unit_test/dq_p2_reagents/dq_tabletop_pack_sets_down_on_a_clicked_tile/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, run_loc_floor_bottom_left)
	rc_click(H, C, null)
	var/obj/item/tabletop_pack/pack = dq_tt_pack_in_hand(H)
	TEST_ASSERT_NOTNULL(pack, "the loose condenser is picked up")
	var/turf/there = get_step(run_loc_floor_bottom_left, NORTH)
	rc_click(H, there, pack)
	TEST_ASSERT_EQUAL(C.loc, there, "clicking the next tile with the pack sets the condenser down there ([rc_last_click?.reason])")
	TEST_ASSERT(QDELETED(pack), "and the pack is gone")

/// A packed machine draws nothing and belongs to no area's power; set down, it joins the area it is set down in.
/datum/unit_test/dq_p2_reagents/dq_tabletop_packed_machine_draws_no_power

/datum/unit_test/dq_p2_reagents/dq_tabletop_packed_machine_draws_no_power/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/turf/T = run_loc_floor_bottom_left
	var/area/here = get_area(T)
	var/before = stat_value(here, STAT_DEMAND_EQUIP) || 0
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, T)
	P.set_anchored(FALSE)
	TEST_ASSERT_EQUAL(P.power_area, here, "a plate on the floor belongs to its area's power")
	var/loose = stat_value(here, STAT_DEMAND_EQUIP) || 0
	TEST_ASSERT(loose > before, "and its idle draw is in the area's demand")
	rc_click(H, P, null)
	var/obj/item/tabletop_pack/pack = dq_tt_pack_in_hand(H)
	TEST_ASSERT_NOTNULL(pack, "the loose plate is picked up")
	TEST_ASSERT_NULL(P.power_area, "packed, it belongs to no area's power")
	TEST_ASSERT(!(P in here.power_machines), "it is not among the area's power machines")
	TEST_ASSERT_EQUAL(stat_value(here, STAT_DEMAND_EQUIP) || 0, before, "and the area's demand is as it was without it")
	// The pack moves to another area with the machine inside: still nothing registered.
	var/area/other = null
	for(var/area/A in world)
		if(A != here && length(A.contents))
			other = A
			break
	if(other)
		var/turf/far = locate(/turf) in other
		if(far)
			pack.forceMove(far)
			TEST_ASSERT_NULL(P.power_area, "carried into another area it still belongs to none")
			pack.forceMove(H)
	rc_use(H, pack)
	TEST_ASSERT(isturf(P.loc), "the plate is set down")
	TEST_ASSERT_EQUAL(P.power_area, get_area(P), "set down, it joins the power of the area it stands in")
	TEST_ASSERT_EQUAL(stat_value(here, STAT_DEMAND_EQUIP) || 0, loose, "and its draw is back in the demand")

/// The pack looks like the machine inside it, the beaker on a hot plate included.
/datum/unit_test/dq_p2_reagents/dq_tabletop_pack_look_shows_the_machine

/datum/unit_test/dq_p2_reagents/dq_tabletop_pack_look_shows_the_machine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, run_loc_floor_bottom_left)
	P.set_anchored(FALSE)
	rc_click(H, P, null)
	var/obj/item/tabletop_pack/pack = dq_tt_pack_in_hand(H)
	TEST_ASSERT_NOTNULL(pack, "the loose plate is picked up")
	draw_now(P)
	draw_now(pack)
	TEST_ASSERT_EQUAL(pack.icon, P.icon, "the pack wears the plate's icon")
	TEST_ASSERT_EQUAL(pack.icon_state, P.icon_state, "and its state")
	var/bare = length(pack.overlays)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	TEST_ASSERT(move_into(P, nameof(P.held_container), B), "a beaker is put on the packed plate")
	draw_now(P)
	draw_now(pack)
	TEST_ASSERT(length(pack.overlays) > bare, "the pack now shows the beaker ([length(pack.overlays)] overlays, was [bare])")
	TEST_ASSERT_EQUAL(length(pack.overlays), length(P.overlays), "exactly what the plate shows")

/// Bolted, an empty hand uses the machine instead of picking it up: a condenser gives its container back.
/datum/unit_test/dq_p2_reagents/dq_tabletop_bolted_machine_is_used_not_picked_up

/datum/unit_test/dq_p2_reagents/dq_tabletop_bolted_machine_is_used_not_picked_up/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, run_loc_floor_bottom_left)
	C.set_anchored(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	TEST_ASSERT(move_into(C, nameof(C.held_container), B), "the beaker stands under the spout")
	rc_click(H, C, null)
	TEST_ASSERT_NULL(dq_tt_pack_in_hand(H), "a bolted condenser is not picked up")
	TEST_ASSERT(isturf(C.loc), "it stays where it is bolted")
	TEST_ASSERT_NULL(C.held_container, "the click took the container as it always did")
	TEST_ASSERT_EQUAL(B.loc, H, "into the hand")

/// A loose machine does not work; bolted it does.
/datum/unit_test/dq_tabletop_loose_machine_does_not_work

/datum/unit_test/dq_tabletop_loose_machine_does_not_work/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, T)
	P.set_powered(TRUE)
	P.set_anchored(FALSE)
	TEST_ASSERT(!P.operable(), "a loose hot plate is not operable")
	P.switch_element(null, TRUE)
	TEST_ASSERT(!P.heating, "it cannot be switched on")
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, T)
	C.set_powered(TRUE)
	C.set_anchored(FALSE)
	var/obj/item/reagent_containers/glass/beaker/receiver = allocate(/obj/item/reagent_containers/glass/beaker, T)
	move_into(C, nameof(C.held_container), receiver)
	TEST_ASSERT(!C.collect(list(REAGENT_ID_WATER = list(5, null))), "a loose condenser collects nothing")
	P.set_anchored(TRUE)
	C.set_anchored(TRUE)
	TEST_ASSERT(P.operable(), "a bolted hot plate works")
	P.switch_element(null, TRUE)
	TEST_ASSERT(P.heating, "and switches on")
	TEST_ASSERT(C.collect(list(REAGENT_ID_WATER = list(5, null))), "a bolted condenser collects")
	for(var/path in DQ_TABLETOP_PORTABLE + DQ_TABLETOP_BULKY)
		var/obj/machinery/M = allocate(path, T)
		M.set_powered(TRUE)
		M.set_anchored(FALSE)
		TEST_ASSERT(!M.operable(), "[path]: loose, it does not work")
		M.set_anchored(TRUE)
		TEST_ASSERT(M.operable(), "[path]: bolted, it works")

/// The bulky machines are never picked up, loose or not.
/datum/unit_test/dq_p2_reagents/dq_tabletop_bulky_machines_are_not_pickable

/datum/unit_test/dq_p2_reagents/dq_tabletop_bulky_machines_are_not_pickable/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/path in DQ_TABLETOP_BULKY)
		var/obj/machinery/M = allocate(path, run_loc_floor_bottom_left)
		M.set_anchored(FALSE)
		rc_click(H, M, null)
		TEST_ASSERT_NULL(dq_tt_pack_in_hand(H), "[path]: a loose one is not picked up")
		TEST_ASSERT(isturf(M.loc), "[path]: it stays on the floor")
		M.set_anchored(TRUE)
		rc_click(H, M, null)
		TEST_ASSERT_NULL(dq_tt_pack_in_hand(H), "[path]: a bolted one is not picked up either")
		TEST_ASSERT(isturf(M.loc), "[path]: it stays on the floor, bolted")

#undef DQ_TABLETOP_PORTABLE
#undef DQ_TABLETOP_BULKY
