// Behaviour-preservation tests for the hand-converted structures (code/game/objects/structures). They pin what a player observes through clicks,
// window buttons and the questions a structure asks, so the same file passes before and after a structure moves to the final forms. State is read
// through plain vars; nothing here depends on message text or on an op key. Helpers shared with the other hand-conversion tests:
// hci_click / hci_answer (dq_hc_items_behaviour.dm) and hc_ui / hc_data (dq_hc_computers_base.dm).

/datum/unit_test/dq_hc_struct
	abstract_type = /datum/unit_test/dq_hc_struct

/datum/unit_test/dq_hc_struct/Run()
	test_driver_begin()
	test_rng(23)
	om_scheduler().test_prompts = list()
	run_gate()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	test_driver_end()

/datum/unit_test/dq_hc_struct/proc/run_gate()
	return

/datum/unit_test/dq_hc_struct/proc/tile(dx, dy)
	return locate(run_loc_floor_bottom_left.x + dx, run_loc_floor_bottom_left.y + dy, run_loc_floor_bottom_left.z)

/datum/unit_test/dq_hc_struct/proc/settle()
	test_time(10 SECONDS)

/datum/unit_test/dq_hc_struct/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || tile(2, 2))
	H.enable_godmode()
	return H

/// A window button pressed as `actor`, and time passes.
/datum/unit_test/dq_hc_struct/proc/press(mob/actor, datum/host, action, list/args)
	. = hc_ui(actor, host, action, args)
	settle()

// ---------------------------------------------------------------------------------------------------------------------
// What a hit does to a structure
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/tree_blast_hurts_through_its_health
/datum/unit_test/dq_hc_struct/tree_blast_hurts_through_its_health/run_gate()
	var/obj/structure/flora/tree/T = allocate(/obj/structure/flora/tree, tile(3, 3))
	var/start = T.get_integrity()
	T.ex_act(2)
	TEST_ASSERT_EQUAL(T.get_integrity(), start - round(T.max_integrity / 2), "a severity 2 blast takes half the tree's integrity")
	TEST_ASSERT(!T.is_stump, "and leaves it standing")
	T.ex_act(1)
	TEST_ASSERT(T.is_stump, "a severity 1 blast fells it into a stump")

/datum/unit_test/dq_hc_struct/girder_is_pulled_apart_by_a_blob
/datum/unit_test/dq_hc_struct/girder_is_pulled_apart_by_a_blob/run_gate()
	var/obj/structure/girder/G = allocate(/obj/structure/girder, tile(3, 3))
	G.blob_act()
	TEST_ASSERT(QDELETED(G), "a blob pulls a girder apart")

/datum/unit_test/dq_hc_struct/inflatable_is_punctured_by_a_blob
/datum/unit_test/dq_hc_struct/inflatable_is_punctured_by_a_blob/run_gate()
	var/turf/T = tile(3, 3)
	var/obj/structure/inflatable/W = allocate(/obj/structure/inflatable, T)
	W.blob_act()
	TEST_ASSERT(QDELETED(W), "a blob punctures the wall")
	TEST_ASSERT(locate(/obj/item/inflatable/torn) in T, "and it leaves a torn one behind")

/datum/unit_test/dq_hc_struct/blackbox_takes_a_blast_one_step_lighter
/datum/unit_test/dq_hc_struct/blackbox_takes_a_blast_one_step_lighter/run_gate()
	var/obj/structure/prop/blackbox/B = allocate(/obj/structure/prop/blackbox, tile(3, 3))
	var/start = B.get_integrity()
	B.ex_act(3)
	TEST_ASSERT_EQUAL(B.get_integrity(), start, "a severity 3 blast does nothing")
	B.ex_act(2)
	var/after_light = B.get_integrity()
	TEST_ASSERT(after_light < start, "a severity 2 blast hurts it")
	TEST_ASSERT(!QDELETED(B), "but it stands")
	B.ex_act(1)
	TEST_ASSERT(B.get_integrity() < after_light, "a severity 1 blast hurts it more")

/datum/unit_test/dq_hc_struct/janicart_spills_its_gear_in_a_blast
/datum/unit_test/dq_hc_struct/janicart_spills_its_gear_in_a_blast/run_gate()
	var/turf/T = tile(3, 3)
	var/obj/structure/janitorialcart/C = allocate(/obj/structure/janitorialcart, T)
	var/obj/item/mop/M = allocate(/obj/item/mop, T)
	rel_set(C, nameof(C.mymop), M)
	C.ex_act(1)
	TEST_ASSERT_NULL(C.mymop, "a severity 1 blast always knocks the mop off")
	TEST_ASSERT_EQUAL(M.loc, T, "onto the floor")

/datum/unit_test/dq_hc_struct/flag_that_survives_a_blast_is_torn
/datum/unit_test/dq_hc_struct/flag_that_survives_a_blast_is_torn/run_gate()
	var/obj/structure/sign/flag/F = allocate(/obj/structure/sign/flag, tile(3, 3))
	TEST_ASSERT(!F.ripped, "starts whole")
	F.ex_act(3)
	TEST_ASSERT(F.ripped || QDELETED(F), "a blast either destroys the flag or tears it")

