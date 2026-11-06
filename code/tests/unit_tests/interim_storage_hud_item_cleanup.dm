/// Closing the real grouped storage HUD must remove item count text and its lifetime pin.
/datum/unit_test/interim_storage_hud_item_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/part_replacer/storage = allocate(/obj/item/storage/part_replacer, T)
	var/obj/item/stock_parts/matter_bin/first = allocate(/obj/item/stock_parts/matter_bin, T)
	var/obj/item/stock_parts/matter_bin/second = allocate(/obj/item/stock_parts/matter_bin, T)
	TEST_ASSERT(storage.insert_item(first), "The real RPED must accept its first stock part")
	TEST_ASSERT(storage.insert_item(second), "The real RPED must accept its second stock part")
	var/hud_count_before = GLOB.storage_hud_count
	storage.open(actor)
	var/datum/storage_hud/hud = storage.hud
	TEST_ASSERT(hud, "Opening the real RPED must create its grouped HUD")
	TEST_ASSERT_EQUAL(length(hud.shown), 1, "The actual RPED HUD must group matching parts into one display item")
	var/obj/item/sample = hud.shown[1]
	TEST_ASSERT(sample == first || sample == second, "The shown sample must be one of the actual inserted parts")
	TEST_ASSERT(findtext(sample.maptext, "2"), "The real grouped HUD must render the count of two parts")
	TEST_ASSERT(sample.latent_pin_count(hud), "The real HUD must pin its displayed stock part")
	storage.close(actor)
	TEST_ASSERT(QDELETED(hud), "Closing the last viewer must destroy its actual HUD")
	TEST_ASSERT_EQUAL(sample.maptext, "", "HUD destruction must remove the displayed part's count text")
	TEST_ASSERT(!sample.latent_pin_count(hud), "HUD destruction must release its displayed part's actual lifetime pin")
	TEST_ASSERT_EQUAL(GLOB.storage_hud_count, hud_count_before, "Closing the HUD must restore its global count")
	TEST_ASSERT(!QDELETED(first) && !QDELETED(second), "Closing a HUD must preserve both stored parts")
