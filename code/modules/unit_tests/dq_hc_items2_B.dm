// Behaviour-preservation tests for group B of the items domain (lighters, cigarettes, tools, weapons, shields, grenades, defibs, bags...). They pin what
// a player observes through clicks, windows and the kernel clock, so the same file passes before and after a family moves to the final forms. State is
// read through plain vars; nothing here depends on message text or on an op key. The helpers (hci_click, hci_answer) are in dq_hc_items_behaviour.dm.

/// One step of an item's periodic work. The legacy periodic lane is not driven by the test clock, so the tests call the step the lane would (an adapter:
/// only its body changes when the family moves to every()).
/proc/hci2b_step(obj/item/I)
	I.periodic_step()

// ---------------------------------------------------------------------------------------------------------------------
// Matches, lighters, cigarettes, pipes, e-cigs
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_items/b_match_burns_down_and_out

/datum/unit_test/dq_hc_items/b_match_burns_down_and_out/run_gate()
	var/obj/item/flame/match/M = allocate(/obj/item/flame/match, tile(2, 2))
	TEST_ASSERT(!M.lit, "a match starts unlit")
	M.light(null)
	TEST_ASSERT(M.lit, "lighting it lights it")
	TEST_ASSERT(M.is_hot(), "a lit match is hot")
	hci2b_step(M)
	TEST_ASSERT(M.lit, "it still burns after a step")
	TEST_ASSERT(M.smoketime < 5, "it burns down while lit")
	for(var/i in 1 to 6)
		hci2b_step(M)
	TEST_ASSERT(!M.lit, "it burns out")
	TEST_ASSERT(M.burnt, "a burnt match is marked burnt")
	TEST_ASSERT_EQUAL(M.icon_state, "match_burnt", "and looks it")

/datum/unit_test/dq_hc_items/b_lighter_toggles_with_use_and_lights_a_cigarette

/datum/unit_test/dq_hc_items/b_lighter_toggles_with_use_and_lights_a_cigarette/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/lighter/L = allocate(/obj/item/flame/lighter, T)
	TEST_ASSERT(!L.lit, "a lighter starts off")
	hci_click(H, L, L)
	settle()
	TEST_ASSERT(L.lit, "using it in the hand lights it")
	TEST_ASSERT_EQUAL(L.icon_state, "lighteron", "it shows the lit state")
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	TEST_ASSERT(!C.lit, "a cigarette starts unlit")
	hci_click(H, C, L)
	settle()
	TEST_ASSERT(C.lit, "a lit lighter used on a cigarette lights it")
	var/before = C.smoketime
	hci2b_step(C)
	TEST_ASSERT(C.smoketime < before, "a lit cigarette burns down")
	hci_click(H, L, L)
	settle()
	TEST_ASSERT(!L.lit, "using the lighter again puts it out")
	TEST_ASSERT_EQUAL(L.icon_state, "lighter", "it shows the off state")
	var/mid = C.smoketime
	hci_click(H, C, C)
	settle()
	TEST_ASSERT(!C.lit, "using a lit cigarette in the hand puts it out")
	TEST_ASSERT_EQUAL(C.smoketime, mid, "an unlit cigarette keeps its fuel")

/datum/unit_test/dq_hc_items/b_cigarette_dropped_in_hurt_stance_goes_out_as_a_butt

/datum/unit_test/dq_hc_items/b_cigarette_dropped_in_hurt_stance_goes_out_as_a_butt/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	C.light("lit")
	TEST_ASSERT(C.lit, "lit")
	hci_click(H, C, C, I_HURT)
	settle()
	TEST_ASSERT(QDELETED(C), "treading on a lit cigarette replaces it")
	var/found = FALSE
	for(var/obj/item/trash/cigbutt/B in T)
		found = TRUE
		qdel(B)
	for(var/obj/item/trash/cigbutt/B in H)
		found = TRUE
		qdel(B)
	TEST_ASSERT(found, "a butt is left")

/datum/unit_test/dq_hc_items/b_zippo_uses_its_own_states_and_pipe_empties

/datum/unit_test/dq_hc_items/b_zippo_uses_its_own_states_and_pipe_empties/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/lighter/zippo/Z = allocate(/obj/item/flame/lighter/zippo, T)
	hci_click(H, Z, Z)
	settle()
	TEST_ASSERT(Z.lit, "a zippo lights in the hand")
	TEST_ASSERT_EQUAL(Z.item_state, "zippoon", "it shows the lit in-hand state")
	hci_click(H, Z, Z)
	settle()
	TEST_ASSERT(!Z.lit, "and goes out")
	TEST_ASSERT_EQUAL(Z.item_state, "zippo", "back to the plain in-hand state")
	var/obj/item/clothing/mask/smokable/pipe/P = allocate(/obj/item/clothing/mask/smokable/pipe, T)
	P.light("lit")
	TEST_ASSERT(P.lit, "a pipe lights")
	hci_click(H, P, P, I_HELP)
	settle()
	TEST_ASSERT(!P.lit, "using a lit pipe puts it out")
	P.light("lit")
	hci_click(H, P, P, I_HURT)
	settle()
	TEST_ASSERT(!P.lit, "emptying a lit pipe puts it out")
	for(var/obj/effect/decal/cleanable/ash/ash in T)
		qdel(ash)

