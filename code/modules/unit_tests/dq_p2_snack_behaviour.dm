// Behaviour-preservation tests for solid food (phase 2, food, step 2): eating a bite at a time, feeding another, the wrapper and the can, slicing, hiding an
// item in a cake, batter, the things a held item turns a food into (rolling a dough, a burger and a cheese wedge), eggs, donk-pockets, monkey cubes, chips and
// dips, and the customizable foods. They use the base and the click helpers of dq_p2_reagent_behaviour.dm and the fixtures of dq_p2_food_behaviour.dm.
//
// Rules the tests keep: input goes through the click helpers and the adapter block below, which is the only place that names today's accessors; every
// input is followed by a settle; nothing depends on message text or on an op key.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The bites taken out of a snack.
/proc/sn_bites(obj/item/reagent_containers/food/snacks/F)
	return F.bitecount

/// The snack is still in its wrapper.
/proc/sn_wrapped(obj/item/reagent_containers/food/snacks/F)
	return !!F.package

/// The snack is still sealed in its can.
/proc/sn_canned(obj/item/reagent_containers/food/snacks/F)
	return !!F.canned

/// The coating (batter) on a snack, or null.
/proc/sn_coating(obj/item/reagent_containers/food/snacks/F)
	return F.coating()

/// The actor clicks `target` with `held` and gives `answer` to the one question it asks.
/datum/unit_test/dq_p2_reagents/proc/sn_click_answering(mob/living/carbon/human/H, atom/target, obj/item/held, answer, stance = I_HELP)
	rc_click(H, target, held, stance, FALSE)
	if(isnull(answer))
		test_answer(H, null, REQ_CANCELLED)
	else
		test_answer(H, answer)
	rc_settle()

/// The actor clicks `food` with `held` and says yes or no to hiding it in the food.
/datum/unit_test/dq_p2_reagents/proc/sn_click_hiding(mob/living/carbon/human/H, obj/item/reagent_containers/food/snacks/food, obj/item/held, answer)
	sn_click_answering(H, food, held, answer == "Yes" ? TRUE : null)

/// A snack of `type` on the test turf.
/datum/unit_test/dq_p2_reagents/proc/sn_snack(type = /obj/item/reagent_containers/food/snacks/aesirsalad, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

/// The first thing of `type` in range of the test turf (what a food was turned into).
/datum/unit_test/dq_p2_reagents/proc/sn_find(type)
	for(var/atom/A in range(2, run_loc_floor_bottom_left))
		if(istype(A, type) && !QDELETED(A))
			return A
	for(var/atom/A in run_loc_floor_bottom_left)
		for(var/atom/B in A)
			if(istype(B, type) && !QDELETED(B))
				return B
	return null

/// The things of `type` in range of the test turf, in hands or on the floor.
/datum/unit_test/dq_p2_reagents/proc/sn_count(type, mob/holder)
	. = 0
	for(var/obj/item/I in range(2, run_loc_floor_bottom_left))
		if(istype(I, type) && !QDELETED(I))
			.++
	if(holder)
		for(var/obj/item/I in holder)
			if(istype(I, type) && !QDELETED(I))
				.++

// ---------------------------------------------------------------------------------------------------------------------
// What a snack is
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/snacks_start_as_declared

/datum/unit_test/dq_p2_reagents/snacks_start_as_declared/run_gate()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	TEST_ASSERT_EQUAL(rc_capacity(S), 80, "a snack holds 80")
	TEST_ASSERT_EQUAL(S.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT), 16, "its nutriment is twice the amount written")
	TEST_ASSERT_EQUAL(S.reagents.get_reagent_amount(REAGENT_ID_DOCTORSDELIGHT), 8, "and its declared reagents are in")
	TEST_ASSERT_EQUAL(rc_units(S), 32, "in all")
	TEST_ASSERT_EQUAL(S.bitesize, 3, "a bite is 3")
	TEST_ASSERT(!rc_open(S), "a snack is not an open container")
	var/obj/item/reagent_containers/food/snacks/egg/egg = sn_snack(/obj/item/reagent_containers/food/snacks/egg)
	TEST_ASSERT_EQUAL(rc_capacity(egg), 10, "an egg holds 10")
	var/obj/item/reagent_containers/food/snacks/donut/plain/donut = sn_snack(/obj/item/reagent_containers/food/snacks/donut/plain)
	TEST_ASSERT_EQUAL(donut.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT), 9, "a plain donut's extra nutriment is in")
	var/obj/item/reagent_containers/food/snacks/donut/meat/meat_donut = sn_snack(/obj/item/reagent_containers/food/snacks/donut/meat)
	TEST_ASSERT_EQUAL(meat_donut.reagents.get_reagent_amount(REAGENT_ID_PROTEIN), 3, "a meat donut's extra is protein")

// ---------------------------------------------------------------------------------------------------------------------
// Eating
// ---------------------------------------------------------------------------------------------------------------------

/// A click on yourself takes one bite, in any stance: bitesize units into the stomach, and the bite is counted and shows.
/datum/unit_test/dq_p2_reagents/snack_is_eaten_a_bite_at_a_time

