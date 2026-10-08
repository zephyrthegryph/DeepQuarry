/// A real coordinate card must be consumed successfully before granting its one-use destination.
/datum/unit_test/interim_teleporter_sticky_coordinate_card/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/teleporter/console = allocate(/obj/machinery/computer/teleporter, T)
	var/obj/effect/landmark/destination = allocate(/obj/effect/landmark, get_step(T, NORTH))
	destination.name = "Interim checked coordinate destination"
	var/obj/item/card/data/card = allocate(/obj/item/card/data, T)
	card.function = "teleporter"
	card.data = destination.name
	TEST_ASSERT(destination in REGISTRY_MEMBERS(REGISTRY_LANDMARKS), "the real destination is registered through actual landmark initialization")
	TEST_ASSERT_NOTNULL(console.teleport_control, "the actual console initializes its real control module")
	TEST_ASSERT_NULL(console.teleport_control.locked(), "the actual console starts without a locked destination")
	TEST_ASSERT_EQUAL(console.one_time_use, 0, "the actual console starts without a one-use card grant")
	TEST_ASSERT(user.put_in_active_hand(card), "the actor holds the exact original coordinate card")
	add_trait(card, TRAIT_NODROP, "interim_teleporter_sticky")
	TEST_ASSERT(user.release_refusal(card, user), "actual inventory refuses the sticky coordinate card")
	test_menu(user, console, "teleporter_computer_insert_card")
	TEST_ASSERT(!QDELETED(card), "refused consumption preserves the original coordinate card")
	TEST_ASSERT_EQUAL(user.get_active_hand(), card, "refused consumption preserves the original hand")
	TEST_ASSERT_EQUAL(card.loc, user, "refused consumption preserves actual inventory containment")
	TEST_ASSERT_NULL(console.teleport_control.locked(), "refused consumption grants no locked destination")
	TEST_ASSERT_EQUAL(console.one_time_use, 0, "refused consumption grants no one-use authorization")
	remove_trait(card, TRAIT_NODROP, "interim_teleporter_sticky")
	test_menu(user, console, "teleporter_computer_insert_card") // the console's generic use_item op takes a plain click first
	TEST_ASSERT(QDELETED(card), "allowed installation consumes the exact original coordinate card")
	TEST_ASSERT_NULL(user.get_active_hand(), "allowed installation clears the actual source hand")
	TEST_ASSERT_EQUAL(console.teleport_control.locked(), destination, "allowed installation grants the exact original registered destination")
	TEST_ASSERT_EQUAL(console.one_time_use, 1, "one consumed coordinate card grants the actual one-use authorization")
