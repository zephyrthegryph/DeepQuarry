/// Destination capacity clamps the source debit before scaling a real mixed solution.
/datum/unit_test/interim_reagent_scaled_capacity/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/reagent_containers/glass/beaker/source = allocate(/obj/item/reagent_containers/glass/beaker, T)
	var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker, T)
	source.reagents.add_reagent(REAGENT_ID_WATER, 30)
	source.reagents.add_reagent(REAGENT_ID_ETHANOL, 10)
	var/initial_target_water = target.reagents.maximum_volume - 5
	target.reagents.add_reagent(REAGENT_ID_WATER, initial_target_water)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 40, "the actual source holds its full three-to-one mixture")
	TEST_ASSERT_EQUAL(target.reagents.get_free_space(), 5, "the actual target has exactly five units of capacity")
	TEST_ASSERT_EQUAL(source.reagents.trans_to_holder(target.reagents, 20, multiplier = 2), 2.5, "scaled capacity limits the actual source debit to two and a half units")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 37.5, "the actual source loses only the capacity-limited debit")
	TEST_ASSERT_EQUAL(source.reagents.get_reagent_amount(REAGENT_ID_WATER), 28.125, "the source water debit respects the original mixture ratio")
	TEST_ASSERT_EQUAL(source.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 9.375, "the source ethanol debit respects the original mixture ratio")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, target.reagents.maximum_volume, "the scaled actual delivery exactly fills destination capacity")
	TEST_ASSERT_EQUAL(target.reagents.get_reagent_amount(REAGENT_ID_WATER), initial_target_water + 3.75, "the target receives its doubled water share")
	TEST_ASSERT_EQUAL(target.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 1.25, "the target receives its doubled ethanol share")
	TEST_ASSERT(!source.reagents.trans_to_holder(target.reagents, 20, multiplier = 2), "the now-full target rejects a repeated scaled transfer")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 37.5, "the full-target rejection preserves remaining source volume")

/// A capacity-limited scaled copy preserves both real source components while delivering their original ratio.
/datum/unit_test/interim_reagent_scaled_copy_capacity/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/reagent_containers/glass/beaker/source = allocate(/obj/item/reagent_containers/glass/beaker, T)
	var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker, T)
	source.reagents.add_reagent(REAGENT_ID_WATER, 30)
	source.reagents.add_reagent(REAGENT_ID_ETHANOL, 10)
	var/initial_target_water = target.reagents.maximum_volume - 1
	target.reagents.add_reagent(REAGENT_ID_WATER, initial_target_water)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 40, "the actual source holds its full three-to-one mixture")
	TEST_ASSERT_EQUAL(target.reagents.get_free_space(), 1, "the actual target has exactly one unit of capacity")
	TEST_ASSERT_EQUAL(source.reagents.trans_to_holder(target.reagents, 8, multiplier = 0.5, copy = TRUE), 2, "the scaled copy samples only the two source units that fit")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 40, "copying preserves actual total source volume")
	TEST_ASSERT_EQUAL(source.reagents.get_reagent_amount(REAGENT_ID_WATER), 30, "copying preserves the actual source water amount")
	TEST_ASSERT_EQUAL(source.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 10, "copying preserves the actual source ethanol amount")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, target.reagents.maximum_volume, "the actual copied delivery exactly fills capacity")
	TEST_ASSERT_EQUAL(target.reagents.get_reagent_amount(REAGENT_ID_WATER), initial_target_water + 0.75, "the target receives its capacity-limited copied water share")
	TEST_ASSERT_EQUAL(target.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 0.25, "the target receives its capacity-limited copied ethanol share")