/datum/unit_test/dq_p2_reagents/snack_is_eaten_a_bite_at_a_time/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	var/before = rc_stomach_units(H)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 29, "one bite of 3 left the snack")
	TEST_ASSERT(rc_stomach_units(H) > before, "and is in the stomach")
	TEST_ASSERT_EQUAL(sn_bites(S), 1, "one bite is counted")
	TEST_ASSERT(findtext(jointext(S.examine(H), " "), "bitten by someone"), "and examine says so")
	for(var/stance in list(I_DISARM, I_GRAB, I_HURT))
		var/units = rc_units(S)
		rc_click(H, H, S, stance, FALSE)
		TEST_ASSERT_EQUAL(rc_units(S), units - 3, "a bite in the [stance] stance too")
	TEST_ASSERT_EQUAL(sn_bites(S), 4, "four bites are counted")
	TEST_ASSERT(findtext(jointext(S.examine(H), " "), "multiple times"), "and it was bitten many times")

/// A snack is eaten to the end: it is gone and its trash is in the hand.
/datum/unit_test/dq_p2_reagents/finished_snack_leaves_its_trash

/datum/unit_test/dq_p2_reagents/finished_snack_leaves_its_trash/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	for(var/i in 1 to 20)
		if(QDELETED(S))
			break
		rc_click(H, H, S, I_HELP, FALSE)
		test_time(1 SECONDS)
	TEST_ASSERT(QDELETED(S), "the snack is gone")
	var/obj/item/trash/snack_bowl/trash = locate() in H
	if(!trash)
		trash = locate() in get_turf(H)
	TEST_ASSERT_NOTNULL(trash, "its bowl is left")

/// A very full person does not take another bite.
/datum/unit_test/dq_p2_reagents/full_person_cannot_eat

/datum/unit_test/dq_p2_reagents/full_person_cannot_eat/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	H.reagents.add_reagent(REAGENT_ID_NUTRIMENT, 260)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nothing was eaten")
	H.reagents.clear_reagents()
	H.set_nutrition(100)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 29, "a hungry one eats")

/// A mask over the mouth stops a bite, for the one eating and the one fed.
/datum/unit_test/dq_p2_reagents/mask_stops_a_bite

/datum/unit_test/dq_p2_reagents/mask_stops_a_bite/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(H.equip_to_slot_if_possible(mask, SLOT_ID_MASK), "a mask is worn")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nothing is eaten through a mask")
	var/mob/living/carbon/human/other = rc_actor()
	var/obj/item/clothing/mask/gas/mask2 = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(other.equip_to_slot_if_possible(mask2, SLOT_ID_MASK), "the other wears one")
	rc_click(H, other, S, I_HELP, FALSE)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nor is somebody fed through one")

/// A snack with nothing left is used up by the attempt.
/datum/unit_test/dq_p2_reagents/empty_snack_is_used_up

/datum/unit_test/dq_p2_reagents/empty_snack_is_used_up/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	S.reagents.clear_reagents()
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT(QDELETED(S), "an empty snack is gone")

/// Somebody else is fed after three seconds, in a friendly stance; in a hostile one the snack is not fed.
/datum/unit_test/dq_p2_reagents/snack_is_fed_to_another

/datum/unit_test/dq_p2_reagents/snack_is_fed_to_another/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	var/before = rc_stomach_units(patient)
	rc_click(H, patient, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nothing at once")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nor after a second")
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 29, "after the wait the patient has had a bite")
	TEST_ASSERT(rc_stomach_units(patient) > before, "in the stomach")
	TEST_ASSERT_EQUAL(sn_bites(S), 1, "and it is counted")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/T = sn_snack()
	rc_click(H, patient, T, I_HURT, TRUE)
	TEST_ASSERT_EQUAL(rc_units(T), 32, "a hostile click does not feed")

/// The one fed must stay where they were.
/datum/unit_test/dq_p2_reagents/fed_snack_stops_when_the_patient_leaves

/datum/unit_test/dq_p2_reagents/fed_snack_stops_when_the_patient_leaves/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	rc_click(H, patient, S, I_HELP, FALSE)
	test_time(1 SECONDS)
	patient.forceMove(run_loc_floor_top_right)
	rc_settle()
	TEST_ASSERT_EQUAL(rc_units(S), 32, "nothing is fed")

/// A mindless creature nibbles at a snack with its teeth: a bite of the same size.
/datum/unit_test/dq_p2_reagents/animal_nibbles_a_snack

