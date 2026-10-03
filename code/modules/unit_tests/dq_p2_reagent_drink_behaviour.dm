// Behaviour-preservation tests for drinking containers (phase 2, reagent containers, step 7): cartons, cups, cans and glasses of /food/drinks: what a sip
// is, opening a can, feeding another, pouring from and into one, what is left when it is empty, and what examine says. They use the base and the click
// helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The drink's can is shut before it is opened (an opened one is the same as an open container).
/proc/rc_drink_open(obj/item/reagent_containers/food/drinks/D)
	return !!D.is_open_container()

/// The drink can't be opened (it has no ring pull).
/proc/rc_drink_make_cant_open(obj/item/reagent_containers/food/drinks/D)
	D.cant_open = TRUE

/// How many times the can has been shaken.
/proc/rc_can_shaken(obj/item/reagent_containers/food/drinks/cans/C)
	return C.shaken

// ---------------------------------------------------------------------------------------------------------------------
// What they are
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/drinks_start_as_declared

/datum/unit_test/dq_p2_reagents/drinks_start_as_declared/run_gate()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	TEST_ASSERT_EQUAL(rc_capacity(M), 50, "a carton holds 50")
	TEST_ASSERT_EQUAL(rc_units(M), 50, "and is full of milk")
	TEST_ASSERT_EQUAL(rc_amount(M), 5, "a sip is 5")
	TEST_ASSERT(rc_drink_open(M), "a carton is open")
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	TEST_ASSERT_EQUAL(rc_capacity(C), 40, "a can holds 40")
	TEST_ASSERT_EQUAL(rc_units(C), 30, "and comes with 30 of cola")
	TEST_ASSERT(!rc_drink_open(C), "a can is shut")
	var/obj/item/reagent_containers/food/drinks/golden_cup/G = allocate(/obj/item/reagent_containers/food/drinks/golden_cup)
	TEST_ASSERT_EQUAL(rc_capacity(G), 150, "the golden cup holds 150")
	TEST_ASSERT_EQUAL(rc_amount(G), 20, "a sip of it is 20")

// ---------------------------------------------------------------------------------------------------------------------
// Opening
// ---------------------------------------------------------------------------------------------------------------------

/// Using a can in hand opens it, once; it stays open.
/datum/unit_test/dq_p2_reagents/can_is_opened_in_hand

/datum/unit_test/dq_p2_reagents/can_is_opened_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	rc_use(H, C)
	TEST_ASSERT(rc_drink_open(C), "the can is open")
	rc_use(H, C)
	TEST_ASSERT(rc_drink_open(C), "and stays open")

/// A can with no ring pull does not open, and is renamed for it.
/datum/unit_test/dq_p2_reagents/can_without_a_ring_pull_stays_shut

/datum/unit_test/dq_p2_reagents/can_without_a_ring_pull_stays_shut/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	rc_drink_make_cant_open(C)
	rc_use(H, C)
	TEST_ASSERT(!rc_drink_open(C), "it stays shut")
	TEST_ASSERT(findtext(C.name, "can't"), "and is named for it: [C.name]")

/// In a hostile stance, using a shut can shakes it (it does not open); an open one is not shaken.
/datum/unit_test/dq_p2_reagents/can_is_shaken_in_a_hostile_stance

/datum/unit_test/dq_p2_reagents/can_is_shaken_in_a_hostile_stance/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	H.drop_item()
	H.put_in_active_hand(C)
	H.set_use_stance(I_HURT)
	H.next_click = 0
	input_submit(new /datum/input_event/click(H, C, null, null, "left=1"))
	H.set_use_stance(I_HELP)
	TEST_ASSERT(!rc_drink_open(C), "it is not opened")
	TEST_ASSERT_EQUAL(rc_can_shaken(C), 3, "it is shaken")

// ---------------------------------------------------------------------------------------------------------------------
// Drinking
// ---------------------------------------------------------------------------------------------------------------------

/// A click on yourself with an open drink: one sip into the stomach. A shut can needs opening first.
/datum/unit_test/dq_p2_reagents/drink_is_sipped

/datum/unit_test/dq_p2_reagents/drink_is_sipped/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	var/before = rc_stomach_units(H)
	rc_click(H, H, M, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(M), 45, "a sip left the carton")
	TEST_ASSERT(rc_stomach_units(H) > before, "and is in the stomach")
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	rc_click(H, H, C, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(C), 30, "a shut can gives nothing")

/// The set amount of a drink is what a sip is.
/datum/unit_test/dq_p2_reagents/drink_amount_is_set

/datum/unit_test/dq_p2_reagents/drink_amount_is_set/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/golden_cup/G = allocate(/obj/item/reagent_containers/food/drinks/golden_cup)
	G.reagents.add_reagent(REAGENT_ID_WATER, 100)
	rc_click(H, H, G, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(G), 80, "a sip of the golden cup is 20")

