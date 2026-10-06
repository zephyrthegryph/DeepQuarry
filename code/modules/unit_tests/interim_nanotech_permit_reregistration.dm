/datum/unit_test/interim_nanotech_permit_reregistration

/datum/unit_test/interim_nanotech_permit_reregistration/Run()
	test_driver_begin()
	run_registration()
	test_driver_end()

/datum/unit_test/interim_nanotech_permit_reregistration/proc/run_registration()
	var/turf/floor = run_loc_floor_bottom_left
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human, floor)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human, floor)
	var/obj/item/clothing/accessory/permit/nanotech/permit = allocate(/obj/item/clothing/accessory/permit/nanotech, floor)
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, floor)
	TEST_ASSERT(first.put_in_active_hand(permit), "first actor holds the actual nanotech permit")
	test_menu(first, permit, "register")
	TEST_ASSERT(permit.owner, "real native registration locks the permit")
	TEST_ASSERT_EQUAL(permit.name, "[initial(permit.name)] ([first.name])", "first registration names its actual owner once")
	TEST_ASSERT_EQUAL(permit.desc, initial(permit.desc), "Nanotech registration retains its specialized original description")
	TEST_ASSERT_EQUAL(permit.registring, "[initial(permit.registring)][first.name]", "First registrant text contains one actual owner")
	var/locked_name = permit.name
	var/locked_validity = permit.validstring
	var/locked_registrant = permit.registring
	test_menu(first, permit, "register")
	TEST_ASSERT_EQUAL(permit.name, locked_name, "already registered permit refuses duplicate naming")
	TEST_ASSERT_EQUAL(permit.validstring, locked_validity, "Locked registration does not append validity text")
	TEST_ASSERT_EQUAL(permit.registring, locked_registrant, "Locked registration does not append registrant text")
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
	TEST_ASSERT_EQUAL(permit.name, "[initial(permit.name)] ([second.name])", "re-registration contains one current owner and preserves nanotech subtype prefix")
	TEST_ASSERT_EQUAL(permit.desc, initial(permit.desc), "Re-registration retains specialized nanotech description")
	TEST_ASSERT_EQUAL(permit.registring, "[initial(permit.registring)][second.name]", "Re-registration replaces the previous registrant")
	var/renewal_date = time2text(world.timeofday, "Month") + " " + num2text(text2num(time2text(world.timeofday, "YYYY")) + 544)
	TEST_ASSERT_EQUAL(permit.validstring, "[initial(permit.validstring)][renewal_date]", "Renewal contains one current validity date rather than concatenated dates")