/datum/unit_test/dq_p2_reagents/animal_nibbles_a_snack/run_gate()
	var/mob/living/simple_mob/combat_ai_test_subject/mob = allocate(/mob/living/simple_mob/combat_ai_test_subject, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	S.attack_generic(mob)
	TEST_ASSERT_EQUAL(rc_units(S), 29, "a bite was taken")
	TEST_ASSERT_EQUAL(sn_bites(S), 1, "and counted")

// ---------------------------------------------------------------------------------------------------------------------
// Wrappers and cans
// ---------------------------------------------------------------------------------------------------------------------

/// A packaged snack is eaten only after the wrapper comes off by using it in hand; the wrapper is left in the hand.
/datum/unit_test/dq_p2_reagents/package_is_unwrapped_in_hand

/datum/unit_test/dq_p2_reagents/package_is_unwrapped_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/packaged/lunacake/S = sn_snack(/obj/item/reagent_containers/food/snacks/packaged/lunacake)
	TEST_ASSERT(sn_wrapped(S), "it starts wrapped")
	var/units = rc_units(S)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), units, "a wrapped one is not eaten")
	rc_use(H, S)
	TEST_ASSERT(!sn_wrapped(S), "using it takes the wrapper off")
	var/obj/item/trash/lunacakewrap/wrap = locate() in H
	TEST_ASSERT_NOTNULL(wrap, "the wrapper is in the hand")
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT(rc_units(S) < units, "and it can be eaten")

/// A canned snack is eaten only after the can is opened.
/datum/unit_test/dq_p2_reagents/can_is_opened_in_hand

/datum/unit_test/dq_p2_reagents/can_is_opened_in_hand/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/canned/beef/S = sn_snack(/obj/item/reagent_containers/food/snacks/canned/beef)
	TEST_ASSERT(sn_canned(S), "it starts sealed")
	var/units = rc_units(S)
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT_EQUAL(rc_units(S), units, "a sealed one is not eaten")
	rc_use(H, S)
	TEST_ASSERT(!sn_canned(S), "using it opens the can")
	TEST_ASSERT_EQUAL(S.icon_state, "beef-open", "and draws it open")
	rc_click(H, H, S, I_HELP, FALSE)
	TEST_ASSERT(rc_units(S) < units, "and it can be eaten")

// ---------------------------------------------------------------------------------------------------------------------
// Slicing and hiding
// ---------------------------------------------------------------------------------------------------------------------

/// A knife on a loaf lying on a table cuts it into its slices, each with its share of the reagents; the loaf is gone.
/datum/unit_test/dq_p2_reagents/sliceable_is_sliced_on_a_table

/datum/unit_test/dq_p2_reagents/sliceable_is_sliced_on_a_table/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/structure/table/standard/table = allocate(/obj/structure/table/standard, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/sliceable/meatbread/loaf = sn_snack(/obj/item/reagent_containers/food/snacks/sliceable/meatbread)
	var/total = rc_units(loaf)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	rc_click(H, loaf, knife, I_HELP)
	TEST_ASSERT(QDELETED(loaf), "the loaf is gone")
	var/slices = sn_count(/obj/item/reagent_containers/food/snacks/slice/meatbread)
	TEST_ASSERT_EQUAL(slices, 5, "into five slices")
	var/summed = 0
	for(var/obj/item/reagent_containers/food/snacks/slice/meatbread/slice in range(2, run_loc_floor_bottom_left))
		summed += rc_units(slice)
		qdel(slice)
	TEST_ASSERT(abs(summed - total) < 1, "and the reagents are shared out ([summed] of [total])")

/// Off a table (the floor) a knife does not cut a loaf.
/datum/unit_test/dq_p2_reagents/sliceable_is_not_sliced_off_a_table

/datum/unit_test/dq_p2_reagents/sliceable_is_not_sliced_off_a_table/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/sliceable/meatbread/loaf = sn_snack(/obj/item/reagent_containers/food/snacks/sliceable/meatbread)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	rc_click(H, loaf, knife, I_HELP)
	TEST_ASSERT(!QDELETED(loaf), "the loaf stays whole")
	TEST_ASSERT_EQUAL(sn_count(/obj/item/reagent_containers/food/snacks/slice/meatbread), 0, "and no slices are made")

/// A thing with no edge, used on a loaf, may be hidden in it when the person says yes (and a thing as big as the loaf cannot be).
/datum/unit_test/dq_p2_reagents/item_is_hidden_in_a_sliceable

/datum/unit_test/dq_p2_reagents/item_is_hidden_in_a_sliceable/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/sliceable/meatbread/loaf = sn_snack(/obj/item/reagent_containers/food/snacks/sliceable/meatbread)
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	sn_click_hiding(H, loaf, pen, "No")
	TEST_ASSERT_NOTEQUAL(pen.loc, loaf, "a no keeps the pen out")
	sn_click_hiding(H, loaf, pen, "Yes")
	TEST_ASSERT_EQUAL(pen.loc, loaf, "a yes hides it in the loaf")
	TEST_ASSERT(!QDELETED(loaf), "and the loaf is whole")

// ---------------------------------------------------------------------------------------------------------------------
// Batter
// ---------------------------------------------------------------------------------------------------------------------

/// A snack dipped in an open container of batter takes a coating, which uses up batter and makes room for it.
/datum/unit_test/dq_p2_reagents/snack_is_dipped_in_batter

/datum/unit_test/dq_p2_reagents/snack_is_dipped_in_batter/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	var/obj/item/reagent_containers/glass/beaker/large/B = rc_filled(/obj/item/reagent_containers/glass/beaker/large, 0)
	B.reagents.add_reagent(REAGENT_ID_BATTER, 100)
	rc_click(H, B, S, I_HELP)
	TEST_ASSERT_NOTNULL(sn_coating(S), "the snack is coated")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_BATTER) < 100, "batter was used")
	TEST_ASSERT(S.reagents.get_reagent_amount(REAGENT_ID_BATTER) > 0, "and is in the snack")
	var/left = B.reagents.get_reagent_amount(REAGENT_ID_BATTER)
	rc_click(H, B, S, I_HELP)
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_BATTER), left, "a coated snack is not coated twice")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/second = sn_snack()
	var/obj/item/reagent_containers/glass/beaker/vial/V = rc_filled(/obj/item/reagent_containers/glass/beaker/vial, 0)
	V.reagents.add_reagent(REAGENT_ID_BATTER, 1)
	rc_click(H, V, second, I_HELP)
	TEST_ASSERT_NULL(sn_coating(second), "there is not enough batter in a vial for it")

