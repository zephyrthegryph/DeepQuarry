/// Real sticker application must consume the original before adding its descriptions to a target.
/datum/unit_test/interim_gold_sticker_sticky_application/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/target = allocate(/obj/item/pen, T)
	var/obj/item/clothing/accessory/gold_sticker/sticker = allocate(/obj/item/clothing/accessory/gold_sticker, T)
	var/original_desc = target.desc
	var/original_fluff = target.description_fluff
	var/sticker_name = "[sticker]"
	var/sticker_desc = sticker.desc
	TEST_ASSERT(user.Adjacent(target), "the actual target is adjacent for the real application route")
	TEST_ASSERT(user.put_in_active_hand(sticker), "the actor holds exact original sticker")
	add_trait(sticker, TRAIT_NODROP, "interim_gold_sticker")
	TEST_ASSERT(user.release_refusal(sticker, user), "actual inventory refuses sticky sticker consumption")
	sticker.afterattack(target, user)
	TEST_ASSERT(!QDELETED(sticker), "refused application preserves exact original sticker")
	TEST_ASSERT_EQUAL(user.get_active_hand(), sticker, "refused application preserves original source hand")
	TEST_ASSERT_EQUAL(sticker.loc, user, "refused application preserves inventory containment")
	TEST_ASSERT_EQUAL(target.desc, original_desc, "refused application changes no target description")
	TEST_ASSERT_EQUAL(target.description_fluff, original_fluff, "refused application changes no target extra description")
	remove_trait(sticker, TRAIT_NODROP, "interim_gold_sticker")
	sticker.afterattack(target, user)
	TEST_ASSERT(QDELETED(sticker), "allowed application consumes exact original sticker")
	TEST_ASSERT_NULL(user.get_active_hand(), "allowed consumption clears actual source hand")
	TEST_ASSERT_EQUAL(target.desc, "[original_desc] It has a [sticker_name] stuck to it!", "one consumed original adds exactly its actual sticker description")
	TEST_ASSERT_EQUAL(target.description_fluff, "[original_fluff] Attached to it is [sticker_desc]", "one consumed original adds exactly its original extra description")
	TEST_ASSERT(!QDELETED(target), "actual application preserves exact original target")
	TEST_ASSERT_EQUAL(target.loc, T, "actual application preserves original target location")
