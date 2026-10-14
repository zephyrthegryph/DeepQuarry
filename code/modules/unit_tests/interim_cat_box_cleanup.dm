/datum/unit_test/interim_cat_box_cleanup
	var/box_type = /obj/item/cat_box
	var/cat_type = /mob/living/simple_mob/animal/passive/cat

/datum/unit_test/interim_cat_box_cleanup/black
	box_type = /obj/item/cat_box/black
	cat_type = /mob/living/simple_mob/animal/passive/cat/black

/datum/unit_test/interim_cat_box_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/cat_box/box = allocate(box_type, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(actor.put_in_active_hand(pen), "The actual actor holds its original unrelated pen")
	TEST_ASSERT(actor.put_in_inactive_hand(box), "The actual cat box genuinely occupies its original hand slot")
	TEST_ASSERT_EQUAL(box.cattype, cat_type, "The actual existing box subtype retains its exact canonical cat family")
	var/list/cats_before = turf_contents_of_type(T, /mob/living/simple_mob/animal/passive/cat)
	var/list/cardboard_before = turf_contents_of_type(T, /obj/item/stack/material/cardboard)
	add_trait(box, TRAIT_NODROP, "interim_cat_box_cleanup")
	TEST_ASSERT(box.loc.release_refusal(box, actor), "The actual sticky held cat box genuinely refuses release")
	test_op_handler(box, "interaction_self", actor, box) // the box sits in the inactive hand, then on the floor: the handler is called as the engine would
	TEST_ASSERT(!QDELETED(box) && box.loc == actor, "Actual sticky box refusal preserves the exact original held source")
	TEST_ASSERT_EQUAL(actor.get_inactive_hand(), box, "Actual sticky box refusal preserves the exact original source slot")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /mob/living/simple_mob/animal/passive/cat) - cats_before), 0, "Actual sticky refusal creates no cat")
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/stack/material/cardboard) - cardboard_before), 0, "Actual sticky refusal creates no cardboard")
	remove_trait(box, TRAIT_NODROP, "interim_cat_box_cleanup")
	TEST_ASSERT(actor.drop_from_inventory(box, T), "The actual unblocked cat box returns to its original floor")
	TEST_ASSERT(test_op_handler(box, "interaction_self", actor, box), "Actual floor opening preserves the original handled result")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(box), "Actual opening consumes the exact original cat box")
	var/list/cats = turf_contents_of_type(T, /mob/living/simple_mob/animal/passive/cat) - cats_before
	TEST_ASSERT_EQUAL(length(cats), 1, "Actual box opening produces exactly one real cat")
	var/mob/living/simple_mob/animal/passive/cat/cat = cats[1]
	TEST_ASSERT_EQUAL(cat.type, cat_type, "The actual original product has the exact canonical cat subtype")
	TEST_ASSERT(!QDELETED(cat) && cat.stat != DEAD && cat.loc == T, "The actual original cat survives alive on its original floor")
	var/list/cardboard = turf_contents_of_type(T, /obj/item/stack/material/cardboard) - cardboard_before
	TEST_ASSERT_EQUAL(length(cardboard), 1, "Actual opening produces exactly one original cardboard stack")
	var/obj/item/stack/material/cardboard/sheet = cardboard[1]
	TEST_ASSERT_EQUAL(sheet.get_amount(), 1, "Actual opening retains the original one-sheet cardboard yield")
	TEST_ASSERT(!QDELETED(sheet) && sheet.loc == T, "The actual original cardboard survives on the original floor")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), pen, "Actual cat-box opening preserves the original unrelated held pen")
	TEST_ASSERT(!QDELETED(actor) && !QDELETED(pen), "Actual opening preserves both original unrelated participants")