// ---------------------------------------------------------------------------------------------------------------------
// Eggs
// ---------------------------------------------------------------------------------------------------------------------

/// An egg held to an open container is cracked into it, and used up.
/datum/unit_test/dq_p2_reagents/egg_is_cracked_into_a_container

/datum/unit_test/dq_p2_reagents/egg_is_cracked_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/egg/egg = sn_snack(/obj/item/reagent_containers/food/snacks/egg)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, egg, I_HELP)
	TEST_ASSERT(QDELETED(egg), "the egg is used up")
	TEST_ASSERT_EQUAL(B.reagents.get_reagent_amount(REAGENT_ID_EGG), 3, "and is in the beaker")
	var/obj/item/reagent_containers/food/snacks/egg/second = sn_snack(/obj/item/reagent_containers/food/snacks/egg)
	var/obj/item/reagent_containers/glass/beaker/closed = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_use(H, closed)
	rc_click(H, closed, second, I_HELP)
	TEST_ASSERT(!QDELETED(second), "a closed container is not cracked into")

/// A crayon colours an egg, if it is one of the colours an egg takes.
/datum/unit_test/dq_p2_reagents/egg_is_coloured

/datum/unit_test/dq_p2_reagents/egg_is_coloured/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/egg/egg = sn_snack(/obj/item/reagent_containers/food/snacks/egg)
	var/obj/item/pen/crayon/crayon = allocate(/obj/item/pen/crayon/red, run_loc_floor_bottom_left)
	rc_click(H, egg, crayon, I_HELP)
	TEST_ASSERT_EQUAL(egg.icon_state, "egg-red", "the egg is red")
	crayon.colourName = "black"
	rc_click(H, egg, crayon, I_HELP)
	TEST_ASSERT_EQUAL(egg.icon_state, "egg-red", "a colour it does not take leaves it red")

/// A thrown egg is squashed: what it held splashes and it is replaced by a smudge.
/datum/unit_test/dq_p2_reagents/egg_is_squashed_when_it_lands

/datum/unit_test/dq_p2_reagents/egg_is_squashed_when_it_lands/run_gate()
	var/obj/item/reagent_containers/food/snacks/egg/egg = sn_snack(/obj/item/reagent_containers/food/snacks/egg)
	egg.throw_impact(get_step(run_loc_floor_bottom_left, NORTH))
	TEST_ASSERT(QDELETED(egg), "the egg is gone")
	TEST_ASSERT_NOTNULL(sn_find(/obj/effect/decal/cleanable/egg_smudge), "and it left a smudge")

/// A pulsing fruit is torn open into an open container.
/datum/unit_test/dq_p2_reagents/siffruit_is_torn_into_a_container

/datum/unit_test/dq_p2_reagents/siffruit_is_torn_into_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/siffruit/fruit = sn_snack(/obj/item/reagent_containers/food/snacks/siffruit)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	rc_click(H, B, fruit, I_HELP)
	TEST_ASSERT(QDELETED(fruit), "the fruit is used up")
	TEST_ASSERT(B.reagents.get_reagent_amount(REAGENT_ID_SIFSAP) > 0, "and its sap is in the beaker")

// ---------------------------------------------------------------------------------------------------------------------
// Donk-pockets
// ---------------------------------------------------------------------------------------------------------------------

/// A donk-pocket that is heated adds its warming chemicals, is bigger to bite and renamed; seven minutes later it is cold again.
/datum/unit_test/dq_p2_reagents/donkpocket_warms_and_cools

