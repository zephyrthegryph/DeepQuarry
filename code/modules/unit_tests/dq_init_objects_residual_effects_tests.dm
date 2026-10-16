// Supported residual effects retain constructor results, contents and declared ownership.
/obj/item/trash/material/dq_init_fixed_scrap
	matter_chances = list(list(MAT_STEEL, 100, 10))

/datum/unit_test/dq_init_objects_residual_effects

/datum/unit_test/dq_init_objects_residual_effects/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/trash/material/dq_init_fixed_scrap/S = allocate(/obj/item/trash/material/dq_init_fixed_scrap)
	var/list/totals = S.material_totals()
	TEST_ASSERT(totals[MAT_STEEL] >= 8 && totals[MAT_STEEL] <= 12, "real scrap receives its guaranteed starting steel with the original bounded random quantity")
	TEST_ASSERT_EQUAL(length(totals), 1, "scrap does not gain undeclared starting materials")

/datum/unit_test/dq_init_objects_residual_effects/contents

/datum/unit_test/dq_init_objects_residual_effects/contents/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/storage/chewables/C = allocate(/obj/item/storage/chewables)
	TEST_ASSERT_EQUAL(contents_count(C), 6, "fitted chewables materialize the actual six starting wads")
	TEST_ASSERT_EQUAL(C.storage_slots, 6, "fitted storage derives its exact slot count from real contents")
	var/expected_space = 0
	for(var/obj/item/I as anything in contents_of(C))
		expected_space += I.get_storage_cost()
	TEST_ASSERT_EQUAL(C.max_storage_space, expected_space, "fitted storage reserves exactly the actual contents' space")
	var/obj/item/mail/junkmail/M = allocate(/obj/item/mail/junkmail)
	TEST_ASSERT_EQUAL(contents_count(M), 1, "the real junkmail constructor still encloses one actual item")
	TEST_ASSERT(M.name != initial(M.name), "junkmail preserves its generated envelope name")

/datum/unit_test/dq_init_objects_residual_effects/camera_huds

/datum/unit_test/dq_init_objects_residual_effects/camera_huds/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/camera/communicator/C = allocate(/obj/machinery/camera/communicator)
	TEST_ASSERT(GLOB.global_hud.whitense in C.client_huds, "a communicator camera retains its actual enhanced-vision HUD")
	TEST_ASSERT(GLOB.global_hud.darkMask in C.client_huds, "a communicator camera retains its actual dark-mask HUD")
	var/whitense_count = 0
	var/dark_count = 0
	for(var/datum/H as anything in C.client_huds)
		if(H == GLOB.global_hud.whitense)
			whitense_count++
		if(H == GLOB.global_hud.darkMask)
			dark_count++
	TEST_ASSERT_EQUAL(whitense_count, 1, "the enhanced-vision HUD is included once")
	TEST_ASSERT_EQUAL(dark_count, 1, "the dark-mask HUD is included once")

/datum/unit_test/dq_init_objects_residual_effects/implant_ownership

/datum/unit_test/dq_init_objects_residual_effects/implant_ownership/Run()
	dq_init_objects_fixture_scope()
	var/obj/machinery/implantchair/C = allocate(/obj/machinery/implantchair)
	TEST_ASSERT_EQUAL(length(C.implant_list), C.max_implants, "the actual chair starts with its configured implant count")
	var/list/implants = C.implant_list.Copy()
	for(var/obj/item/implant/loyalty/I as anything in implants)
		TEST_ASSERT_EQUAL(I.loc, C, "each starting implant is contained in the real chair")
		TEST_ASSERT_EQUAL(owner_of(I), C, "each starting implant retains the pre-existing declared owner")
	qdel(C)
	for(var/obj/item/implant/loyalty/I as anything in implants)
		TEST_ASSERT(QDELETED(I), "the existing owned-delete policy still deletes every starting implant with the chair")
