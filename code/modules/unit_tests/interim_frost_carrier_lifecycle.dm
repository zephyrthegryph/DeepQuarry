/// Actual range dispatch spends the frost carrier only when it reaches its endpoint on a turf.
/datum/unit_test/interim_frost_carrier_range_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/projectile/bullet/frostshotgun/carrier = allocate(/obj/item/projectile/bullet/frostshotgun, T)
	carrier.range = 2
	carrier.Range()
	TEST_ASSERT(!QDELETED(carrier), "the actual frost carrier survives a remaining range step")
	TEST_ASSERT_EQUAL(carrier.range, 1, "actual projectile range dispatch decrements the carrier's range")
	TEST_ASSERT_EQUAL(carrier.loc, T, "the surviving carrier remains on its actual turf")
	carrier.Range()
	TEST_ASSERT(QDELETED(carrier), "the final actual range step immediately consumes the spent carrier")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/projectile/bullet/frostshotgun), "the spent carrier leaves no projectile on its original turf")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/projectile/energy/frostsphere)), 0, "range expiry alone does not create shotgun submunitions")
	var/obj/item/projectile/bullet/frostshotgun/parked = allocate(/obj/item/projectile/bullet/frostshotgun, null)
	parked.range = 1
	parked.Range()
	TEST_ASSERT(!QDELETED(parked), "the existing nullspace range guard preserves an unlaunched carrier")
	TEST_ASSERT_EQUAL(parked.range, 0, "the nullspace carrier still tracks its actual spent range")
	TEST_ASSERT_NULL(parked.loc, "the unlaunched carrier stays in nullspace")
