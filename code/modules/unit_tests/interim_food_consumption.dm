/// A partial snack survives; finishing it releases the hand and leaves its trash.
/datum/unit_test/interim_snack_consumption_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/eater = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/food/snacks/snack = allocate(/obj/item/reagent_containers/food/snacks, T)
	snack.trash = /obj/item/trash/plate
	snack.reagents.add_reagent(REAGENT_ID_NUTRIMENT, 1)
	TEST_ASSERT(eater.put_in_active_hand(snack), "the eater holds the snack")
	snack.On_Consume(eater, eater)
	TEST_ASSERT(!QDELETED(snack), "a snack with remaining contents is preserved")
	TEST_ASSERT_EQUAL(snack.loc, eater, "a partial snack stays in the eater's hand")
	snack.reagents.clear_reagents()
	snack.On_Consume(eater, eater)
	TEST_ASSERT(QDELETED(snack), "the finished snack is consumed")
	TEST_ASSERT(!eater.is_in_hands(snack), "the consumed snack leaves the inventory hand")
	TEST_ASSERT(istype(eater.get_active_hand(), /obj/item/trash/plate), "finishing the snack leaves its plate in the free hand")

/// The lowercase consumption callback has the same item lifecycle contract.
/datum/unit_test/interim_snack_serving_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/eater = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/food/snacks/snack = allocate(/obj/item/reagent_containers/food/snacks, T)
	TEST_ASSERT(eater.put_in_active_hand(snack), "the eater holds the serving")
	snack.on_consume(eater)
	TEST_ASSERT(QDELETED(snack), "an empty serving is consumed")
	TEST_ASSERT_NULL(eater.get_active_hand(), "consuming an unwrapped serving frees the hand")

/// Finishing a disposable drink consumes its container and returns its trash.
/datum/unit_test/interim_drink_consumption_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/eater = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/food/drinks/drink = allocate(/obj/item/reagent_containers/food/drinks, T)
	drink.trash = /obj/item/trash/candy
	drink.reagents.clear_reagents()
	TEST_ASSERT(eater.put_in_active_hand(drink), "the drinker holds the disposable container")
	drink.On_Consume(eater, eater, FALSE)
	TEST_ASSERT(!QDELETED(drink), "an unchanged empty container is preserved")
	drink.On_Consume(eater, eater, TRUE)
	TEST_ASSERT(QDELETED(drink), "finishing the disposable drink consumes its container")
	TEST_ASSERT(!eater.is_in_hands(drink), "the consumed container leaves the inventory hand")
	TEST_ASSERT(istype(eater.get_active_hand(), /obj/item/trash/candy), "the empty wrapper is returned to the drinker's hand")
