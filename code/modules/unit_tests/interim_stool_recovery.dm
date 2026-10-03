/// Actual wrench dismantling consumes held stools and returns their material only after release.
/datum/unit_test/interim_stool_wrench_recovery
	var/stool_type = /obj/item/stool
	var/padded = FALSE
	var/sticky = FALSE

/datum/unit_test/interim_stool_wrench_recovery/padded
	stool_type = /obj/item/stool/padded
	padded = TRUE

/datum/unit_test/interim_stool_wrench_recovery/sticky
	sticky = TRUE

/datum/unit_test/interim_stool_wrench_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/stool/stool = allocate(stool_type, T)
	var/obj/item/tool/wrench/tool = allocate(/obj/item/tool/wrench, T)
	TEST_ASSERT_EQUAL(stool.material.name, MAT_STEEL, "the actual stool initializes its steel frame")
	TEST_ASSERT_EQUAL(!!stool.padding_material, padded, "the actual variant initializes the expected padding")
	if(padded)
		TEST_ASSERT_EQUAL(stool.padding_material.name, MAT_CARPET, "the actual padded stool initializes carpet padding")
	TEST_ASSERT(user.put_in_active_hand(stool), "the real stool occupies the active hand before dismantling")
	TEST_ASSERT(user.put_in_inactive_hand(tool), "the real wrench occupies the other hand")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack)), 0, "the floor starts without returned material")
	if(sticky)
		add_trait(stool, TRAIT_NODROP, "interim_stool_wrench_recovery")
		TEST_ASSERT(stool.loc.release_refusal(stool, user), "the actual sticky stool refuses release")
		TEST_ASSERT_EQUAL(stool.wrench_act(user, tool), FALSE, "actual wrench dismantling refuses a stool that cannot be released")
		own_turf_contents(T)
		TEST_ASSERT(!QDELETED(stool), "refused dismantling preserves the original stool")
		TEST_ASSERT_EQUAL(stool.loc, user, "refused dismantling preserves the original holder")
		TEST_ASSERT_EQUAL(user.get_active_hand(), stool, "refused dismantling preserves the original hand slot")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack)), 0, "refused dismantling creates no duplicate material")
		remove_trait(stool, TRAIT_NODROP, "interim_stool_wrench_recovery")
	else
		TEST_ASSERT_EQUAL(stool.wrench_act(user, tool), TRUE, "actual wrench dismantling reports success")
		own_turf_contents(T)
		TEST_ASSERT(QDELETED(stool), "successful dismantling consumes the original stool")
		TEST_ASSERT_NULL(user.get_active_hand(), "successful dismantling clears the original stool hand slot")
		TEST_ASSERT_NULL(locate_within(T, /obj/item/stool), "dismantling leaves no duplicate stool")
		var/steel_amount = 0
		var/carpet_amount = 0
		var/other_amount = 0
		for(var/obj/item/stack/product as anything in contents_of(T, /obj/item/stack))
			TEST_ASSERT_EQUAL(product.loc, T, "every returned material stack stays on the original floor")
			if(product.type == /obj/item/stack/material/steel)
				steel_amount += product.get_amount()
			else if(product.type == /obj/item/stack/tile/carpet)
				carpet_amount += product.get_amount()
			else
				other_amount += product.get_amount()
		TEST_ASSERT_EQUAL(steel_amount, 1, "actual dismantling returns exactly one steel frame sheet")
		TEST_ASSERT_EQUAL(carpet_amount, padded ? 1 : 0, "actual dismantling returns exactly its installed carpet padding")
		TEST_ASSERT_EQUAL(other_amount, 0, "dismantling returns no unrelated material")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), tool, "both outcomes preserve the original wrench hand slot")
