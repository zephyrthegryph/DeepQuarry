/datum/unit_test/interim_chewable_spitout_cleanup
	var/worn = FALSE

/datum/unit_test/interim_chewable_spitout_cleanup/worn
	worn = TRUE

/datum/unit_test/interim_chewable_spitout_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(actor.put_in_active_hand(pen), "The actual actor holds its original unrelated pen")
	var/obj/item/clothing/mask/chewable/tobacco/wad = allocate(/obj/item/clothing/mask/chewable/tobacco, T)
	wad.set_base_color("#327654")
	TEST_ASSERT_EQUAL(wad.type_butt, /obj/item/trash/spitwad, "The actual tobacco retains its canonical replacement product")
	TEST_ASSERT_EQUAL(wad.brand, "tobacco", "The actual tobacco retains its original brand metadata")
	var/list/before = turf_contents_of_type(T, /obj/item/trash/spitwad)
	if(worn)
		TEST_ASSERT(actor.equip_to_slot_if_possible(wad, SLOT_ID_MASK), "The actual tobacco equips through the public mask path")
		TEST_ASSERT_EQUAL(actor.get_equipped_item(SLOT_ID_MASK), wad, "The actor actually wears the exact original tobacco")
		TEST_ASSERT(wad.chewing, "The real equipped tobacco activates its original chewing state")
		wad.spitout()
	else
		wad.spitout()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(wad), "Actual spitout consumes the exact original tobacco source")
	var/obj/item/trash/spitwad/product
	if(worn)
		product = actor.get_equipped_item(SLOT_ID_MASK)
		TEST_ASSERT_NOTNULL(product, "Actual worn spitout equips a real replacement in the original mask slot")
		own(product)
		TEST_ASSERT_EQUAL(product.loc, actor, "The actual original replacement remains worn by the same actor")
	else
		var/list/products = turf_contents_of_type(T, /obj/item/trash/spitwad) - before
		TEST_ASSERT_EQUAL(length(products), 1, "Actual floor spitout creates exactly one new original spitwad")
		product = products[1]
		TEST_ASSERT_EQUAL(product.loc, T, "The actual original replacement remains on the source floor")
	TEST_ASSERT_EQUAL(product.type, /obj/item/trash/spitwad, "Actual spitout creates the exact canonical spitwad type")
	TEST_ASSERT(!QDELETED(product), "The actual replacement survives source consumption")
	TEST_ASSERT_EQUAL(product.color, "#327654", "Actual spitout transfers the original source color")
	TEST_ASSERT_EQUAL(product.desc, "A disgusting spitwad. This one is a tobacco.", "Actual spitout preserves the exact original brand description")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "Actual spitout preserves the exact unrelated held pen")
	TEST_ASSERT(!QDELETED(actor) && actor.loc == T, "Actual spitout preserves the original actor and floor")
