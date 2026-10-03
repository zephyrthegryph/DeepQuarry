/datum/unit_test/interim_telecrystal_release_validation

/datum/unit_test/interim_telecrystal_release_validation/Run()
	var/turf/floor = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, floor)
	var/obj/machinery/smartfridge/tcrystal/storage = allocate(/obj/machinery/smartfridge/tcrystal, floor)
	var/obj/item/stack/telecrystal/input = allocate(/obj/item/stack/telecrystal, floor, 10)
	storage.stock(input)
	TEST_ASSERT(QDELETED(input), "Actual stocking must consume the inserted telecrystal stack")
	TEST_ASSERT_EQUAL(LAZYLEN(storage.item_records), 1, "Actual stocking must establish one stock record")
	var/datum/stored_item/record = storage.item_records[1]
	TEST_ASSERT_EQUAL(record.get_amount(), 10, "The real record must retain exactly ten inserted crystals")
	for(var/amount in list(-5, 0, 1.5))
		TEST_ASSERT(!storage.release_crystals(actor, amount, "1"), "A non-positive or fractional request must be refused")
		TEST_ASSERT_EQUAL(record.get_amount(), 10, "Invalid release amounts must not manufacture or consume stock")
		TEST_ASSERT_EQUAL(LAZYLEN(turf_contents_of_type(floor, /obj/item/stack/telecrystal)), 0, "Invalid amounts must not create crystal output")
	for(var/index in list("0", "2", "1.5", "invalid"))
		TEST_ASSERT(!storage.release_crystals(actor, 3, index), "An invalid stock index must be refused without a runtime")
		TEST_ASSERT_EQUAL(record.get_amount(), 10, "Invalid indices must not change the real stock record")
	TEST_ASSERT(storage.release_crystals(actor, 3, 1), "A valid numeric UI index must release crystals")
	own_turf_contents(floor)
	var/list/products = turf_contents_of_type(floor, /obj/item/stack/telecrystal)
	TEST_ASSERT_EQUAL(LAZYLEN(products), 1, "A valid request must produce exactly one actual output stack")
	var/obj/item/stack/telecrystal/product = products[1]
	TEST_ASSERT_EQUAL(product.get_amount(), 3, "A valid request must output the exact requested amount")
	TEST_ASSERT_EQUAL(record.get_amount(), 7, "A valid request must deduct only the actual output from stock")
	qdel(product)
	TEST_ASSERT(storage.release_crystals(actor, 20, "1"), "A valid text index must cap release at the remaining stock")
	own_turf_contents(floor)
	products = turf_contents_of_type(floor, /obj/item/stack/telecrystal)
	TEST_ASSERT_EQUAL(LAZYLEN(products), 1, "Exhausting the record must produce exactly one remaining output stack")
	product = products[1]
	TEST_ASSERT_EQUAL(product.get_amount(), 7, "An oversized request must output only the seven remaining crystals")
	TEST_ASSERT_EQUAL(LAZYLEN(storage.item_records), 0, "Exhausting stock must remove its real record")
