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

/// A machine of `type` with power and in one piece.
/datum/unit_test/dq_hc_struct/proc/mach(type, turf/T)
	var/obj/machinery/M = allocate(type, T)
	M.stat_remove(NOPOWER | BROKEN)
	return M

/// A question is open for `actor`: an engine request, or a legacy prompt not yet answered.
/datum/unit_test/dq_hc_struct/proc/asked(mob/actor)
	if(SSrequests.open_for(actor))
		return TRUE
	for(var/datum/om/prompt/P as anything in om_scheduler().test_prompts)
		if(!P.answered && P.peek("answerer") == actor)
			return TRUE
	return FALSE

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

// ---------------------------------------------------------------------------------------------------------------------
// Questions a structure asks (answered through hci_answer: the engine's request first, else the legacy prompt)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/bonfire_rods_ask_what_to_build
/datum/unit_test/dq_hc_struct/bonfire_rods_ask_what_to_build/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/bonfire/B = allocate(/obj/structure/bonfire, tile(3, 2))
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, tile(2, 2))
	R.amount = 3
	hci_click(H, B, R)
	hci_answer(H, "Grill")
	settle()
	TEST_ASSERT(B.grill, "choosing the grill adds one")
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "and costs a rod")
	hci_click(H, B, R)
	TEST_ASSERT(!asked(H), "a bonfire with a grill asks nothing more")
	TEST_ASSERT_EQUAL(R.get_amount(), 2, "and no rod is spent")

/datum/unit_test/dq_hc_struct/bonfire_choice_is_dropped_when_the_rods_are_gone
/datum/unit_test/dq_hc_struct/bonfire_choice_is_dropped_when_the_rods_are_gone/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/bonfire/B = allocate(/obj/structure/bonfire, tile(3, 2))
	var/obj/item/stack/rods/R = allocate(/obj/item/stack/rods, tile(2, 2))
	R.amount = 3
	hci_click(H, B, R)
	H.drop_item()
	hci_answer(H, "Grill")
	settle()
	TEST_ASSERT(!B.grill, "an answer given after the rods left the hand is dropped")
	TEST_ASSERT_EQUAL(R.get_amount(), 3, "and no rod is spent")

/datum/unit_test/dq_hc_struct/gravemarker_name_is_carved
/datum/unit_test/dq_hc_struct/gravemarker_name_is_carved/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/gravemarker/G = allocate(/obj/structure/gravemarker, tile(3, 2))
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, tile(2, 2))
	hci_click(H, G, S)
	hci_answer(H, "Bob")
	settle() // the epitaph is the op's second question: it opens once the first is answered
	hci_answer(H, "Rest well")
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(G.grave_name, "Bob", "the first answer is the name, carved")

/datum/unit_test/dq_hc_struct/gravemarker_carving_is_dropped_when_the_tool_leaves_the_hand
/datum/unit_test/dq_hc_struct/gravemarker_carving_is_dropped_when_the_tool_leaves_the_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/gravemarker/G = allocate(/obj/structure/gravemarker, tile(3, 2))
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, tile(2, 2))
	hci_click(H, G, S)
	H.drop_item()
	hci_answer(H, "Bob")
	settle()
	hci_answer(H, "Rest well")
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(G.grave_name, "", "nothing is carved with a tool that is no longer held")

/datum/unit_test/dq_hc_struct/morgue_and_crematorium_are_labelled_with_a_pen
/datum/unit_test/dq_hc_struct/morgue_and_crematorium_are_labelled_with_a_pen/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/morgue/M = allocate(/obj/structure/morgue, tile(3, 2))
	var/obj/structure/morgue/crematorium/C = allocate(/obj/structure/morgue/crematorium, tile(3, 3))
	var/obj/item/pen/P = allocate(/obj/item/pen, tile(2, 2))
	hci_click(H, M, P)
	hci_answer(H, "Doe")
	settle()
	TEST_ASSERT_EQUAL(M.name, "Morgue- 'Doe'", "the morgue takes the label")
	hci_click(H, M, P)
	hci_answer(H, "")
	settle()
	TEST_ASSERT_EQUAL(M.name, "Morgue", "an empty label clears it")
	hci_click(H, C, P)
	hci_answer(H, "Roe")
	settle()
	TEST_ASSERT_EQUAL(C.name, "Crematorium- 'Roe'", "the crematorium takes its own label")

/datum/unit_test/dq_hc_struct/locked_reflector_asks_nothing
/datum/unit_test/dq_hc_struct/locked_reflector_asks_nothing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/reflector/R = allocate(/obj/structure/reflector, tile(3, 2))
	R.finished = TRUE
	var/angle = R.rotation_angle
	R.can_rotate = FALSE
	R.rotate(H)
	TEST_ASSERT(!asked(H), "a locked reflector asks nothing")
	TEST_ASSERT_EQUAL(R.rotation_angle, angle, "and keeps its angle")

