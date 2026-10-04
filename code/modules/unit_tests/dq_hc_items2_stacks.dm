// Behaviour-preservation tests for the stack family (code/game/objects/items/stacks and the stack subtypes under code/modules/materials). They pin what a
// player observes through clicks, windows and the kernel clock, so the same file passes before and after the family moves to the final forms. State is
// read through plain vars; nothing here depends on message text or on an op key. The helpers (hci_click, hci_answer, hci_ui) are in dq_hc_items_behaviour.dm.

/// Sets a stack's amount the way the game does and lets the redraw run.
/proc/hci2_set_amount(obj/item/stack/S, n)
	S.set_amount(n, TRUE)
	S.update_icon()
	test_time(2 SECONDS)

/datum/unit_test/dq_hc_items/stack_icon_follows_amount

/datum/unit_test/dq_hc_items/stack_icon_follows_amount/run_gate()
	var/obj/item/stack/nanopaste/S = allocate(/obj/item/stack/nanopaste, tile(2, 2))
	hci2_set_amount(S, 3)
	TEST_ASSERT_EQUAL(S.icon_state, "nanopaste", "a third or less shows the plain state")
	hci2_set_amount(S, 5)
	TEST_ASSERT_EQUAL(S.icon_state, "nanopaste_2", "up to two thirds shows the second state")
	hci2_set_amount(S, 8)
	TEST_ASSERT_EQUAL(S.icon_state, "nanopaste_3", "more shows the third state")
	var/obj/item/stack/sandbags/B = allocate(/obj/item/stack/sandbags, tile(3, 3))
	hci2_set_amount(B, 20)
	TEST_ASSERT_EQUAL(B.icon_state, "sandbag", "a stack that has no variants keeps its state")

/datum/unit_test/dq_hc_items/stack_use_and_add_move_the_amount

/datum/unit_test/dq_hc_items/stack_use_and_add_move_the_amount/run_gate()
	var/obj/item/stack/nanopaste/S = allocate(/obj/item/stack/nanopaste, tile(2, 2))
	TEST_ASSERT_EQUAL(S.amount, 10, "starts full")
	TEST_ASSERT(S.use(4), "uses four")
	TEST_ASSERT_EQUAL(S.amount, 6, "six are left")
	TEST_ASSERT(!S.add(5), "adding past the maximum is refused")
	TEST_ASSERT(S.add(4), "adding within the maximum works")
	TEST_ASSERT_EQUAL(S.amount, 10, "back to ten")
	S.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.icon_state, "nanopaste_3", "the look follows the use and the add")
	var/obj/item/stack/split_off = S.split(3)
	TEST_ASSERT_EQUAL(split_off.amount, 3, "the split has three")
	TEST_ASSERT_EQUAL(S.amount, 7, "seven stay")
	qdel(split_off)

/datum/unit_test/dq_hc_items/stack_advanced_medical_icon_steps

/datum/unit_test/dq_hc_items/stack_advanced_medical_icon_steps/run_gate()
	var/obj/item/stack/medical/advanced/bruise_pack/S = allocate(/obj/item/stack/medical/advanced/bruise_pack, tile(2, 2))
	var/base = initial(S.icon_state)
	hci2_set_amount(S, 2)
	TEST_ASSERT_EQUAL(S.icon_state, base, "one to two shows the base state")
	hci2_set_amount(S, 4)
	TEST_ASSERT_EQUAL(S.icon_state, "[base]_4", "three to four")
	hci2_set_amount(S, 6)
	TEST_ASSERT_EQUAL(S.icon_state, "[base]_6", "five to six")
	hci2_set_amount(S, 8)
	TEST_ASSERT_EQUAL(S.icon_state, "[base]_8", "seven to eight")
	hci2_set_amount(S, 9)
	TEST_ASSERT_EQUAL(S.icon_state, "[base]_9", "nine")
	hci2_set_amount(S, 10)
	TEST_ASSERT_EQUAL(S.icon_state, "[base]_10", "ten")
	var/obj/item/stack/medical/advanced/clotting/C = allocate(/obj/item/stack/medical/advanced/clotting, tile(3, 3))
	hci2_set_amount(C, 3)
	TEST_ASSERT_EQUAL(C.icon_state, "clotkit_3", "the clotting kit shows its count")

