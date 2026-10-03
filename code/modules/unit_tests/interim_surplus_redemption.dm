/// All real surplus voucher families refuse release first, then deliver one real reward on retry.
/datum/unit_test/interim_surplus_redemption
	var/voucher_type = /obj/item/surplus_voucher/com

/datum/unit_test/interim_surplus_redemption/engineering
	voucher_type = /obj/item/surplus_voucher/eng

/datum/unit_test/interim_surplus_redemption/medical
	voucher_type = /obj/item/surplus_voucher/med

/datum/unit_test/interim_surplus_redemption/science
	voucher_type = /obj/item/surplus_voucher/sci

/datum/unit_test/interim_surplus_redemption/security
	voucher_type = /obj/item/surplus_voucher/sec

/datum/unit_test/interim_surplus_redemption/service
	voucher_type = /obj/item/surplus_voucher/ser

/datum/unit_test/interim_surplus_redemption/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/surplus_voucher/voucher = allocate(voucher_type, T)
	TEST_ASSERT(user.put_in_active_hand(voucher), "the actual departmental voucher occupies the active hand")
	var/list/before = contents_of(T, /obj)
	add_trait(voucher, TRAIT_NODROP, "interim_surplus_redemption")
	TEST_ASSERT(voucher.loc.release_refusal(voucher, user), "the actual sticky voucher refuses release")
	TEST_ASSERT_EQUAL(voucher.interaction_redeem(user, voucher, null), FALSE, "the actual redemption entry refuses an unconsumable voucher")
	own_turf_contents(T)
	TEST_ASSERT(!QDELETED(voucher), "refused redemption preserves the original voucher")
	TEST_ASSERT_EQUAL(voucher.loc, user, "refused redemption preserves the original holder")
	TEST_ASSERT_EQUAL(user.get_active_hand(), voucher, "refused redemption preserves the exact active-hand identity")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj) - before), 0, "refused redemption creates no reward object")
	remove_trait(voucher, TRAIT_NODROP, "interim_surplus_redemption")
	TEST_ASSERT_EQUAL(voucher.interaction_redeem(user, voucher, null), TRUE, "retrying the actual redemption entry succeeds after release is allowed")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(voucher), "actual successful redemption consumes the original departmental voucher")
	TEST_ASSERT_NULL(user.get_active_hand(), "successful redemption vacates the original voucher hand slot")
	var/list/deliveries = contents_of(T, /obj) - before
	TEST_ASSERT_EQUAL(length(deliveries), 1, "actual successful redemption creates exactly one top-level reward")
	var/obj/reward = deliveries[1]
	TEST_ASSERT(reward != voucher, "the actual delivered object is a new reward rather than the original voucher")
	TEST_ASSERT(!QDELETED(reward), "the actual delivered reward is alive after redemption")
	TEST_ASSERT_EQUAL(reward.loc, T, "the actual reward lands on the original delivery floor")
	TEST_ASSERT(!(istype(reward, /obj/item/surplus_voucher)), "redemption delivers a real reward instead of another voucher")
	TEST_ASSERT_EQUAL(length(contents_of(user, /obj/item/surplus_voucher)), 0, "successful redemption leaves no stale departmental voucher in the actor inventory")
