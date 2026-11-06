/// Actual curtain projectile handling distinguishes damaging laser hits from non-damaging stun beams.
/datum/unit_test/interim_curtain_projectile_removal
	var/projectile_type = /obj/item/projectile/beam
	var/harmless = FALSE

/datum/unit_test/interim_curtain_projectile_removal/harmless
	projectile_type = /obj/item/projectile/beam/stun
	harmless = TRUE

/datum/unit_test/interim_curtain_projectile_removal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/curtain/curtain = allocate(/obj/structure/curtain, T)
	var/obj/item/projectile/beam/projectile = allocate(projectile_type, T)
	TEST_ASSERT_EQUAL(!!projectile.nodamage, harmless, "the real projectile type declares the expected damage behavior")
	var/integrity = curtain.get_integrity()
	curtain.bullet_act(projectile, null)
	own_turf_contents(T)
	if(harmless)
		TEST_ASSERT(!QDELETED(curtain), "the actual non-damaging projectile preserves the curtain")
		TEST_ASSERT_EQUAL(curtain.loc, T, "the surviving curtain stays on its original floor")
		TEST_ASSERT_EQUAL(curtain.get_integrity(), integrity, "the actual non-damaging hit preserves curtain integrity")
		TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/curtain)), 1, "the harmless hit preserves exactly the original curtain")
	else
		TEST_ASSERT(QDELETED(curtain), "the actual damaging laser hit consumes the curtain")
		TEST_ASSERT_NULL(locate_within(T, /obj/structure/curtain), "the damaging hit leaves no duplicate curtain")

/// Real grave closing stores cargo; smoothing deletes only empty graves and conceals occupied ones.
/datum/unit_test/interim_grave_smoothing
	var/occupied = FALSE

/datum/unit_test/interim_grave_smoothing/occupied
	occupied = TRUE

/datum/unit_test/interim_grave_smoothing/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/adjacent = locate(T.x + 1, T.y, T.z)
	TEST_ASSERT(adjacent, "the actual grave fixture has an adjacent actor floor")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, adjacent)
	var/obj/structure/closet/grave/grave = allocate(/obj/structure/closet/grave, T)
	var/obj/item/book/book
	if(occupied)
		book = allocate(/obj/item/book, T)
	TEST_ASSERT(grave.opened, "the real grave initializes open")
	grave.close()
	TEST_ASSERT(!grave.opened, "actual closing fills the grave")
	if(occupied)
		TEST_ASSERT_EQUAL(book.loc, grave, "actual closing stores the original book in the grave")
		TEST_ASSERT(book in grave.slot_contents(CONTAINER_SLOT_INTERIOR), "the original book occupies the actual grave interior slot")
	else
		TEST_ASSERT_EQUAL(length(grave.slot_contents()), 0, "the actual closed grave starts empty")
	var/obj/item/shovel/shovel = allocate(/obj/item/shovel, adjacent)
	TEST_ASSERT(user.put_in_active_hand(shovel), "the actor holds the actual shovel")
	user.set_use_stance(I_HURT)
	test_click(user, grave, shovel)
	test_time(10 SECONDS)
	own_turf_contents(T)
	if(occupied)
		TEST_ASSERT(!QDELETED(grave), "actual smoothing preserves a grave containing the original book")
		TEST_ASSERT_EQUAL(grave.alpha, 40, "actual smoothing conceals the occupied grave at its existing opacity")
		TEST_ASSERT(!QDELETED(book), "actual smoothing preserves the original stored book")
		TEST_ASSERT_EQUAL(book.loc, grave, "smoothing leaves the original book inside its grave")
	else
		TEST_ASSERT(QDELETED(grave), "actual smoothing consumes an empty grave")
		TEST_ASSERT_NULL(locate_within(T, /obj/structure/closet/grave), "smoothing leaves no duplicate empty grave")
	test_driver_end()