/datum/unit_test/dq_hc_struct/sign_is_fastened_in_the_chosen_direction
/datum/unit_test/dq_hc_struct/sign_is_fastened_in_the_chosen_direction/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/sign/S = allocate(/obj/item/sign, T)
	var/obj/item/tool/screwdriver/D = allocate(/obj/item/tool/screwdriver, T)
	hci_click(H, S, D)
	hci_answer(H, "North")
	settle()
	TEST_ASSERT(QDELETED(S), "the sign item is used up")
	var/obj/structure/sign/placed = locate(/obj/structure/sign) in T
	TEST_ASSERT_NOTNULL(placed, "and the sign stands on the person's tile")
	TEST_ASSERT_EQUAL(placed.pixel_y, 32, "a north sign sits on the north edge")

/datum/unit_test/dq_hc_struct/sign_cancel_places_nothing
/datum/unit_test/dq_hc_struct/sign_cancel_places_nothing/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/sign/S = allocate(/obj/item/sign, T)
	var/obj/item/tool/screwdriver/D = allocate(/obj/item/tool/screwdriver, T)
	hci_click(H, S, D)
	hci_answer(H, "Cancel")
	settle()
	TEST_ASSERT(!QDELETED(S), "the sign item is kept")
	TEST_ASSERT_NULL(locate(/obj/structure/sign) in T, "and nothing is placed")

/datum/unit_test/dq_hc_struct/tyr_keypad_opens_for_the_right_code
/datum/unit_test/dq_hc_struct/tyr_keypad_opens_for_the_right_code/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/door/blast/puzzle/tyrdoor/keypad/D = allocate(/obj/machinery/door/blast/puzzle/tyrdoor/keypad, tile(3, 2))
	D.code = list("1", "2", "3", "4", "5", "6")
	D.stat_remove(NOPOWER | BROKEN)
	var/obj/item/multitool/M = allocate(/obj/item/multitool, tile(2, 2))
	// The multitool's code entry is an op above the puzzle door's catch-all for held items.
	hci_click(H, D, M)
	TEST_ASSERT(asked(H), "the multitool asks for a code")
	hci_answer(H, "654321")
	settle()
	TEST_ASSERT(D.density, "a wrong code leaves the door shut")
	hci_click(H, D, M)
	hci_answer(H, "112345")
	settle()
	TEST_ASSERT(D.density, "a code with repeated digits is refused")
	hci_click(H, D, M)
	hci_answer(H, "123456")
	test_time(3 SECONDS)
	TEST_ASSERT(!D.density, "the right code opens it")

/datum/unit_test/dq_hc_struct/window_tint_button_takes_an_id
/datum/unit_test/dq_hc_struct/window_tint_button_takes_an_id/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/button/windowtint/B = allocate(/obj/machinery/button/windowtint, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, tile(2, 2))
	B.id = null
	hci_click(H, B, M)
	hci_answer(H, "tintA")
	settle()
	TEST_ASSERT_EQUAL(B.id, "tintA", "the multitool sets the button's id")
	hci_click(H, B, M)
	TEST_ASSERT(!asked(H), "a button with an id asks nothing")
	TEST_ASSERT_EQUAL(B.id, "tintA", "and keeps it")

/datum/unit_test/dq_hc_struct/prism_is_rotated_by_hand
/datum/unit_test/dq_hc_struct/prism_is_rotated_by_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/prop/prism/P = allocate(/obj/structure/prop/prism, tile(3, 2))
	hci_click(H, P, null)
	hci_answer(H, TRUE)
	hci_answer(H, 90)
	settle()
	TEST_ASSERT_EQUAL(P.degrees_from_north, 90, "a confirmed bearing turns the prism")
	hci_click(H, P, null)
	hci_answer(H, FALSE)
	TEST_ASSERT(!asked(H), "a no asks for no bearing")
	TEST_ASSERT_EQUAL(P.degrees_from_north, 90, "and leaves it")
	P.rotation_lock = 1
	hci_click(H, P, null)
	TEST_ASSERT(!asked(H), "a locked prism asks nothing")

/datum/unit_test/dq_hc_struct/incremental_prism_is_turned_to_a_compass_point
/datum/unit_test/dq_hc_struct/incremental_prism_is_turned_to_a_compass_point/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/prop/prism/incremental/P = allocate(/obj/structure/prop/prism/incremental, tile(3, 2))
	hci_click(H, P, null)
	hci_answer(H, TRUE)
	hci_answer(H, "East")
	settle()
	TEST_ASSERT_EQUAL(P.degrees_from_north, 90, "a compass point sets its bearing")

/datum/unit_test/dq_hc_struct/prism_dial_turns_every_linked_prism
/datum/unit_test/dq_hc_struct/prism_dial_turns_every_linked_prism/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/prop/prismcontrol/C = allocate(/obj/structure/prop/prismcontrol, tile(3, 2))
	var/obj/structure/prop/prism/P = allocate(/obj/structure/prop/prism, tile(3, 3))
	rel_add(C, nameof(C.my_turrets), P)
	hci_click(H, C, null)
	hci_answer(H, TRUE)
	hci_answer(H, 45)
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT_EQUAL(P.degrees_from_north, 45, "the confirmed bearing turns the linked prism")
	hci_click(H, C, null)
	hci_answer(H, TRUE)
	hci_answer(H, 120)
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT_EQUAL(P.degrees_from_north, 45, "a final no turns nothing")

