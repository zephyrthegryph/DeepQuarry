/datum/unit_test/interim_permit_reregistration

/datum/unit_test/interim_permit_reregistration/Run()
	test_driver_begin()
	run_registration()
	test_driver_end()

/datum/unit_test/interim_permit_reregistration/proc/run_registration()
	var/turf/floor = run_loc_floor_bottom_left
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, floor)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, floor)
	var/obj/item/clothing/accessory/permit/gun/permit = allocate(/obj/item/clothing/accessory/permit/gun, floor)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, floor)
	TEST_ASSERT(first.put_in_active_hand(permit), "first actor holds the actual weapon permit")
	test_menu(first, permit, "register")
	TEST_ASSERT(permit.owner, "real native registration locks the permit")
	TEST_ASSERT_EQUAL(permit.name, "[initial(permit.name)] ([first.name])", "first registration names its actual owner once")
	TEST_ASSERT_EQUAL(permit.desc, "[initial(permit.desc)] It belongs to [first.name].", "first registration describes its actual owner")
	var/locked_name = permit.name
	test_menu(first, permit, "register")
	TEST_ASSERT_EQUAL(permit.name, locked_name, "already registered permit refuses duplicate naming")
	TEST_ASSERT(first.drop_from_inventory(permit, floor), "first actor releases the actual permit")
	TEST_ASSERT(second.put_in_active_hand(card), "second actor holds the actual emag")
	var/old_uses = card.uses
	test_click(second, permit, card)
	TEST_ASSERT(!permit.owner, "actual public emag click resets registration lock")
	TEST_ASSERT_EQUAL(card.uses, old_uses - 1, "successful native emag pays its actual charge")
	TEST_ASSERT(second.drop_from_inventory(card, floor), "second actor releases the actual emag")
	TEST_ASSERT(second.put_in_active_hand(permit), "second actor holds the reset permit")
	test_menu(second, permit, "register")
	TEST_ASSERT(permit.owner, "second real registration locks the permit again")
	TEST_ASSERT_EQUAL(permit.name, "[initial(permit.name)] ([second.name])", "re-registration contains one current owner and preserves gun variant prefix")
	TEST_ASSERT_EQUAL(permit.desc, "[initial(permit.desc)] It belongs to [second.name].", "re-registration replaces the stale ownership description")
