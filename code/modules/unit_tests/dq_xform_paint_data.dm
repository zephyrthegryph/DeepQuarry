/// A paint rule declares its colour as constant data (with_data =): the paint it settles into carries that colour; a rule whose data depends on the
/// settle (blood paint, which takes the blood's own colour) still computes it.
/datum/unit_test/dq_xform_paint_data/Run()
	var/turf/T = test_floor()
	var/obj/box = allocate(/obj, T)
	box.create_reagents(DQ_XFORM_VOLUME)
	box.reagents.add_reagent(REAGENT_ID_PLASTICIDE, 1, safety = TRUE)
	box.reagents.add_reagent(REAGENT_ID_WATER, 3, safety = TRUE)
	box.reagents.add_reagent(REAGENT_ID_MARKERINKRED, 1, safety = TRUE)
	box.reagents.handle_reactions()
	TEST_ASSERT(box.reagents.get_reagent_amount(REAGENT_ID_PAINT) > 0, "the red paint ingredients settle into paint")
	TEST_ASSERT_EQUAL(box.reagents.get_data(REAGENT_ID_PAINT), "#FE191A", "and the paint carries the rule's declared colour")
