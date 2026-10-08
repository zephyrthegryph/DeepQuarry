/// Refusing a transfer into an actually full storage destination preserves the real grouped source HUD as well as both containment ledgers.
/datum/unit_test/interim_storage_transfer_full_hud/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/storage/part_replacer/source = allocate(/obj/item/storage/part_replacer, T)
	var/obj/item/storage/part_replacer/target = allocate(/obj/item/storage/part_replacer, T)
	var/obj/item/stock_parts/matter_bin/first = allocate(/obj/item/stock_parts/matter_bin, T)
	var/obj/item/stock_parts/matter_bin/second = allocate(/obj/item/stock_parts/matter_bin, T)
	var/obj/item/stock_parts/matter_bin/filler = allocate(/obj/item/stock_parts/matter_bin, T)
	target.storage_slots = 1
	TEST_ASSERT(source.insert_item(first) && source.insert_item(second), "the actual source RPED stores two real matching parts")
	TEST_ASSERT(target.insert_item(filler), "the actual destination RPED fills its one-item limit")
	source.open(user)
	var/datum/storage_hud/hud = source.hud
	TEST_ASSERT_NOTNULL(hud, "actual source opening constructs its grouped HUD")
	TEST_ASSERT_EQUAL(length(hud.shown), 1, "the actual source HUD groups its matching stored parts")
	var/obj/item/sample = hud.shown[1]
	TEST_ASSERT(sample == first || sample == second, "the actual grouped sample is one of the inserted stock parts")
	TEST_ASSERT(findtext(sample.maptext, "2"), "the actual grouped sample displays its two-part count")
	var/source_used = source.slot_used()
	var/target_used = target.slot_used()
	var/sample_plane = sample.plane
	var/sample_layer = sample.layer
	var/sample_maptext = sample.maptext
	TEST_ASSERT(!source.remove_from_storage(sample, target, user), "the actual removal transfer refuses an actually full destination")
	TEST_ASSERT_EQUAL(sample.loc, source, "destination refusal preserves the actual sample's original source")
	TEST_ASSERT(sample in source.slot_contents(CONTAINER_SLOT_STORAGE), "destination refusal preserves the sample's source ledger entry")
	TEST_ASSERT(!(sample in target.slot_contents(CONTAINER_SLOT_STORAGE)), "destination refusal creates no destination ledger entry")
	TEST_ASSERT_EQUAL(source.slot_used(), source_used, "destination refusal preserves all actual source capacity accounting")
	TEST_ASSERT_EQUAL(target.slot_used(), target_used, "destination refusal preserves all actual destination capacity accounting")
	TEST_ASSERT_EQUAL(filler.loc, target, "destination refusal preserves the actual occupying part")
	TEST_ASSERT_EQUAL(sample.plane, sample_plane, "destination refusal preserves the actual grouped sample's display plane")
	TEST_ASSERT_EQUAL(sample.layer, sample_layer, "destination refusal preserves the actual grouped sample's display layer")
	TEST_ASSERT_EQUAL(sample.maptext, sample_maptext, "destination refusal preserves the actual grouped count text")
	TEST_ASSERT(sample.latent_pin_count(hud), "destination refusal preserves the actual HUD's sample lifetime pin")
	source.close(user)
	TEST_ASSERT(QDELETED(hud), "closing the actual source view tears down its HUD after the refused transfer")