// ---------------------------------------------------------------------------------------------------------------------
// Emags
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/holoplant_is_emagged_once
/datum/unit_test/dq_hc_struct/holoplant_is_emagged_once/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/holoplant/P = allocate(/obj/machinery/holoplant, tile(3, 2))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	TEST_ASSERT(!P.emagged, "starts clean")
	hci_click(H, P, E)
	settle()
	TEST_ASSERT(P.emagged, "an emag subverts the plant")

/datum/unit_test/dq_hc_struct/biowaste_tank_takes_emag_again
/datum/unit_test/dq_hc_struct/biowaste_tank_takes_emag_again/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/biowaste_tank/B = allocate(/obj/structure/biowaste_tank, tile(3, 2))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	hci_click(H, B, E)
	settle()
	TEST_ASSERT(!QDELETED(B), "the tank survives the sequencer")
	hci_click(H, B, E)
	settle()
	TEST_ASSERT(!QDELETED(B), "and takes it again")

// ---------------------------------------------------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/janicart_window_stows_and_takes_gear
/datum/unit_test/dq_hc_struct/janicart_window_stows_and_takes_gear/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/janitorialcart/C = allocate(/obj/structure/janitorialcart, tile(3, 2))
	var/obj/item/mop/M = allocate(/obj/item/mop, tile(2, 2))
	H.put_in_active_hand(M)
	TEST_ASSERT(C.equip_janicart_item(H, M), "a held mop goes into the cart")
	TEST_ASSERT_EQUAL(C.mymop, M, "and is the cart's mop")
	var/list/data = hc_data(C, H)
	TEST_ASSERT(data["mymop"], "the window names it")
	TEST_ASSERT_NULL(data["mybag"], "and has no bag to show")
	press(H, C, "mop")
	TEST_ASSERT_NULL(C.mymop, "pressing it again takes the mop back")
	TEST_ASSERT_EQUAL(H.get_active_hand(), M, "into the hand")
	var/obj/item/clothing/suit/caution/S = allocate(/obj/item/clothing/suit/caution, tile(2, 2))
	H.drop_item()
	H.put_in_active_hand(S)
	press(H, C, "sign")
	TEST_ASSERT_EQUAL(C.signs, 1, "a held caution sign is stowed by the sign button")
	press(H, C, "sign")
	TEST_ASSERT_EQUAL(C.signs, 0, "and taken again with an empty hand")

/datum/unit_test/dq_hc_struct/janicart_bucket_button_unmounts_the_bucket
/datum/unit_test/dq_hc_struct/janicart_bucket_button_unmounts_the_bucket/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/janitorialcart/C = allocate(/obj/structure/janitorialcart, tile(3, 2))
	var/obj/structure/mopbucket/B = allocate(/obj/structure/mopbucket, tile(3, 3))
	rel_set(C, nameof(C.mybucket), B)
	press(H, C, "bucket")
	TEST_ASSERT_NULL(C.mybucket, "the bucket button unmounts the bucket")
	TEST_ASSERT_EQUAL(B.loc, get_turf(H), "at the presser's feet")

/datum/unit_test/dq_hc_struct/safe_dial_turns_and_opens
/datum/unit_test/dq_hc_struct/safe_dial_turns_and_opens/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/safe/S = allocate(/obj/structure/safe, tile(3, 2))
	S.dial = 10
	S.tumbler_1_pos = 8
	S.tumbler_1_open = 40
	S.tumbler_2_pos = 20
	S.tumbler_2_open = 50
	press(H, S, "decrement")
	TEST_ASSERT_EQUAL(S.dial, 9, "decrement turns the dial down")
	TEST_ASSERT_EQUAL(S.tumbler_1_pos, 7, "and drags the first tumbler with it")
	S.dial = 9
	S.tumbler_1_pos = 11
	press(H, S, "increment")
	TEST_ASSERT_EQUAL(S.dial, 10, "increment turns the dial up")
	TEST_ASSERT_EQUAL(S.tumbler_1_pos, 12, "and drags the first tumbler with it")
	press(H, S, "open")
	TEST_ASSERT(!S.open, "a locked safe stays shut")
	S.tumbler_1_pos = S.tumbler_1_open
	S.tumbler_2_pos = S.tumbler_2_open
	press(H, S, "open")
	TEST_ASSERT(S.open, "an unlocked one opens")
	var/list/data = hc_data(S, H)
	TEST_ASSERT(data["open"], "the window says so")
	TEST_ASSERT_EQUAL(data["dial"], 10, "and shows the dial")
	press(H, S, "open")
	TEST_ASSERT(!S.open, "pressing again shuts it")