/datum/unit_test/dq_p2_reagents/donkpocket_warms_and_cools/run_gate()
	var/obj/item/reagent_containers/food/snacks/donkpocket/D = sn_snack(/obj/item/reagent_containers/food/snacks/donkpocket)
	var/original = D.name
	var/bite = D.bitesize
	D.heat()
	TEST_ASSERT(D.warm, "it is warm")
	TEST_ASSERT_EQUAL(D.reagents.get_reagent_amount(REAGENT_ID_TRICORDRAZINE), 5, "it holds the warming chemical")
	TEST_ASSERT_EQUAL(D.bitesize, 6, "its bites are bigger")
	TEST_ASSERT_EQUAL(D.name, "warm [original]", "and it is named for it")
	test_time(419 SECONDS)
	TEST_ASSERT(D.warm, "still warm just before the seven minutes")
	test_time(2 SECONDS)
	TEST_ASSERT(!D.warm, "cold after them")
	TEST_ASSERT_EQUAL(D.reagents.get_reagent_amount(REAGENT_ID_TRICORDRAZINE), 0, "the chemical is gone")
	TEST_ASSERT_EQUAL(D.name, original, "and the name is back")
	TEST_ASSERT_NOTEQUAL(bite, 0, "(a bite was something)")

/// A sin-pocket's package is crushed once, and twenty seconds later it is heated.
/datum/unit_test/dq_p2_reagents/sinpocket_is_crushed_and_heats

/datum/unit_test/dq_p2_reagents/sinpocket_is_crushed_and_heats/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket/D = sn_snack(/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket)
	rc_use(H, D)
	TEST_ASSERT(D.has_been_heated, "the package was crushed")
	TEST_ASSERT(!D.warm, "it is not warm yet")
	test_time(21 SECONDS)
	TEST_ASSERT(D.warm, "twenty seconds later it is warm")
	TEST_ASSERT(D.reagents.get_reagent_amount(REAGENT_ID_HYPERZINE) > 0, "with its chemicals")
	var/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket/second = sn_snack(/obj/item/reagent_containers/food/snacks/donkpocket/sinpocket)
	rc_use(H, second)
	rc_use(H, second)
	test_time(21 SECONDS)
	TEST_ASSERT_EQUAL(second.reagents.get_reagent_amount(REAGENT_ID_HYPERZINE), D.reagents.get_reagent_amount(REAGENT_ID_HYPERZINE), "a second crush does not heat it twice")

// ---------------------------------------------------------------------------------------------------------------------
// Cubes
// ---------------------------------------------------------------------------------------------------------------------

/// A wrapped monkey cube is unwrapped in hand, then it is an open container; water makes it a monkey.
/datum/unit_test/dq_p2_reagents/monkey_cube_unwraps_and_expands

/datum/unit_test/dq_p2_reagents/monkey_cube_unwraps_and_expands/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/C = sn_snack(/obj/item/reagent_containers/food/snacks/monkeycube/wrapped)
	TEST_ASSERT(!rc_open(C), "a wrapped cube is shut")
	rc_use(H, C)
	TEST_ASSERT(rc_open(C), "unwrapped, it is open")
	TEST_ASSERT_EQUAL(C.icon_state, "monkeycube", "and drawn bare")
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, C, B, I_HELP)
	TEST_ASSERT(QDELETED(C), "water makes the cube a monkey")
	var/found = FALSE
	for(var/mob/living/carbon/human/monkey in range(2, run_loc_floor_bottom_left))
		if(monkey != H && !monkey.client && monkey.species?.name == "Monkey")
			found = TRUE
			qdel(monkey)
	TEST_ASSERT(found, "a monkey stands where it was")

/// A protein cube expands in water into its slab.
/datum/unit_test/dq_p2_reagents/protein_cube_expands

/datum/unit_test/dq_p2_reagents/protein_cube_expands/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/cube/protein/C = sn_snack(/obj/item/reagent_containers/food/snacks/cube/protein)
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 30)
	rc_click(H, C, B, I_HELP)
	TEST_ASSERT(QDELETED(C), "the cube is gone")
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/proteinslab), "and a slab is left")

// ---------------------------------------------------------------------------------------------------------------------
// What a held item makes of a food
// ---------------------------------------------------------------------------------------------------------------------

/// A rolling pin on dough flattens it.
/datum/unit_test/dq_p2_reagents/rolling_pin_flattens_dough

/datum/unit_test/dq_p2_reagents/rolling_pin_flattens_dough/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/dough/dough = sn_snack(/obj/item/reagent_containers/food/snacks/dough)
	var/obj/item/material/kitchen/rollingpin/pin = allocate(/obj/item/material/kitchen/rollingpin, run_loc_floor_bottom_left)
	rc_click(H, dough, pin, I_HELP)
	TEST_ASSERT(QDELETED(dough), "the dough is gone")
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/sliceable/flatdough), "flat dough is left")
	var/obj/item/reagent_containers/food/snacks/steamtealeaf/leaf = sn_snack(/obj/item/reagent_containers/food/snacks/steamtealeaf)
	rc_click(H, leaf, pin, I_HELP)
	TEST_ASSERT(QDELETED(leaf), "a steamed leaf is rolled too")
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/steamrolltealeaf), "into a rolled leaf")

/// A knife on a raw cutlet makes two rashers of bacon.
/datum/unit_test/dq_p2_reagents/knife_cuts_a_cutlet_into_bacon

