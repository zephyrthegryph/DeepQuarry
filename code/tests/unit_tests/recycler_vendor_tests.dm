/// Validates every maint recycler vendor entry is well-formed: a non-scam
/// entry must spawn something, cost can't be negative, and a free item must
/// carry at least one purchase cap so it can't be spawned infinitely.

/datum/unit_test/recycler_vendor_tests/Run()
	for(var/datum/maint_recycler_vendor_entry/R as anything in subtypesof(/datum/maint_recycler_vendor_entry))
		TEST_ASSERT(initial(R.is_scam) || initial(R.object_type_to_spawn), "[R] : Vendor Entry - non-scam entry is missing object_type_to_spawn")
		TEST_ASSERT(initial(R.item_cost) >= 0, "[R] : Vendor Entry - negative item_cost")
		TEST_ASSERT(!(initial(R.item_cost) == 0 && initial(R.per_round_cap) < 0 && initial(R.per_person_cap) < 0), "[R] : Vendor Entry - free item (cost 0) with no per-round or per-person cap can be spawned infinitely")
