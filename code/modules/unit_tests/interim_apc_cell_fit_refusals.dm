/// A full real APC bay refuses a different held cell without ejecting, charging, or replacing either actual cell.
/datum/unit_test/interim_apc_occupied_cell_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/apc = interim_apc_make(T)
	var/obj/item/cell/original = apc.cell
	var/obj/item/cell/replacement = allocate(/obj/item/cell, T)
	TEST_ASSERT_NOTNULL(original, "the actual APC starts with an installed original cell")
	key_set(apc, COVER_OPEN, TRUE)
	replacement.charge = replacement.maxcharge / 2
	var/original_charge = original.charge
	var/replacement_charge = replacement.charge
	TEST_ASSERT(user.put_in_active_hand(replacement), "the actual actor holds the distinct replacement cell")
	TEST_ASSERT(!interim_apc_insert(apc, replacement, user), "the actual occupied bay refuses the held replacement")
	TEST_ASSERT_EQUAL(apc.cell, original, "occupied-bay refusal preserves the exact original cell reference")
	TEST_ASSERT_EQUAL(original.loc, apc, "occupied-bay refusal keeps the original cell physically installed")
	TEST_ASSERT_EQUAL(original.charge, original_charge, "occupied-bay refusal preserves original stored charge")
	TEST_ASSERT_EQUAL(replacement.loc, user, "occupied-bay refusal preserves the replacement's actual actor")
	TEST_ASSERT_EQUAL(user.get_active_hand(), replacement, "occupied-bay refusal preserves the replacement's exact active hand")
	TEST_ASSERT_EQUAL(replacement.charge, replacement_charge, "occupied-bay refusal preserves replacement stored charge")
	TEST_ASSERT_EQUAL(interim_apc_take(apc, user, drop = TRUE), original, "the actual public bay take op and inventory drop release only the original cell")
	TEST_ASSERT_EQUAL(original.loc, T, "actual original-cell ejection reaches the floor")
	TEST_ASSERT(interim_apc_insert(apc, replacement, user), "the exact previously refused replacement fits the now-empty real bay")
	TEST_ASSERT_EQUAL(apc.cell, replacement, "actual insertion adopts the exact replacement cell")
	TEST_ASSERT_EQUAL(replacement.loc, apc, "actual replacement insertion reaches the APC")
	TEST_ASSERT_NULL(user.get_active_hand(), "actual replacement insertion clears its former active hand")
	TEST_ASSERT_EQUAL(original.charge, original_charge, "actual replacement never consumes the removed original's charge")
	TEST_ASSERT_EQUAL(replacement.charge, replacement_charge, "actual replacement insertion preserves its independent charge")

/// A real device-sized power cell cannot enter the APC's normal-sized bay even when the bay is empty.
/datum/unit_test/interim_apc_device_cell_size_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/power/apc/apc = interim_apc_make(T)
	var/obj/item/cell/original = apc.cell
	var/obj/item/cell/device/small = allocate(/obj/item/cell/device, T)
	TEST_ASSERT_NOTNULL(original, "the actual size-refusal fixture has an original cell")
	key_set(apc, COVER_OPEN, TRUE)
	TEST_ASSERT_EQUAL(interim_apc_take(apc, user, drop = TRUE), original, "the actual public bay take op and inventory drop empty the actual bay for the size test")
	TEST_ASSERT_NULL(apc.cell, "the actual size-refusal fixture has an empty bay")
	TEST_ASSERT(small.w_class != ITEMSIZE_NORMAL, "the actual device cell has a genuinely incompatible physical size")
	TEST_ASSERT(user.put_in_active_hand(small), "the actual actor holds the real undersized device cell")
	var/charge_before = small.charge
	TEST_ASSERT(!interim_apc_insert(apc, small, user), "the actual empty APC bay refuses a real device-sized cell")
	TEST_ASSERT_NULL(apc.cell, "size refusal preserves the actual empty bay")
	TEST_ASSERT_EQUAL(small.loc, user, "size refusal preserves the actual device cell's actor")
	TEST_ASSERT_EQUAL(user.get_active_hand(), small, "size refusal preserves the device cell's exact active hand")
	TEST_ASSERT_EQUAL(small.charge, charge_before, "size refusal consumes no device-cell charge")
	TEST_ASSERT_EQUAL(original.loc, T, "size refusal leaves the previously removed normal cell on the floor")