/datum/unit_test/dq_p2_reagents/knife_cuts_a_cutlet_into_bacon/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/rawcutlet/cutlet = sn_snack(/obj/item/reagent_containers/food/snacks/rawcutlet)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	rc_click(H, cutlet, knife, I_HELP)
	TEST_ASSERT(QDELETED(cutlet), "the cutlet is gone")
	TEST_ASSERT_EQUAL(sn_count(/obj/item/reagent_containers/food/snacks/rawbacon), 2, "and two rashers are left")

/// A cheese wedge on a burger makes a cheeseburger; a meatball or cutlet on a bun makes a burger and a sausage a hot dog.
/datum/unit_test/dq_p2_reagents/burgers_are_made

/datum/unit_test/dq_p2_reagents/burgers_are_made/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/monkeyburger/burger = sn_snack(/obj/item/reagent_containers/food/snacks/monkeyburger)
	var/obj/item/reagent_containers/food/snacks/cheesewedge/cheese = sn_snack(/obj/item/reagent_containers/food/snacks/cheesewedge)
	rc_click(H, burger, cheese, I_HELP)
	TEST_ASSERT(QDELETED(burger) && QDELETED(cheese), "both are used up")
	var/obj/item/reagent_containers/food/snacks/cheeseburger/made = sn_find(/obj/item/reagent_containers/food/snacks/cheeseburger)
	TEST_ASSERT_NOTNULL(made, "a cheeseburger is made")
	qdel(made)
	var/obj/item/reagent_containers/food/snacks/bun/bun = sn_snack(/obj/item/reagent_containers/food/snacks/bun)
	var/obj/item/reagent_containers/food/snacks/meatball/ball = sn_snack(/obj/item/reagent_containers/food/snacks/meatball)
	rc_click(H, bun, ball, I_HELP)
	TEST_ASSERT(QDELETED(bun) && QDELETED(ball), "a bun and a meatball are used up")
	var/obj/item/reagent_containers/food/snacks/monkeyburger/b2 = sn_find(/obj/item/reagent_containers/food/snacks/monkeyburger)
	TEST_ASSERT_NOTNULL(b2, "a burger is made")
	qdel(b2)
	var/obj/item/reagent_containers/food/snacks/bun/bun2 = sn_snack(/obj/item/reagent_containers/food/snacks/bun)
	var/obj/item/reagent_containers/food/snacks/sausage/sausage = sn_snack(/obj/item/reagent_containers/food/snacks/sausage)
	rc_click(H, bun2, sausage, I_HELP)
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/hotdog), "a sausage in a bun is a hot dog")

/// A chip in a dip comes out dipped, the dip gives some of itself, and a plain item is not taken.
/datum/unit_test/dq_p2_reagents/chip_is_dipped

/datum/unit_test/dq_p2_reagents/chip_is_dipped/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/dip/dip = sn_snack(/obj/item/reagent_containers/food/snacks/dip)
	var/before = rc_units(dip)
	var/obj/item/reagent_containers/food/snacks/chip/chip = sn_snack(/obj/item/reagent_containers/food/snacks/chip)
	rc_click(H, dip, chip, I_HELP)
	TEST_ASSERT(QDELETED(chip), "the chip is used up")
	TEST_ASSERT(rc_units(dip) < before, "the dip gave some")
	TEST_ASSERT_NOTNULL(locate(/obj/item/reagent_containers/food/snacks/chip/cheese) in H, "a dipped chip is in the hand")

/// An empty hand takes a chip from a basket, and the last one leaves the basket's trash.
/datum/unit_test/dq_p2_reagents/chip_is_taken_from_a_basket

/datum/unit_test/dq_p2_reagents/chip_is_taken_from_a_basket/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/chipplate/plate = sn_snack(/obj/item/reagent_containers/food/snacks/chipplate)
	var/before = rc_units(plate)
	rc_click(H, plate, null, I_HELP)
	TEST_ASSERT(rc_units(plate) < before, "a chip's worth left the basket")
	TEST_ASSERT_NOTNULL(locate(/obj/item/reagent_containers/food/snacks/chip) in H, "and a chip is in the hand")

// ---------------------------------------------------------------------------------------------------------------------
// Customizable food
// ---------------------------------------------------------------------------------------------------------------------

/// A food put on bread makes a sandwich of it; another slice shuts it; a thing that is already custom is refused.
/datum/unit_test/dq_p2_reagents/sandwich_is_built

