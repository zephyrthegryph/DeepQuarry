// A costume landmark rolls a costume where it stands (resolve_landmark()). Only the base picks one at random; every costume type under it names its own
// items, or it would pick again, a type that picks itself without end (boot died in the map pass on such a landmark, and every atom after it stayed
// uninitialized).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_costume_landmarks_name_their_items

/datum/unit_test/dq_costume_landmarks_name_their_items/Run()
	var/checked = 0
	for(var/path in subtypesof(/obj/effect/landmark/costume))
		var/datum/loot_decl/decl = loot_decl_for(path)
		TEST_ASSERT_NOTNULL(decl, "[path] has no loot declaration")
		if(!decl)
			continue
		checked++
		TEST_ASSERT(!decl.main_table, "[path] inherits the base's random costume table and would roll another costume landmark: give it its own items")
		TEST_ASSERT(length(decl.all), "[path] names no items")
	TEST_ASSERT(checked > 0, "no costume landmark types were checked")

#endif
