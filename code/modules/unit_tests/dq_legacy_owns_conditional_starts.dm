/// A legacy ownership() owns(starts = when(cond, T)) makes its occupant while the holder initializes, exactly as owns_one(starts = when()) does
/// (the bare when() entry used to resolve to nothing): a mapped extinguisher cabinet holds its extinguisher by the time Initialize returns,
/// watches it for deletion, and one built on a wall from its frame starts empty.
/datum/unit_test/dq_legacy_owns_conditional_starts/Run()
	var/turf/T = run_loc_floor_bottom_left
	for(var/i in 1 to 3)
		var/obj/structure/extinguisher_cabinet/C = allocate(/obj/structure/extinguisher_cabinet, T)
		TEST_ASSERT(istype(C.has_extinguisher, /obj/item/extinguisher), "a mapped cabinet starts with its extinguisher (try [i])")
		TEST_ASSERT_EQUAL(C.has_extinguisher?.loc, C, "the extinguisher is inside the cabinet")
		qdel(C.has_extinguisher)
		TEST_ASSERT_NULL(C.has_extinguisher, "the cabinet's deletion watch clears the var when its extinguisher is deleted")
		TEST_ASSERT(C.opened, "and leaves the cabinet open")
	var/obj/structure/extinguisher_cabinet/built = allocate(/obj/structure/extinguisher_cabinet, T, NORTH, TRUE)
	TEST_ASSERT_NULL(built.has_extinguisher, "a cabinet built from its frame starts empty")
	var/obj/item/gun/G = allocate(/obj/item/gun, T)
	TEST_ASSERT_NULL(G.attached_lock, "a gun without a DNA lock makes no chip")
