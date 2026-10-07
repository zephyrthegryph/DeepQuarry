/// Actual wall-poster removal preserves its declaration and distinguishes ruined scraps.
/datum/unit_test/interim_poster_recovery
	var/ruined = FALSE
	var/direct = FALSE

/datum/unit_test/interim_poster_recovery/ruined
	ruined = TRUE

/datum/unit_test/interim_poster_recovery/direct
	direct = TRUE

/datum/unit_test/interim_poster_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/poster/original = allocate(/obj/item/poster, T)
	TEST_ASSERT(user.put_in_active_hand(original), "the original rolled poster occupies the actual actor hand")
	var/datum/decl/poster/expected_decl = original.get_decl()
	TEST_ASSERT(expected_decl, "the real rolled poster initializes a concrete declaration")
	var/obj/structure/sign/poster/wall_poster = allocate(/obj/structure/sign/poster, T, EAST, original)
	TEST_ASSERT_EQUAL(wall_poster.pixel_x, 32, "the actual wall poster initializes its east-facing wall offset")
	TEST_ASSERT(!wall_poster.is_ruined(), "the actual wall poster initially has recoverable print")
	var/obj/item/tool/wirecutters/tool = allocate(/obj/item/tool/wirecutters, T)
	TEST_ASSERT(user.put_in_inactive_hand(tool), "the real wirecutters occupy the actor's other hand")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/poster)), 0, "the floor initially has no rolled posters")
	if(ruined)
		test_driver_begin()
		defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
		var/mob/living/carbon/human/ripper = allocate(/mob/living/carbon/human, T)
		test_click(ripper, wall_poster, null)
		TEST_ASSERT(test_op_committed(test_answer(ripper, TRUE)), "the actual native confirmation delivers the rip")
		TEST_ASSERT(wall_poster.is_ruined(), "the actual rip callback ruins the wall poster before removal")
		TEST_ASSERT_EQUAL(wall_poster.icon_state, "poster_ripped", "the actual rip replaces the wall poster appearance")
	var/obj/item/poster/recovered
	if(direct)
		recovered = wall_poster.roll_and_drop(T)
	else
		TEST_ASSERT_EQUAL(test_op_handler(wall_poster, "wirecutter_used", user, tool), OP_OK, "the actual wirecutter removal succeeds")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(wall_poster), "actual removal consumes the original wall poster")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/sign/poster)), 0, "actual removal leaves no duplicate wall poster")
	if(ruined)
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/poster)), 0, "removing actual ruined scraps creates no recoverable rolled print")
	else
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/poster)), 1, "intact removal returns exactly one real rolled poster")
		var/obj/item/poster/product = locate_within(T, /obj/item/poster)
		TEST_ASSERT(!QDELETED(product), "the actual recovered rolled poster survives source deletion")
		TEST_ASSERT_EQUAL(product.get_decl(), expected_decl, "actual recovery preserves the exact initialized print declaration")
		TEST_ASSERT_EQUAL(product.type, original.type, "actual recovery preserves the original rolled item type")
		TEST_ASSERT_EQUAL(product.loc, T, "actual recovery places the rolled poster on the requested floor")
		if(direct)
			TEST_ASSERT_EQUAL(recovered, product, "the public wall-dismantling helper returns its exact new product")
	TEST_ASSERT_EQUAL(user.get_active_hand(), original, "wall poster removal preserves the separate original rolled item")
	TEST_ASSERT_EQUAL(user.get_inactive_hand(), tool, "wall poster removal preserves its real wirecutters")