/datum/unit_test/dq_p2_reagents/sandwich_is_built/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/slice/bread/bread = sn_snack(/obj/item/reagent_containers/food/snacks/slice/bread)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/filling = sn_snack()
	rc_click(H, bread, filling, I_HELP)
	var/obj/item/reagent_containers/food/snacks/customizable/sandwich/sandwich = sn_find(/obj/item/reagent_containers/food/snacks/customizable/sandwich)
	TEST_ASSERT_NOTNULL(sandwich, "a sandwich is made")
	if(!sandwich)
		return
	TEST_ASSERT(QDELETED(bread), "the bread is used")
	TEST_ASSERT_EQUAL(length(sandwich.ingredients), 1, "with the filling in it")
	TEST_ASSERT(findtext(sandwich.name, filling.name), "named for it: [sandwich.name]")
	var/obj/item/reagent_containers/food/snacks/slice/bread/top = sn_snack(/obj/item/reagent_containers/food/snacks/slice/bread)
	rc_click(H, sandwich, top, I_HELP)
	TEST_ASSERT(QDELETED(top), "a second slice closes it")
	TEST_ASSERT(sandwich.addTop, "with a top")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/more = sn_snack()
	rc_click(H, sandwich, more, I_HELP)
	TEST_ASSERT_EQUAL(length(sandwich.ingredients), 2, "and one more thing goes in")

/// A bun makes a custom burger of any food, a bowl a soup, a flat dough a pizza, and none takes a custom food.
/datum/unit_test/dq_p2_reagents/custom_dishes_are_started

/datum/unit_test/dq_p2_reagents/custom_dishes_are_started/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/bun/bun = sn_snack(/obj/item/reagent_containers/food/snacks/bun)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/filling = sn_snack()
	rc_click(H, bun, filling, I_HELP)
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/customizable/burger), "a bun and a food make a burger")
	var/obj/item/trash/bowl/bowl = allocate(/obj/item/trash/bowl, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/second = sn_snack()
	rc_click(H, bowl, second, I_HELP)
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/customizable/soup), "a bowl and a food make a soup")
	var/obj/item/reagent_containers/food/snacks/sliceable/flatdough/dough = sn_snack(/obj/item/reagent_containers/food/snacks/sliceable/flatdough)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/third = sn_snack()
	rc_click(H, dough, third, I_HELP)
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/customizable/pizza), "a flat dough and a food make a pizza")
	var/obj/item/reagent_containers/food/snacks/spagetti/pasta = sn_snack(/obj/item/reagent_containers/food/snacks/spagetti)
	var/obj/item/reagent_containers/food/snacks/aesirsalad/fourth = sn_snack()
	rc_click(H, pasta, fourth, I_HELP)
	TEST_ASSERT_NOTNULL(sn_find(/obj/item/reagent_containers/food/snacks/customizable/pasta), "a spaghetti and a food make a pasta dish")

/// A custom food is not put into another (no recursive food).
/datum/unit_test/dq_p2_reagents/custom_food_is_not_recursive

/datum/unit_test/dq_p2_reagents/custom_food_is_not_recursive/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/bun/bun = sn_snack(/obj/item/reagent_containers/food/snacks/bun)
	var/obj/item/reagent_containers/food/snacks/customizable/soup/soup = sn_snack(/obj/item/reagent_containers/food/snacks/customizable/soup)
	rc_click(H, bun, soup, I_HELP)
	TEST_ASSERT(!QDELETED(bun), "the bun is not used")
	TEST_ASSERT(!QDELETED(soup), "nor the soup")

/// A shard on a sandwich is hidden in it; whoever eats it themselves is cut.
/datum/unit_test/dq_p2_reagents/sandwich_hides_a_shard

/datum/unit_test/dq_p2_reagents/sandwich_hides_a_shard/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/csandwich/sandwich = sn_snack(/obj/item/reagent_containers/food/snacks/csandwich)
	var/obj/item/material/shard/shard = allocate(/obj/item/material/shard, run_loc_floor_bottom_left)
	rc_click(H, sandwich, shard, I_HELP)
	TEST_ASSERT_EQUAL(shard.loc, sandwich, "the shard is in the sandwich")
	var/obj/item/reagent_containers/food/snacks/aesirsalad/layer = sn_snack()
	rc_click(H, sandwich, layer, I_HELP)
	TEST_ASSERT_EQUAL(length(sandwich.ingredients), 1, "a food is layered on")
	TEST_ASSERT(QDELETED(layer) || layer.loc == sandwich, "inside it")

/// A knife on a slab of meat cuts three cutlets; on a worm's meat it also cuts what is inside.
/datum/unit_test/dq_p2_reagents/knife_cuts_meat_into_cutlets

/datum/unit_test/dq_p2_reagents/knife_cuts_meat_into_cutlets/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/meat/meat = sn_snack(/obj/item/reagent_containers/food/snacks/meat)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife, run_loc_floor_bottom_left)
	rc_click(H, meat, knife, I_HELP)
	TEST_ASSERT(QDELETED(meat), "the meat is gone")
	TEST_ASSERT_EQUAL(sn_count(/obj/item/reagent_containers/food/snacks/rawcutlet), 3, "and three cutlets are left")
	var/obj/item/reagent_containers/food/snacks/meat/worm/worm = sn_snack(/obj/item/reagent_containers/food/snacks/meat/worm)
	rc_click(H, worm, knife, I_HELP)
	TEST_ASSERT(QDELETED(worm), "the worm's meat is gone")
	TEST_ASSERT_EQUAL(sn_count(/obj/item/reagent_containers/food/snacks/rawcutlet), 6, "three more cutlets are left, and something else spilled out")