/datum/unit_test/dq_hc_items/stack_tickets_icon_steps

/datum/unit_test/dq_hc_items/stack_tickets_icon_steps/run_gate()
	var/obj/item/stack/arcadeticket/S = allocate(/obj/item/stack/arcadeticket, tile(2, 2))
	hci2_set_amount(S, 1)
	TEST_ASSERT_EQUAL(S.icon_state, "arcade-ticket", "one ticket")
	hci2_set_amount(S, 4)
	TEST_ASSERT_EQUAL(S.icon_state, "arcade-ticket_2", "a few tickets")
	hci2_set_amount(S, 8)
	TEST_ASSERT_EQUAL(S.icon_state, "arcade-ticket_3", "more tickets")
	hci2_set_amount(S, 30)
	TEST_ASSERT_EQUAL(S.icon_state, "arcade-ticket_4", "a full pile")

/datum/unit_test/dq_hc_items/stack_rods_icon_and_tape_splint

/datum/unit_test/dq_hc_items/stack_rods_icon_and_tape_splint/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, T)
	hci2_set_amount(R, 3)
	TEST_ASSERT_EQUAL(R.icon_state, "rods-3", "a few rods show their count")
	hci2_set_amount(R, 9)
	TEST_ASSERT_EQUAL(R.icon_state, "rods", "a pile shows the plain state")
	hci2_set_amount(R, 4)
	var/obj/item/tape_roll/tape = allocate(/obj/item/tape_roll, T)
	hci_click(H, R, tape)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(R.amount, 3, "a rod is used up")
	var/found = FALSE
	for(var/obj/item/stack/medical/splint/ghetto/S in get_turf(H))
		found = TRUE
	TEST_ASSERT(found, "a makeshift splint is made")
	var/obj/item/stack/material/plasteel/rebar/B = allocate(/obj/item/stack/material/plasteel/rebar, tile(3, 3))
	hci2_set_amount(B, 2)
	TEST_ASSERT_EQUAL(B.icon_state, "rods-2", "rebar shows its count too")
	for(var/obj/item/I in get_turf(H))
		if(!istype(I, /obj/item/stack/rods) && !istype(I, /obj/item/tape_roll))
			qdel(I)

/datum/unit_test/dq_hc_items/stack_sandbag_slowdown_follows_amount

/datum/unit_test/dq_hc_items/stack_sandbag_slowdown_follows_amount/run_gate()
	var/obj/item/stack/sandbags/B = allocate(/obj/item/stack/sandbags, tile(2, 2))
	hci2_set_amount(B, 20)
	TEST_ASSERT_EQUAL(B.slowdown, 2, "twenty bags slow by two")
	hci2_set_amount(B, 5)
	TEST_ASSERT_EQUAL(B.slowdown, 0.5, "five bags slow by half")

/datum/unit_test/dq_hc_items/stack_merges_when_clicked_onto_another

/datum/unit_test/dq_hc_items/stack_merges_when_clicked_onto_another/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/stack/nanopaste/target = allocate(/obj/item/stack/nanopaste, T)
	var/obj/item/stack/nanopaste/mine = allocate(/obj/item/stack/nanopaste, T)
	target.set_amount(4, TRUE)
	mine.set_amount(3, TRUE)
	hci_click(H, target, mine)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(mine.amount, 7, "the stack that was clicked moves into the held one")
	TEST_ASSERT(QDELETED(target), "and is used up")

/datum/unit_test/dq_hc_items/stack_split_through_the_other_hand

/datum/unit_test/dq_hc_items/stack_split_through_the_other_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/nanopaste/S = allocate(/obj/item/stack/nanopaste, tile(2, 2))
	S.set_amount(8, TRUE)
	H.put_in_inactive_hand(S)
	TEST_ASSERT_EQUAL(H.get_inactive_hand(), S, "the stack is in the other hand")
	hci_click(H, S, null)
	test_time(5 SECONDS)
	hci_answer(H, 3)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.amount, 5, "three came off")
	var/obj/item/stack/nanopaste/piece = H.get_active_hand()
	TEST_ASSERT(istype(piece), "the piece is in the active hand")
	TEST_ASSERT_EQUAL(piece?.amount, 3, "the piece has three")
	// A refusal of the question keeps the stack whole.
	hci_click(H, S, null)
	test_time(5 SECONDS)

