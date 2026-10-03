// Behaviour-preservation tests for the other reagent containers (phase 2, reagent containers, step 6): the chemical dispenser cartridge and canister, the
// powder, the rolling paper and the e-cigarette cartridge. They use the base and the click helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The person sets the cartridge's label (the menu entry), giving `text` when asked (a re-run answer today).
/proc/rc_label_cartridge(mob/actor, obj/item/reagent_containers/chem_disp_cartridge/C, text)
	GLOB.om_rerun_answers["[REF(C)]:cartridge_set_label"] = list("label" = text)
	C.cartridge_set_label(actor, null, null)
	GLOB.om_rerun_answers -= "[REF(C)]:cartridge_set_label"

/// The label the cartridge keeps.
/proc/rc_cartridge_label(obj/item/reagent_containers/chem_disp_cartridge/C)
	return C.label

// ---------------------------------------------------------------------------------------------------------------------
// Chemical dispenser cartridge
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/cartridges_start_as_declared

/datum/unit_test/dq_p2_reagents/cartridges_start_as_declared/run_gate()
	var/obj/item/reagent_containers/chem_disp_cartridge/water/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water)
	TEST_ASSERT_EQUAL(rc_capacity(C), 500, "a large cartridge holds 500")
	TEST_ASSERT_EQUAL(rc_units(C), 500, "and comes full of water")
	TEST_ASSERT_EQUAL(rc_amount(C), 50, "it moves 50 at a time")
	TEST_ASSERT_EQUAL(rc_amount_range(C)[1], 50, "from 50")
	TEST_ASSERT_EQUAL(rc_amount_range(C)[2], 500, "to 500")
	TEST_ASSERT(!rc_open(C), "its cap is on")
	TEST_ASSERT(findtext(C.name, "Water"), "it is named for what it holds: [C.name]")
	var/obj/item/reagent_containers/chem_disp_cartridge/small/small = allocate(/obj/item/reagent_containers/chem_disp_cartridge/small)
	TEST_ASSERT_EQUAL(rc_capacity(small), 100, "a small one holds 100")
	TEST_ASSERT_EQUAL(rc_units(small), 0, "and starts empty")

/// Using it in hand takes the cap off and puts it on.
/datum/unit_test/dq_p2_reagents/cartridge_cap_toggles_in_hand

/datum/unit_test/dq_p2_reagents/cartridge_cap_toggles_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_disp_cartridge/water/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water)
	rc_use(H, C)
	TEST_ASSERT(rc_open(C), "the cap is off")
	rc_use(H, C)
	TEST_ASSERT(!rc_open(C), "and on again")

/// Open, it pours its amount into an open container; closed, it does not; a full container takes nothing.
/datum/unit_test/dq_p2_reagents/cartridge_pours_into_a_container

/datum/unit_test/dq_p2_reagents/cartridge_pours_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_disp_cartridge/water/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water)
	var/obj/item/reagent_containers/glass/beaker/large/B = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	rc_click(H, B, C)
	TEST_ASSERT_EQUAL(rc_units(B), 0, "with the cap on nothing pours")
	rc_use(H, C)
	rc_click(H, B, C)
	TEST_ASSERT_EQUAL(rc_units(B), 50, "with the cap off it pours its 50")
	TEST_ASSERT_EQUAL(rc_units(C), 450, "from the cartridge")
	var/obj/item/reagent_containers/glass/beaker/full = rc_filled(/obj/item/reagent_containers/glass/beaker, 60)
	rc_click(H, full, C)
	TEST_ASSERT_EQUAL(rc_units(C), 450, "a full beaker takes nothing")

/// Open, it fills from a tank by the tank's own amount; closed, it does not.
/datum/unit_test/dq_p2_reagents/cartridge_fills_from_a_tank

/datum/unit_test/dq_p2_reagents/cartridge_fills_from_a_tank/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_disp_cartridge/small/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/small)
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(rc_units(C), 0, "with the cap on it does not fill")
	rc_use(H, C)
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(rc_units(C), tank.amount_per_transfer_from_this, "with the cap off it takes the tank's amount")

/// The label verb names the cartridge; an empty label clears it.
/datum/unit_test/dq_p2_reagents/cartridge_label

/datum/unit_test/dq_p2_reagents/cartridge_label/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_disp_cartridge/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge)
	rc_label_cartridge(H, C, "Acid")
	TEST_ASSERT_EQUAL(rc_cartridge_label(C), "Acid", "the label is kept")
	TEST_ASSERT(findtext(C.name, "Acid"), "and is in the name: [C.name]")
	rc_label_cartridge(H, C, "")
	TEST_ASSERT_EQUAL(rc_cartridge_label(C), "", "an empty label clears it")
	TEST_ASSERT_EQUAL(C.name, initial(C.name), "and the name goes back")

/// Examine says what it holds and whether its cap is on.
/datum/unit_test/dq_p2_reagents/cartridge_examine

/datum/unit_test/dq_p2_reagents/cartridge_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_disp_cartridge/water/C = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water)
	var/text = jointext(C.examine(H), " ")
	TEST_ASSERT(findtext(text, "500"), "it says how much it holds: [text]")
	TEST_ASSERT(findtext(text, "cap") || findtext(text, "lid"), "and that it is shut: [text]")
	rc_use(H, C)
	text = jointext(C.examine(H), " ")
	TEST_ASSERT(!findtext(text, "sealed") && !findtext(text, "is closed"), "an open one does not: [text]")

