/// Actual foods keep integer and fractional bite sizes through their real ingest transfer.
/datum/unit_test/interim_food_bite_data/Run()
	var/static/list/cases = list(
		list(/obj/item/reagent_containers/food/snacks/slice/bigbeanburrito, 6),
		list(/obj/item/reagent_containers/food/snacks/slice/bigbeanburrito/filled, 6),
		list(/obj/item/reagent_containers/food/snacks/lobster, 0.1),
		list(/obj/item/reagent_containers/food/snacks/sliceable/monkfishremains, 0.01),
		list(/obj/item/reagent_containers/food/snacks/meat, 1.5),
		list(/obj/item/reagent_containers/food/snacks/meat/grubmeat, 6),
		list(/obj/item/reagent_containers/food/snacks/meat/worm, 3),
		list(/obj/item/reagent_containers/food/snacks/meat/chicken, 1.5),
		list(/obj/item/reagent_containers/food/snacks/meat/syntiflesh, 1.5),
	)
	var/turf/T = run_loc_floor_bottom_left
	for(var/list/entry as anything in cases)
		var/mob/living/carbon/human/eater = allocate(/mob/living/carbon/human, T)
		var/obj/item/reagent_containers/food/snacks/food = allocate(entry[1], T)
		TEST_ASSERT_EQUAL(food.bitesize, entry[2], "the actual food retains its exact original initialized bite size: [entry[1]]")
		TEST_ASSERT_EQUAL(eater.species.bite_mod, 1, "the actual human fixture uses the standard bite multiplier")
		var/original_source = food.reagents.total_volume
		var/original_ingested = eater.ingested.total_volume
		TEST_ASSERT(original_source > entry[2], "the actual food starts with more than one full bite: [entry[1]]")
		TEST_ASSERT(eater.put_in_active_hand(food), "the actual food starts in the eater's real hand: [entry[1]]")
		TEST_ASSERT_EQUAL(food.finish_feeding(eater, eater, FALSE, null), TRUE, "the actual food performs its real feeding effect: [entry[1]]")
		TEST_ASSERT(abs(food.reagents.total_volume - (original_source - entry[2])) < 0.001, "the actual bite debits the exact integer or fractional portion: [entry[1]]")
		if(food.type == /obj/item/reagent_containers/food/snacks/sliceable/monkfishremains)
			// The original 0.01 bite splits into 0.008 nutriment and 0.002 carbon;
			// both fall below the real holder's minimum and are discarded.
			TEST_ASSERT_EQUAL(original_source, 25, "actual monkfish remains start with twenty nutrient and five carbon units")
			TEST_ASSERT_EQUAL(original_ingested, 0, "the actual ingest holder starts empty before the tiny monkfish bite")
			TEST_ASSERT(0.008 < MINIMUM_CHEMICAL_VOLUME && 0.002 < MINIMUM_CHEMICAL_VOLUME, "both original monkfish bite components fall below the actual reagent retention threshold")
			TEST_ASSERT_EQUAL(eater.ingested.total_volume, 0, "the actual tiny monkfish bite debits its source but retains no sub-threshold ingest reagents")
			TEST_ASSERT_EQUAL(eater.ingested.get_reagent_amount(REAGENT_ID_NUTRIMENT), 0, "the actual tiny nutrient portion is discarded by the ingest holder")
			TEST_ASSERT_EQUAL(eater.ingested.get_reagent_amount(REAGENT_ID_CARBON), 0, "the actual tiny carbon portion is discarded by the ingest holder")
		else
			TEST_ASSERT(abs(eater.ingested.total_volume - (original_ingested + entry[2])) < 0.001, "the real ingest holder receives the exact integer or fractional portion: [entry[1]]")
		TEST_ASSERT_EQUAL(food.bitecount, 1, "the actual food counts exactly one completed bite: [entry[1]]")
		TEST_ASSERT(!QDELETED(food), "the real partial bite preserves its exact food item: [entry[1]]")
		TEST_ASSERT_EQUAL(eater.get_active_hand(), food, "the real partial bite preserves the exact food hand slot: [entry[1]]")