/datum/unit_test/dq_hc_struct/safe_gives_back_what_it_holds
/datum/unit_test/dq_hc_struct/safe_gives_back_what_it_holds/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/safe/S = allocate(/obj/structure/safe, tile(3, 2))
	var/obj/item/pen/P = allocate(/obj/item/pen, tile(3, 2))
	P.forceMove(S)
	S.space = P.w_class
	var/list/data = hc_data(S, H)
	TEST_ASSERT_EQUAL(length(data["contents"]), 1, "the window lists what is inside")
	press(H, S, "retrieve", list("ref" = "\ref[P]"))
	TEST_ASSERT_EQUAL(P.loc, S, "a closed safe keeps it")
	S.open = TRUE
	press(H, S, "retrieve", list("ref" = "\ref[P]"))
	TEST_ASSERT_EQUAL(P.loc, H, "an open one hands it over")
	TEST_ASSERT_EQUAL(S.space, 0, "and has the room back")

/datum/unit_test/dq_hc_struct/tank_dispenser_hands_out_tanks
/datum/unit_test/dq_hc_struct/tank_dispenser_hands_out_tanks/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/dispenser/D = allocate(/obj/structure/dispenser, tile(3, 2))
	var/list/data = hc_data(D, H)
	TEST_ASSERT_EQUAL(data["oxygen"], 10, "the window counts the oxygen tanks")
	TEST_ASSERT_EQUAL(data["phoron"], 10, "and the phoron ones")
	press(H, D, "oxygen")
	TEST_ASSERT_EQUAL(D.oxygentanks, 9, "an oxygen tank leaves")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/tank/oxygen), "into the hand")
	H.drop_item()
	press(H, D, "phoron")
	TEST_ASSERT_EQUAL(D.phorontanks, 9, "a phoron tank leaves")
	TEST_ASSERT(istype(H.get_active_hand(), /obj/item/tank/phoron), "into the hand")

/datum/unit_test/dq_hc_struct/undies_wardrobe_removes_underwear
/datum/unit_test/dq_hc_struct/undies_wardrobe_removes_underwear/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/undies_wardrobe/W = allocate(/obj/structure/undies_wardrobe, tile(3, 2))
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories[1]
	var/datum/category_item/underwear/UWI = UWC.items[1]
	LAZYSET(H.all_underwear, UWC.name, UWI)
	var/list/data = hc_data(W, H)
	TEST_ASSERT(length(data["categories"]) > 0, "the window lists the underwear categories")
	press(H, W, "remove_underwear", list("category" = UWC.name))
	TEST_ASSERT(!(UWC.name in H.all_underwear), "the remove button takes the item off")

// Added with the conversion: the legacy question was asked with a window-state requirement no player-less test can satisfy.
/datum/unit_test/dq_hc_struct/undies_wardrobe_change_asks_for_a_choice
/datum/unit_test/dq_hc_struct/undies_wardrobe_change_asks_for_a_choice/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/undies_wardrobe/W = allocate(/obj/structure/undies_wardrobe, tile(3, 2))
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories[1]
	var/datum/category_item/underwear/chosen = UWC.items[length(UWC.items)]
	press(H, W, "change_underwear", list("category" = UWC.name))
	test_answer(H, chosen.name)
	settle()
	TEST_ASSERT_EQUAL(LAZYACCESS(H.all_underwear, UWC.name), chosen, "the chosen item is worn")

// ---------------------------------------------------------------------------------------------------------------------
// Held things used in hand
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/torn_inflatable_cannot_be_inflated
/datum/unit_test/dq_hc_struct/torn_inflatable_cannot_be_inflated/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/inflatable/torn/T = allocate(/obj/item/inflatable/torn, tile(2, 2))
	hci_click(H, T, T)
	settle()
	TEST_ASSERT(!QDELETED(T), "a torn wall is not used up")
	TEST_ASSERT_NULL(locate(/obj/structure/inflatable) in view(1, H), "and nothing is inflated")
	var/obj/item/inflatable/door/torn/D = allocate(/obj/item/inflatable/door/torn, tile(2, 2))
	hci_click(H, D, D)
	settle()
	TEST_ASSERT(!QDELETED(D), "nor is a torn door")
	TEST_ASSERT_NULL(locate(/obj/structure/inflatable) in view(1, H), "and nothing is inflated")

/datum/unit_test/dq_hc_struct/rubber_ducky_squeaks
/datum/unit_test/dq_hc_struct/rubber_ducky_squeaks/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/bikehorn/rubberducky/red/R = allocate(/obj/item/bikehorn/rubberducky/red, tile(2, 2))
	hci_click(H, R, R)
	settle()
	TEST_ASSERT_EQUAL(R.honk_count, 1, "the red duck counts a squeeze")
	var/obj/item/bikehorn/rubberducky/blue/B = allocate(/obj/item/bikehorn/rubberducky/blue, tile(2, 2))
	hci_click(H, B, B)
	settle()
	TEST_ASSERT(!QDELETED(B), "the blue duck survives a squeeze")