// ---------------------------------------------------------------------------------------------------------------------
// Chemical canister
// ---------------------------------------------------------------------------------------------------------------------

/// A canister pours its whole content into an open container (as much as it takes) and refills the matching cartridge of a dispenser machine.
/datum/unit_test/dq_p2_reagents/canister_pours_and_refills

/datum/unit_test/dq_p2_reagents/canister_pours_and_refills/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/chem_canister/water/can = allocate(/obj/item/reagent_containers/chem_canister/water)
	TEST_ASSERT_EQUAL(rc_units(can), 500, "a canister comes full")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, can)
	TEST_ASSERT_EQUAL(rc_units(B), 60, "an open container takes what it can hold")
	TEST_ASSERT_EQUAL(rc_units(can), 440, "from the canister")
	var/obj/machinery/chemical_dispenser/D = allocate(/obj/machinery/chemical_dispenser)
	var/obj/item/reagent_containers/chem_disp_cartridge/water/cart = allocate(/obj/item/reagent_containers/chem_disp_cartridge/water)
	cart.reagents.clear_reagents()
	D.cartridges[cart.label] = cart
	rc_click(H, D, can)
	TEST_ASSERT(rc_units(cart) >= 440, "the matching cartridge is refilled from the canister")
	TEST_ASSERT(rc_units(can) <= 0, "which gave all it had")

// ---------------------------------------------------------------------------------------------------------------------
// Powder
// ---------------------------------------------------------------------------------------------------------------------

/// A powder is snorted with a straw: two units into the blood; anything else, or a non-human, does nothing.
/datum/unit_test/dq_p2_reagents/powder_is_snorted_with_a_straw

/datum/unit_test/dq_p2_reagents/powder_is_snorted_with_a_straw/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/powder/P = allocate(/obj/item/reagent_containers/powder)
	P.reagents.add_reagent(REAGENT_ID_SUGAR, 10)
	var/obj/item/glass_extra/straw/straw = allocate(/obj/item/glass_extra/straw)
	var/before = rc_blood_units(H)
	rc_click(H, P, straw)
	TEST_ASSERT_EQUAL(rc_units(P), 8, "two units are snorted")
	TEST_ASSERT(rc_blood_units(H) > before, "into the blood")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rc_click(H, P, pen)
	TEST_ASSERT_EQUAL(rc_units(P), 8, "a pen is no straw")
	for(var/i in 1 to 4)
		rc_click(H, P, straw)
	TEST_ASSERT(QDELETED(P), "the powder is used up when it is gone")

// ---------------------------------------------------------------------------------------------------------------------
// Rolling paper
// ---------------------------------------------------------------------------------------------------------------------

/// Rolling paper with something in it is rolled by using it: the joint holds what the paper held, and the paper is used up. (The old "nothing in it"
/// requirement was always true, so an empty paper is rolled too: the pinned behaviour.)
/datum/unit_test/dq_p2_reagents/rolling_paper_is_rolled

/datum/unit_test/dq_p2_reagents/rolling_paper_is_rolled/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/rollingpaper/empty = allocate(/obj/item/reagent_containers/rollingpaper)
	rc_use(H, empty)
	TEST_ASSERT(QDELETED(empty), "an empty paper is rolled too (the old refusal never applied)")
	for(var/obj/item/clothing/mask/smokable/cigarette/joint/old in H.contents + get_turf(H))
		qdel(old)
	var/obj/item/reagent_containers/rollingpaper/P = allocate(/obj/item/reagent_containers/rollingpaper)
	P.reagents.add_reagent(REAGENT_ID_SUGAR, 10)
	rc_use(H, P)
	TEST_ASSERT(QDELETED(P), "the paper is used up")
	var/obj/item/clothing/mask/smokable/cigarette/joint/J = locate() in H
	if(!J)
		J = locate() in get_turf(H)
	TEST_ASSERT_NOTNULL(J, "a joint was made")
	if(J)
		TEST_ASSERT(J.reagents.has_reagent(REAGENT_ID_SUGAR, 10), "that holds what the paper held")
		qdel(J)

/// Anything but a dried plant is not put into the paper.
/datum/unit_test/dq_p2_reagents/rolling_paper_takes_nothing_else

/datum/unit_test/dq_p2_reagents/rolling_paper_takes_nothing_else/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/rollingpaper/P = allocate(/obj/item/reagent_containers/rollingpaper)
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rc_click(H, P, pen)
	TEST_ASSERT_EQUAL(rc_units(P), 0, "a pen adds nothing")
	TEST_ASSERT(!QDELETED(P), "and the paper is kept")

// ---------------------------------------------------------------------------------------------------------------------
// E-cigarette cartridge
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/ecig_cartridge_is_an_open_container

/datum/unit_test/dq_p2_reagents/ecig_cartridge_is_an_open_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/ecig_cartridge/C = allocate(/obj/item/reagent_containers/ecig_cartridge)
	C.reagents.clear_reagents()
	TEST_ASSERT_EQUAL(rc_capacity(C), 20, "a cartridge holds 20")
	TEST_ASSERT(rc_open(C), "and is open")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, C, B)
	TEST_ASSERT_EQUAL(rc_units(C), 10, "a beaker pours into it")
