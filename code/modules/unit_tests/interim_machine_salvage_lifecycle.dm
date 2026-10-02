/// Real salvage completion returns a machine frame and respects deterministic salvage chances.
/datum/unit_test/interim_machine_salvage_lifecycle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/salvageable/machine/wreck = allocate(/obj/structure/salvageable/machine, T)
	// Exercise the actual probability table with deterministic edge chances, without replacing its effect.
	wreck.salvageable_parts = list(/obj/item/stock_parts/console_screen = 100, /obj/item/stock_parts/capacitor = 0)
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/frame)), 0, "the wreck starts without a returned machine frame")
	wreck.crowbar_act_timed_done(user)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(wreck), "actual salvage completion immediately consumes the broken machine")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/salvageable/machine), "salvage leaves no duplicate broken machine")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/structure/frame)), 1, "actual salvage produces exactly one machine frame")
	var/obj/structure/frame/frame = locate_within(T, /obj/structure/frame)
	TEST_ASSERT_EQUAL(frame.loc, T, "the real returned frame stays on the original wreck turf")
	TEST_ASSERT(!QDELETED(frame), "the real returned frame survives source consumption")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stock_parts/console_screen)), 1, "the guaranteed actual salvage part is returned exactly once")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stock_parts/capacitor)), 0, "the zero-chance actual salvage part is never returned")
	TEST_ASSERT_NULL(user.get_active_hand(), "salvaging the floor wreck does not equip its products")
