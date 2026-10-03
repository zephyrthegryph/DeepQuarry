/// Actual APC bay ejection with both hands occupied returns the original cell to the floor without replacing either held item or changing stored charge.
/datum/unit_test/interim_apc_cell_eject_occupied_hands/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/apc = interim_apc_make(T)
	var/obj/item/cell/cell = apc.cell
	var/obj/item/pen/active = allocate(/obj/item/pen, T)
	var/obj/item/pen/inactive = allocate(/obj/item/pen, T)
	TEST_ASSERT_NOTNULL(cell, "the actual APC fixture starts with its real installed power cell")
	cap_key_set(apc, COVER_OPEN, TRUE, null)
	cell.charge = cell.maxcharge / 2
	var/charge_before = cell.charge
	TEST_ASSERT(user.put_in_active_hand(active), "the actual actor's active hand holds its first distinct item")
	TEST_ASSERT(user.put_in_inactive_hand(inactive), "the actual actor's inactive hand holds its second distinct item")
	TEST_ASSERT_EQUAL(interim_apc_take(apc, user), cell, "the actual public bay API returns the original ejected cell despite occupied hands")
	TEST_ASSERT_NULL(apc.cell, "actual occupied-hand ejection clears the APC's cell ownership view")
	TEST_ASSERT_EQUAL(cell.loc, T, "actual occupied-hand ejection places the original cell on the APC floor")
	TEST_ASSERT_EQUAL(cell.charge, charge_before, "actual occupied-hand ejection preserves all original stored charge")
	TEST_ASSERT_EQUAL(user.get_active_hand(), active, "actual occupied-hand ejection preserves the exact active item")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), inactive, "actual occupied-hand ejection preserves the exact inactive item")
	TEST_ASSERT_EQUAL(active.loc, user, "actual occupied-hand ejection retains physical ownership of the active item")
	TEST_ASSERT_EQUAL(inactive.loc, user, "actual occupied-hand ejection retains physical ownership of the inactive item")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/cell)), 1, "actual occupied-hand ejection creates no duplicate power cell")
	TEST_ASSERT_EQUAL(cell_charge_percent(apc), 0, "the actual empty bay reports zero charge after occupied-hand ejection")
	TEST_ASSERT_NULL(interim_apc_take(apc, user), "actual repeated empty-bay ejection returns no additional item")
	TEST_ASSERT_EQUAL(cell.loc, T, "actual repeated empty-bay ejection preserves the original cell on the floor")
	TEST_ASSERT_EQUAL(cell.charge, charge_before, "actual repeated empty-bay ejection cannot consume charge")
	TEST_ASSERT_EQUAL(user.get_active_hand(), active, "actual repeated empty-bay ejection preserves the occupied active hand")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), inactive, "actual repeated empty-bay ejection preserves the occupied inactive hand")
