/datum/unit_test/round2_tele_beacon_native_warning/Run()
	test_driver_begin()
	exercise_warning()
	test_driver_end()

/// Someone else's beacon warns before the first pick-up (the op "warn" asks it): leaving it, closing the warning or walking away
/// leaves it on the floor; taking it picks it up; and a warned actor is not asked again.
/datum/unit_test/round2_tele_beacon_native_warning/proc/exercise_warning()
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, surface)
	actor.enable_godmode()
	var/obj/item/perfect_tele_beacon/beacon = allocate(/obj/item/perfect_tele_beacon, surface)
	TEST_ASSERT_NULL(beacon.creator, "Actual beacon has its default null creator")
	beacon.creator = "someone_else" // the warning is for a beacon somebody else made
	TEST_ASSERT_NULL(actor.client, "Fixture uses an actual clientless human")
	test_click(actor, beacon)
	TEST_ASSERT(istype(SSrequests.open_for(actor), /datum/prompt/choice), "Actual warning opens nearby")
	test_answer(actor, "Leave It")
	test_time(0.1 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Leave It closes warning")
	TEST_ASSERT_EQUAL(beacon.loc, surface, "Leave It retains original beacon on floor")

	var/obj/item/perfect_tele_beacon/closed = allocate(/obj/item/perfect_tele_beacon, surface)
	closed.creator = "someone_else"
	test_click(actor, closed)
	test_answer(actor, null, REQ_CANCELLED)
	test_time(0.1 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Explicit close leaves no request")
	TEST_ASSERT_EQUAL(closed.loc, surface, "Explicit close retains original floor beacon")

	var/turf/far = locate(surface.x + 3, surface.y, surface.z)
	TEST_ASSERT(far && get_dist(surface, far) > 1, "Fixture has genuinely distant turf")
	var/obj/item/perfect_tele_beacon/distant = allocate(/obj/item/perfect_tele_beacon, surface)
	distant.creator = "someone_else"
	test_click(actor, distant)
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "Late distance case starts with actual pending warning")
	actor.forceMove(far)
	test_answer(actor, "Take It")
	test_time(0.1 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Distant answer closes rejected request")
	TEST_ASSERT_EQUAL(distant.loc, surface, "Distant answer cannot pick up original beacon")
	actor.forceMove(surface)

	var/obj/item/perfect_tele_beacon/taken = allocate(/obj/item/perfect_tele_beacon, surface)
	taken.creator = "someone_else"
	test_click(actor, taken)
	TEST_ASSERT_NOTNULL(SSrequests.open_for(actor), "Nearby accepted pickup has actual warning")
	test_answer(actor, "Take It")
	test_time(0.1 SECONDS)
	own_turf_contents(surface)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "Take It completes warning")
	TEST_ASSERT(actor.item_is_in_hands(taken), "Production callback actually picks original beacon into a real hand")
	TEST_ASSERT_EQUAL(taken.loc, actor, "Original beacon physically belongs to drawer after pickup")

	actor.drop_item()
	test_click(actor, beacon)
	TEST_ASSERT_NULL(SSrequests.open_for(actor), "A warned actor is not asked again")
	TEST_ASSERT(actor.item_is_in_hands(beacon), "A warned actor picks the beacon straight up")
	own_turf_contents(surface)
