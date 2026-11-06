/datum/unit_test/interim_large_parcel_unwrap
	var/cargo_type = /obj/structure/closet
	var/sealed_after_wrap = TRUE

/datum/unit_test/interim_large_parcel_unwrap/crate
	cargo_type = /obj/structure/closet/crate
	sealed_after_wrap = FALSE

/datum/unit_test/interim_large_parcel_unwrap/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	// Create the actual closet before allocating floor items: its constructor gathers floor items.
	var/obj/structure/closet/cargo = allocate(cargo_type, T)
	TEST_ASSERT(!cargo.opened && !cargo.anchored && cargo.loc == T, "The actual original cargo is closed and movable on the wrapping floor")
	var/obj/item/packageWrap/paper = allocate(/obj/item/packageWrap, T)
	TEST_ASSERT(actor.put_in_active_hand(paper), "The actual actor holds its original package wrapper")
	var/paper_before = paper.amount
	var/list/before = turf_contents_of_type(T, /obj/structure/bigDelivery)
	paper.afterattack(cargo, actor, TRUE)
	own_turf_contents(T)
	var/list/products = turf_contents_of_type(T, /obj/structure/bigDelivery) - before
	TEST_ASSERT_EQUAL(length(products), 1, "Actual package wrapping creates exactly one real large parcel")
	var/obj/structure/bigDelivery/parcel = products[1]
	TEST_ASSERT_EQUAL(parcel.wrapped(), cargo, "The actual parcel records the exact original cargo")
	TEST_ASSERT_EQUAL(cargo.loc, parcel, "Actual wrapping physically contains its exact original cargo")
	TEST_ASSERT_EQUAL(paper.amount, paper_before - 3, "Actual large wrapping consumes exactly three original paper units")
	TEST_ASSERT_EQUAL(!!is_welded(cargo), sealed_after_wrap, "Actual wrapping preserves its canonical closet versus crate sealing behavior")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), paper, "Actual wrapping preserves the original held wrapper")
	TEST_ASSERT_EQUAL(test_op_handler(parcel, "interaction_hand", actor, paper), OP_OK, "Actual hand unwrapping preserves its original handled result")
	TEST_ASSERT(QDELETED(parcel), "Actual hand unwrapping consumes the exact original large parcel")
	TEST_ASSERT(!QDELETED(cargo) && cargo.loc == T, "The actual destruction chain releases the exact original cargo to its original floor")
	TEST_ASSERT(!is_welded(cargo), "The actual destruction chain leaves the released original cargo unsealed")
	TEST_ASSERT_EQUAL(paper.amount, paper_before - 3, "Actual unwrapping neither refunds nor consumes more original paper")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), paper, "Actual unwrapping preserves the original held wrapper")
	TEST_ASSERT(!QDELETED(actor) && !QDELETED(paper), "Actual parcel cleanup preserves the original actor and wrapper")