/datum/unit_test/dq_hc_struct/teleplumbed_toilet_offers_its_crystal
/datum/unit_test/dq_hc_struct/teleplumbed_toilet_offers_its_crystal/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/toilet/teleplumbed/T = allocate(/obj/structure/toilet/teleplumbed, tile(3, 2))
	T.cistern = TRUE
	T.open = FALSE
	var/obj/item/bluespace_crystal/crystal = T.teleplumb_crystal
	TEST_ASSERT_NOTNULL(crystal, "it has a crystal")
	hci_click(H, T, null)
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT_EQUAL(T.teleplumb_crystal, crystal, "a no leaves the crystal")
	hci_click(H, T, null)
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT_NULL(T.teleplumb_crystal, "a yes takes it out")
	TEST_ASSERT_EQUAL(crystal.loc, H, "into the hand")

/datum/unit_test/dq_hc_struct/trash_pile_hides_and_releases_an_animal
/datum/unit_test/dq_hc_struct/trash_pile_hides_and_releases_an_animal/run_gate()
	var/obj/structure/trash_pile/P = allocate(/obj/structure/trash_pile, tile(3, 2))
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, tile(2, 2))
	generic_hit(P, M)
	hci_answer(M, FALSE)
	settle()
	TEST_ASSERT_NULL(P.hider, "a no stays outside")
	generic_hit(P, M)
	hci_answer(M, TRUE)
	settle()
	TEST_ASSERT_EQUAL(M.loc, P, "a yes hides in the pile")
	TEST_ASSERT_EQUAL(P.hider, M, "as its hider")
	generic_hit(P, M)
	hci_answer(M, TRUE)
	settle()
	TEST_ASSERT_NOTEQUAL(M.loc, P, "a second yes comes out")
	TEST_ASSERT_NULL(P.hider, "and nobody hides there")

// ---------------------------------------------------------------------------------------------------------------------
// Added with the conversion (the legacy forms could not be driven by a player-less test)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/reflector_angle_is_asked_and_set
/datum/unit_test/dq_hc_struct/reflector_angle_is_asked_and_set/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/reflector/R = allocate(/obj/structure/reflector, tile(3, 2))
	R.finished = TRUE
	R.rotate(H)
	TEST_ASSERT(asked(H), "an unlocked reflector asks for an angle")
	hci_answer(H, 90)
	settle()
	TEST_ASSERT_EQUAL(R.rotation_angle, 90, "the answered angle is set")
	R.rotate(H)
	R.can_rotate = FALSE
	hci_answer(H, 180)
	settle()
	TEST_ASSERT_EQUAL(R.rotation_angle, 90, "an answer that arrives after the rotation was locked is dropped")

/datum/unit_test/dq_hc_struct/medical_stand_menu_toggles_mode_and_sets_transfer
/datum/unit_test/dq_hc_struct/medical_stand_menu_toggles_mode_and_sets_transfer/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/medical_stand/S = allocate(/obj/structure/medical_stand, tile(3, 2))
	var/mode = S.mode
	test_menu(H, S, "toggle_iv_mode")
	settle()
	TEST_ASSERT_NOTEQUAL(S.mode, mode, "the menu entry flips the IV mode")
	test_menu(H, S, "set_iv_transfer")
	TEST_ASSERT(asked(H), "the transfer entry asks for an amount")
	hci_answer(H, 2)
	settle()
	TEST_ASSERT_EQUAL(S.transfer_amount, 2, "the answered amount is the new transfer amount")

/datum/unit_test/dq_hc_struct/canvas_takes_strokes_until_it_is_finished
/datum/unit_test/dq_hc_struct/canvas_takes_strokes_until_it_is_finished/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/canvas/C = allocate(/obj/item/canvas, tile(2, 2))
	var/obj/item/paint_brush/B = allocate(/obj/item/paint_brush, tile(2, 2))
	B.selected_color = "#123456"
	H.put_in_active_hand(B)
	press(H, C, "paint", list("x" = 2, "y" = 3))
	TEST_ASSERT_EQUAL(C.grid[2][3], "#123456", "a stroke paints the cell under the held brush")
	TEST_ASSERT(C.used, "and marks the canvas as used")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["grid"], C.grid, "the window shows the grid")
	C.finalized = TRUE
	B.selected_color = "#654321"
	press(H, C, "paint", list("x" = 4, "y" = 4))
	TEST_ASSERT_NOTEQUAL(C.grid[4][4], "#654321", "a finished painting takes no more strokes")

/datum/unit_test/dq_hc_struct/flag_is_ripped_down_when_confirmed
/datum/unit_test/dq_hc_struct/flag_is_ripped_down_when_confirmed/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/sign/flag/F = allocate(/obj/structure/sign/flag, tile(3, 2))
	hci_click(H, F, null)
	hci_answer(H, FALSE)
	settle()
	TEST_ASSERT(!F.ripped, "a no leaves the flag whole")
	hci_click(H, F, null)
	hci_answer(H, TRUE)
	settle()
	TEST_ASSERT(F.ripped, "a yes rips it")