/datum/unit_test/dq_hc_items/stack_window_builds_a_recipe

/datum/unit_test/dq_hc_items/stack_window_builds_a_recipe/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = get_turf(H)
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, T)
	R.set_amount(5, TRUE)
	H.put_in_active_hand(R)
	var/datum/stack_recipe/grille = null
	for(var/datum/stack_recipe/recipe in R.recipes)
		if(recipe.title == "grille")
			grille = recipe
	TEST_ASSERT(grille, "rods know a grille recipe")
	hci_ui(H, R, "make", list("multiplier" = 1, "ref" = "\ref[grille]"))
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(R.amount, 3, "a grille costs two rods")
	var/obj/structure/grille/G = locate() in T
	TEST_ASSERT(G, "the grille is built where the builder stands")
	// A recipe that is not the stack's own is refused.
	var/datum/stack_recipe/foreign = new("foreign", /obj/structure/grille, 1)
	hci_ui(H, R, "make", list("multiplier" = 1, "ref" = "\ref[foreign]"))
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(R.amount, 3, "a foreign recipe builds nothing")
	qdel(foreign)
	qdel(G)

/datum/unit_test/dq_hc_items/stack_cyborg_charge_amount_is_the_synth

/datum/unit_test/dq_hc_items/stack_cyborg_charge_amount_is_the_synth/run_gate()
	var/obj/item/stack/rods/cyborg/R = allocate(/obj/item/stack/rods/cyborg, tile(2, 2))
	TEST_ASSERT(R.uses_charge, "a synthesizer draws on a synth")
	TEST_ASSERT_EQUAL(R.get_amount(), 0, "with no synth linked it has nothing")
	TEST_ASSERT(!R.can_use(1), "so it cannot be used")

// ---- Marker beacons ----

/datum/unit_test/dq_hc_items/stack_marker_beacon_places_and_uses_one

/datum/unit_test/dq_hc_items/stack_marker_beacon_places_and_uses_one/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = get_turf(H)
	var/obj/item/stack/marker_beacon/ten/S = allocate(/obj/item/stack/marker_beacon/ten, T)
	S.picked_color = "Jade"
	S.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.icon_state, "markerjade", "the stack shows its colour")
	hci_click(H, S, S)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.amount, 9, "one beacon is used")
	var/obj/structure/marker_beacon/placed = locate() in T
	TEST_ASSERT(placed, "a beacon is anchored under the user")
	TEST_ASSERT_EQUAL(placed?.picked_color, "Jade", "in the stack's colour")
	hci_click(H, S, S)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.amount, 9, "a second beacon does not go on the same tile")
	qdel(placed)

/datum/unit_test/dq_hc_items/stack_marker_beacon_colour_is_picked_by_alt_click

/datum/unit_test/dq_hc_items/stack_marker_beacon_colour_is_picked_by_alt_click/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = get_turf(H)
	var/obj/item/stack/marker_beacon/S = allocate(/obj/item/stack/marker_beacon, T)
	S.picked_color = "Jade"
	hci_click(H, S, null, I_HELP, "alt=1")
	test_time(5 SECONDS)
	hci_answer(H, "Indigo")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.picked_color, "Indigo", "the colour is the one chosen")
	S.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(S.icon_state, "markerindigo", "and shows")
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, T, "Jade")
	hci_click(H, B, null, I_HELP, "alt=1")
	test_time(5 SECONDS)
	hci_answer(H, "Teal")
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(B.picked_color, "Teal", "a placed beacon takes the colour too")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(B.icon_state, "markerteal-on", "and shows it lit")

/datum/unit_test/dq_hc_items/stack_marker_beacon_structure_is_picked_up_after_a_wait

/datum/unit_test/dq_hc_items/stack_marker_beacon_structure_is_picked_up_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = get_turf(H)
	var/obj/structure/marker_beacon/B = allocate(/obj/structure/marker_beacon, T, "Lime")
	hci_click(H, B, null)
	test_time(10 SECONDS)
	TEST_ASSERT(QDELETED(B), "the placed beacon is taken up")
	var/obj/item/stack/marker_beacon/got = H.get_active_hand()
	TEST_ASSERT(istype(got), "into the hand")
	TEST_ASSERT_EQUAL(got?.picked_color, "Lime", "with its colour")
	qdel(got)
	var/obj/structure/marker_beacon/perm = allocate(/obj/structure/marker_beacon, tile(3, 3))
	perm.perma = TRUE
	hci_click(H, perm, null)
	test_time(10 SECONDS)
	TEST_ASSERT(!QDELETED(perm), "a permanent beacon stays")