/// Somebody else is fed after three seconds, in a friendly stance; in a hostile stance a cup with force hits and one without feeds.
/datum/unit_test/dq_p2_reagents/drink_is_fed_to_another

/datum/unit_test/dq_p2_reagents/drink_is_fed_to_another/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	var/before = rc_stomach_units(patient)
	rc_click(H, patient, M, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(M), 50, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(M), 50, "nor after a second")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(M), 45, "after the wait the patient has had a sip")
	TEST_ASSERT(rc_stomach_units(patient) > before, "into the stomach")

/// A hostile click with a drink that does no harm feeds all the same (a carton).
/datum/unit_test/dq_p2_reagents/hostile_carton_still_feeds

/datum/unit_test/dq_p2_reagents/hostile_carton_still_feeds/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	rc_click(H, patient, M, I_HURT)
	TEST_ASSERT_EQUAL(rc_units(M), 45, "a sip was given")

// ---------------------------------------------------------------------------------------------------------------------
// Pouring
// ---------------------------------------------------------------------------------------------------------------------

/// An open drink pours into an open container, and a closed can does not; a tank fills it by the tank's amount.
/datum/unit_test/dq_p2_reagents/drink_pours_and_fills

/datum/unit_test/dq_p2_reagents/drink_pours_and_fills/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, M)
	TEST_ASSERT_EQUAL(rc_units(B), 5, "a carton pours a sip into a beaker")
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	rc_click(H, B, C)
	TEST_ASSERT_EQUAL(rc_units(B), 5, "a shut can does not")
	var/obj/item/reagent_containers/food/drinks/golden_cup/G = allocate(/obj/item/reagent_containers/food/drinks/golden_cup)
	var/obj/structure/reagent_dispensers/watertank/tank = allocate(/obj/structure/reagent_dispensers/watertank)
	rc_click(H, tank, G)
	TEST_ASSERT_EQUAL(rc_units(G), tank.amount_per_transfer_from_this, "an open cup is filled from a tank by the tank's amount")
	rc_click(H, tank, C)
	TEST_ASSERT_EQUAL(rc_units(C), 30, "a shut can is not")

/// A beaker pours into an open drink.
/datum/unit_test/dq_p2_reagents/drink_is_poured_into

/datum/unit_test/dq_p2_reagents/drink_is_poured_into/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/golden_cup/G = allocate(/obj/item/reagent_containers/food/drinks/golden_cup)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, G, B)
	TEST_ASSERT_EQUAL(rc_units(G), 10, "the beaker pours its ten into the cup")

// ---------------------------------------------------------------------------------------------------------------------
// When it is empty, and what examine says
// ---------------------------------------------------------------------------------------------------------------------

/// A cup that leaves something behind is gone when it is emptied, and the trash is in the hand.
/datum/unit_test/dq_p2_reagents/emptied_cup_leaves_its_trash

/datum/unit_test/dq_p2_reagents/emptied_cup_leaves_its_trash/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/coffee/C = allocate(/obj/item/reagent_containers/food/drinks/coffee)
	for(var/i in 1 to 6)
		if(QDELETED(C))
			break
		rc_click(H, H, C, I_HELP, FALSE)
		rc_settle()
	TEST_ASSERT(QDELETED(C), "the cup is gone")
	var/obj/item/trash/coffee/trash = locate() in H
	if(!trash)
		trash = locate() in get_turf(H)
	TEST_ASSERT_NOTNULL(trash, "its trash is left")
	if(trash)
		qdel(trash)

/// Examine tells how full it is, and a can with no ring pull says so.
/datum/unit_test/dq_p2_reagents/drink_examine

/datum/unit_test/dq_p2_reagents/drink_examine/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/drinks/milk/M = allocate(/obj/item/reagent_containers/food/drinks/milk)
	var/text = jointext(M.examine(H), " ")
	TEST_ASSERT(findtext(text, "full"), "a full carton says so: [text]")
	M.reagents.remove_any(30)
	text = jointext(M.examine(H), " ")
	TEST_ASSERT(findtext(text, "half") || findtext(text, "almost"), "a part full one says how much: [text]")
	M.reagents.clear_reagents()
	text = jointext(M.examine(H), " ")
	TEST_ASSERT(findtext(text, "empty"), "an empty one says so: [text]")
	var/obj/item/reagent_containers/food/drinks/cans/cola/C = allocate(/obj/item/reagent_containers/food/drinks/cans/cola)
	rc_drink_make_cant_open(C)
	text = jointext(C.examine(H), " ")
	TEST_ASSERT(findtext(text, "ring pull"), "a can with no ring pull says so: [text]")
