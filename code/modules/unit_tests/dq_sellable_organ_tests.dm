#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// An organ sold in a freezer crate is refused when it is damaged ("damaged on arrival") and accepted when whole.
/datum/unit_test/dq_sellable_organ_damaged_on_arrival

/datum/unit_test/dq_sellable_organ_damaged_on_arrival/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/crate/freezer/crate = allocate(/obj/structure/closet/crate/freezer, T)
	var/obj/item/organ/internal/heart/heart = allocate(/obj/item/organ/internal/heart, crate)
	var/datum/sellable/organ/profile = get_sellable_profile(/datum/sellable/organ)
	TEST_ASSERT_NOTNULL(profile, "the organ sellable profile exists")
	TEST_ASSERT_NULL(profile.sell_error(heart), "a whole organ in a freezer crate can be sold")
	heart.set_damage(5)
	TEST_ASSERT_EQUAL(profile.sell_error(heart), "Error: Product was damaged on arrival.", "a damaged organ is refused")

#endif
