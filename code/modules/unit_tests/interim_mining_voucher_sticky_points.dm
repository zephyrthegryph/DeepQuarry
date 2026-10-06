/// The actual answered equipment choice cannot mint points while its original voucher refuses consumption.
/datum/unit_test/om/interim_mining_voucher_sticky_points/run_om(list/made)
	test_prompts_reset()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/mineral/equipment_vendor/vendor = allocate(/obj/machinery/mineral/equipment_vendor, T)
	var/obj/item/mining_voucher/voucher = allocate(/obj/item/mining_voucher, T)
	TEST_ASSERT_NULL(locate_within(T, /obj/item/card/mining_point_card), "actual fixture starts without mining-point rewards")
	TEST_ASSERT(user.put_in_active_hand(voucher), "actor holds exact original mining voucher")
	add_trait(voucher, TRAIT_NODROP, "interim_mining_points")
	TEST_ASSERT(user.release_refusal(voucher, user), "actual inventory refuses sticky original voucher")
	vendor.redeem_voucher(voucher, user)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 1, "actual redemption opens one real equipment selection")
	var/datum/prompt/choice/first = GLOB.test_prompts[1]
	made += first
	TEST_ASSERT_EQUAL(first.answerer, user, "actual equipment choice retains original explicit actor")
	TEST_ASSERT("1000 Points" in first.choices, "actual equipment choice offers its real points reward")
	test_prompt_answer(first, "1000 Points")
	TEST_ASSERT(!QDELETED(voucher), "refused redemption preserves original voucher alive")
	TEST_ASSERT_EQUAL(user.get_active_hand(), voucher, "refused redemption preserves exact original hand")
	TEST_ASSERT_EQUAL(voucher.loc, user, "refused redemption preserves original inventory location")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/card/mining_point_card), "refused redemption emits no mining-point card")
	remove_trait(voucher, TRAIT_NODROP, "interim_mining_points")
	vendor.redeem_voucher(voucher, user)
	TEST_ASSERT_EQUAL(length(GLOB.test_prompts), 2, "legitimate retry opens a fresh real equipment choice")
	var/datum/prompt/choice/second = GLOB.test_prompts[2]
	made += second
	test_prompt_answer(second, "1000 Points")
	TEST_ASSERT(QDELETED(voucher), "allowed redemption consumes exact original voucher")
	TEST_ASSERT_NULL(user.get_active_hand(), "allowed redemption clears original source hand")
	var/rewards = 0
	for(var/obj/item/card/mining_point_card/card in T)
		made += card
		rewards++
		TEST_ASSERT_EQUAL(card.type, /obj/item/card/mining_point_card, "actual points branch emits exact declared reward type")
		TEST_ASSERT_EQUAL(card.mine_points, 1000, "actual reward contains exactly its promised thousand points")
	TEST_ASSERT_EQUAL(rewards, 1, "allowed redemption emits exactly one card for the original voucher")