/// A fork scoops some of a snack up, taking its share of the reagents.
/datum/unit_test/dq_p2_reagents/fork_scoops_a_snack

/datum/unit_test/dq_p2_reagents/fork_scoops_a_snack/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/food/snacks/aesirsalad/S = sn_snack()
	var/obj/item/material/kitchen/utensil/fork/fork = allocate(/obj/item/material/kitchen/utensil/fork, run_loc_floor_bottom_left)
	var/before = rc_units(S)
	rc_click(H, S, fork, I_HELP)
	TEST_ASSERT(rc_units(S) < before, "some of the snack is on the fork")
	TEST_ASSERT(fork.reagents.total_volume > 0, "it holds it")
	TEST_ASSERT_EQUAL(sn_bites(S), 1, "and a bite is counted")

// ---------------------------------------------------------------------------------------------------------------------
// Pizza boxes
// ---------------------------------------------------------------------------------------------------------------------

/// The person writes on the tag of a closed box with a pen, giving `text` when asked.
/datum/unit_test/dq_p2_reagents/proc/sn_tag_box(mob/living/carbon/human/H, obj/item/pizzabox/box, obj/item/pen/pen, text)
	sn_click_answering(H, box, pen, text)

/// Using a box opens and shuts it, and an open box with a pizza is made messy; a stack does not open.
/datum/unit_test/dq_p2_reagents/pizza_box_opens_and_shuts

/datum/unit_test/dq_p2_reagents/pizza_box_opens_and_shuts/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/pizzabox/margherita/box = allocate(/obj/item/pizzabox/margherita, run_loc_floor_bottom_left)
	TEST_ASSERT(!box.open, "it starts shut")
	rc_use(H, box)
	TEST_ASSERT(box.open, "using it opens it")
	TEST_ASSERT(box.ismessy, "an open box with a pizza is messy")
	rc_use(H, box)
	TEST_ASSERT(!box.open, "using it again shuts it")

/// An empty hand takes the pizza out of an open box.
/datum/unit_test/dq_p2_reagents/pizza_is_taken_out_of_a_box

/datum/unit_test/dq_p2_reagents/pizza_is_taken_out_of_a_box/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/pizzabox/margherita/box = allocate(/obj/item/pizzabox/margherita, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/sliceable/pizza/pizza = box.pizza
	rc_click(H, box, null, I_HELP)
	TEST_ASSERT_EQUAL(box.pizza, pizza, "a shut box gives nothing")
	rc_use(H, box)
	H.drop_item()
	rc_click(H, box, null, I_HELP)
	TEST_ASSERT_NULL(box.pizza, "an open one gives its pizza")
	TEST_ASSERT_EQUAL(pizza.loc, H, "to the hand")

/// A pizza is put into an open box and refused by a shut one.
/datum/unit_test/dq_p2_reagents/pizza_is_put_in_a_box

/datum/unit_test/dq_p2_reagents/pizza_is_put_in_a_box/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/pizzabox/box = allocate(/obj/item/pizzabox, run_loc_floor_bottom_left)
	var/obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita/pizza = sn_snack(/obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita)
	rc_click(H, box, pizza, I_HELP)
	TEST_ASSERT_NULL(box.pizza, "a shut box does not take it")
	box.open = TRUE
	changed(box)
	rc_click(H, box, pizza, I_HELP)
	TEST_ASSERT_EQUAL(box.pizza, pizza, "an open one does")

/// A box stacks on a shut box up to five high; an open box is refused; a pen writes on the top box's tag.
/datum/unit_test/dq_p2_reagents/pizza_boxes_stack_and_are_tagged

/datum/unit_test/dq_p2_reagents/pizza_boxes_stack_and_are_tagged/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/pizzabox/bottom = allocate(/obj/item/pizzabox, run_loc_floor_bottom_left)
	var/obj/item/pizzabox/top = allocate(/obj/item/pizzabox, run_loc_floor_bottom_left)
	rc_click(H, bottom, top, I_HELP)
	TEST_ASSERT_EQUAL(length(bottom.boxes), 1, "a box is stacked")
	TEST_ASSERT_EQUAL(top.loc, bottom, "inside the pile")
	var/obj/item/pizzabox/open_box = allocate(/obj/item/pizzabox, run_loc_floor_bottom_left)
	open_box.open = TRUE
	changed(open_box)
	rc_click(H, bottom, open_box, I_HELP)
	TEST_ASSERT_EQUAL(length(bottom.boxes), 1, "an open box is not stacked")
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	sn_tag_box(H, bottom, pen, "Hot")
	TEST_ASSERT_EQUAL(top.boxtag, "Hot", "the tag is written on the top box")
	for(var/i in 1 to 5)
		var/obj/item/pizzabox/more = allocate(/obj/item/pizzabox, run_loc_floor_bottom_left)
		rc_click(H, bottom, more, I_HELP)
	TEST_ASSERT_EQUAL(length(bottom.boxes) + 1, 5, "five boxes are the most")
