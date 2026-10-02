/// The player-facing pouring helper honors the configured dose and conserves liquid across refusals.
/datum/unit_test/interim_standard_pour_amount/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/reagent_containers/glass/beaker/source = allocate(/obj/item/reagent_containers/glass/beaker, T)
	var/obj/item/reagent_containers/glass/beaker/target = allocate(/obj/item/reagent_containers/glass/beaker, T)
	TEST_ASSERT(source.is_open_container() && target.is_open_container(), "both real beakers are open for pouring")
	source.reagents.add_reagent(REAGENT_ID_WATER, 30)
	source.amount_per_transfer_from_this = 7
	TEST_ASSERT_EQUAL(source.standard_pour_into(user, target), 1, "the pouring helper handles an open target")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 23, "the configured seven units leave the source")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 7, "the target receives the configured seven units")
	source.amount_per_transfer_from_this = 3
	source.standard_pour_into(user, target)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 20, "a changed dose applies to the next pour")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 10, "the next pour adds the changed dose")
	TEST_ASSERT_EQUAL(source.reagents.total_volume + target.reagents.total_volume, 30, "successive pours conserve liquid")
	target.reagents.add_reagent(REAGENT_ID_WATER, target.reagents.get_free_space())
	var/full_volume = target.reagents.total_volume
	TEST_ASSERT_EQUAL(source.standard_pour_into(user, target), 1, "the helper handles a full-target refusal")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 20, "a full target does not debit the source")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, full_volume, "a full target gains no liquid")
	target.reagents.clear_reagents()
	source.amount_per_transfer_from_this = 25
	source.standard_pour_into(user, target)
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 0, "an oversized requested dose empties the source")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 20, "only the source's remaining liquid is transferred")
	TEST_ASSERT_EQUAL(source.standard_pour_into(user, target), 1, "the helper handles an empty-source refusal")
	TEST_ASSERT_EQUAL(source.reagents.total_volume, 0, "an empty-source refusal leaves the source empty")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 20, "an empty-source refusal leaves the target unchanged")
	var/obj/item/cell/closed = allocate(/obj/item/cell, T)
	TEST_ASSERT_EQUAL(target.standard_pour_into(user, closed), 0, "a non-container target is not handled as a pour")
	TEST_ASSERT_EQUAL(target.reagents.total_volume, 20, "an invalid target cannot consume liquid")