/datum/unit_test/dq_hc_items/b_match_lights_a_pipe

/datum/unit_test/dq_hc_items/b_match_lights_a_pipe/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/flame/match/M = allocate(/obj/item/flame/match, T)
	M.light(null)
	var/obj/item/clothing/mask/smokable/cigarette/cigar/C = allocate(/obj/item/clothing/mask/smokable/cigarette/cigar, T)
	hci_click(H, C, M)
	settle()
	TEST_ASSERT(C.lit, "a lit match lights a cigar")

/datum/unit_test/dq_hc_items/b_ecig_toggles_vapes_ejects_and_takes_a_cartridge

/datum/unit_test/dq_hc_items/b_ecig_toggles_vapes_ejects_and_takes_a_cartridge/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/clothing/mask/smokable/ecig/simple/E = allocate(/obj/item/clothing/mask/smokable/ecig/simple, T)
	var/obj/item/reagent_containers/ecig_cartridge/cart = E.ec_cartridge
	TEST_ASSERT(cart, "it starts with a cartridge")
	TEST_ASSERT(!E.active, "off")
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(E.active, "using it switches it on")
	E.update_icon()
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(E.icon_state, E.icon_on, "the look follows")
	TEST_ASSERT(H.equip_to_slot_if_possible(E, SLOT_ID_MASK), "worn")
	var/before = cart.reagents.total_volume
	hci2b_step(E)
	TEST_ASSERT(cart.reagents.total_volume < before, "a worn running e-cig vapes its cartridge")
	H.drop_from_inventory(E)
	hci_click(H, E, E)
	settle()
	TEST_ASSERT(!E.active, "using it again switches it off")
	H.put_in_inactive_hand(E)
	hci_click(H, E, null)
	settle()
	TEST_ASSERT_NULL(E.ec_cartridge, "an empty hand on the held e-cig ejects the cartridge")
	TEST_ASSERT_EQUAL(cart.loc, H, "the cartridge is in the hand")
	H.drop_item()
	hci_click(H, E, cart)
	settle()
	TEST_ASSERT_EQUAL(E.ec_cartridge, cart, "a cartridge used on it is installed")

/datum/unit_test/dq_hc_items/b_candle_burns_wax_while_lit

/datum/unit_test/dq_hc_items/b_candle_burns_wax_while_lit/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/flame/candle/C = allocate(/obj/item/flame/candle, tile(2, 2))
	var/start = C.wax
	C.light(user = H)
	TEST_ASSERT(C.lit, "lit")
	hci2b_step(C)
	TEST_ASSERT(C.wax < start, "a lit candle burns wax")
	hci_click(H, C, C)
	settle()
	TEST_ASSERT(!C.lit, "using it snuffs it")
	var/everburn_wax = 99999
	var/obj/item/flame/candle/everburn/E = allocate(/obj/item/flame/candle/everburn, tile(3, 3))
	hci2b_step(E)
	TEST_ASSERT_EQUAL(E.wax, everburn_wax, "an everburning candle never loses wax")

/datum/unit_test/dq_hc_items/b_wrapped_chewable_unwraps_in_the_hand

/datum/unit_test/dq_hc_items/b_wrapped_chewable_unwraps_in_the_hand/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/clothing/mask/chewable/tobacco/W = allocate(/obj/item/clothing/mask/chewable/tobacco, tile(2, 2))
	W.wrapped = TRUE
	hci_click(H, W, W)
	settle()
	TEST_ASSERT(!W.wrapped, "using a wrapped chewable unwraps it")

/datum/unit_test/dq_hc_items/b_ashtray_takes_butts_and_puts_out_cigarettes

/datum/unit_test/dq_hc_items/b_ashtray_takes_butts_and_puts_out_cigarettes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(2, 2)
	var/obj/item/material/ashtray/plastic/A = allocate(/obj/item/material/ashtray/plastic, T)
	var/obj/item/clothing/mask/smokable/cigarette/C = allocate(/obj/item/clothing/mask/smokable/cigarette, T)
	C.light("lit")
	hci_click(H, A, C)
	settle()
	TEST_ASSERT(QDELETED(C), "a lit cigarette put in an ashtray is put out and replaced")
	var/found = FALSE
	for(var/obj/item/trash/cigbutt/B in A)
		found = TRUE
	TEST_ASSERT(found, "its butt is in the ashtray")
	var/obj/item/trash/cigbutt/butt = allocate(/obj/item/trash/cigbutt, T)
	hci_click(H, A, butt)
	settle()
	TEST_ASSERT_EQUAL(butt.loc, A, "a butt is put in")