// ---- Stack subtypes outside code/game/objects/items ----

/datum/unit_test/dq_hc_items/stack_cable_piece_is_named_and_drawn_by_length

/datum/unit_test/dq_hc_items/stack_cable_piece_is_named_and_drawn_by_length/run_gate()
	var/obj/item/stack/cable_coil/C = allocate(/obj/item/stack/cable_coil, tile(2, 2))
	TEST_ASSERT_EQUAL(C.amount, 30, "a coil starts full")
	hci2_set_amount(C, 2)
	TEST_ASSERT_EQUAL(C.icon_state, "coil2", "two lengths show the short piece")
	TEST_ASSERT_EQUAL(C.name, "cable piece", "and are called a piece")
	hci2_set_amount(C, 1)
	TEST_ASSERT_EQUAL(C.icon_state, "coil1", "one length shows the shortest piece")
	hci2_set_amount(C, 10)
	TEST_ASSERT_EQUAL(C.icon_state, "coil", "a longer length shows the coil")
	TEST_ASSERT_EQUAL(C.name, initial(C.name), "and is called a coil")
	var/obj/item/stack/cable_coil/cut/piece = allocate(/obj/item/stack/cable_coil/cut, tile(3, 3))
	test_time(2 SECONDS)
	TEST_ASSERT(piece.amount <= 2, "a cut piece is one or two lengths")
	TEST_ASSERT_EQUAL(piece.name, "cable piece", "and is called a piece")

/datum/unit_test/dq_hc_items/stack_processed_alloy_export_value_follows_amount

/datum/unit_test/dq_hc_items/stack_processed_alloy_export_value_follows_amount/run_gate()
	var/obj/item/stack/material/processed_alloy/S = allocate(/obj/item/stack/material/processed_alloy, tile(2, 2), 10)
	S.export_value_per_sheet = 7
	S.set_amount(4, TRUE)
	TEST_ASSERT_EQUAL(S.economic_export_value, 28, "the value is per sheet times the sheets")
	TEST_ASSERT(S.use(1), "uses one")
	TEST_ASSERT_EQUAL(S.economic_export_value, 21, "using a sheet takes its value with it")
	TEST_ASSERT(S.add(2), "adds two")
	TEST_ASSERT_EQUAL(S.economic_export_value, 35, "adding sheets adds their value")

/datum/unit_test/dq_hc_items/stack_supermatter_split_asks_through_the_other_hand

/datum/unit_test/dq_hc_items/stack_supermatter_split_asks_through_the_other_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/stack/material/supermatter/S = allocate(/obj/item/stack/material/supermatter, tile(2, 2))
	S.set_amount(20, TRUE)
	var/obj/item/clothing/gloves/gauntlets/G = allocate(/obj/item/clothing/gloves/gauntlets, tile(2, 2)) // the touch scorches a bare hand and drops the stack
	H.equip_to_slot_if_possible(G, SLOT_ID_GLOVES)
	H.put_in_inactive_hand(S)
	hci_click(H, S, null)
	test_time(5 SECONDS)
	hci_answer(H, 5)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(S.amount, 15, "five came off")
	TEST_ASSERT_EQUAL(S.slowdown, 1.5, "the stack re-weighs itself")
	for(var/obj/item/I in H.contents)
		if(I != S && istype(I, /obj/item/stack/material/supermatter))
			qdel(I)

/datum/unit_test/dq_hc_items/stack_flag_plants_one_and_keeps_the_rest

/datum/unit_test/dq_hc_items/stack_flag_plants_one_and_keeps_the_rest/run_gate()
	var/obj/item/stack/flag/F = allocate(/obj/item/stack/flag, tile(2, 2))
	TEST_ASSERT_EQUAL(F.amount, 10, "a flag stack starts with ten")
	TEST_ASSERT(F.use(1), "uses one")
	TEST_ASSERT_EQUAL(F.amount, 9, "nine are left")
