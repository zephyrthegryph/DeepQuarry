/// Cutting a floor cable creates exactly one coil with the appropriate recovered length.
/obj/structure/cable/heavyduty/interim_stub
	icon_state = "0-1"

/obj/structure/cable/heavyduty/interim_straight
	icon_state = "1-2"

/datum/unit_test/interim_heavy_cable_replacement/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/list/expected_lengths = list(/obj/structure/cable/heavyduty/interim_stub = 1, /obj/structure/cable/heavyduty/interim_straight = 2)
	for(var/cable_type in expected_lengths)
		var/obj/structure/cable/heavyduty/cable = allocate(cable_type, T)
		cable.color = COLOR_BLUE
		var/expected_amount = expected_lengths[cable_type]
		TEST_ASSERT_EQUAL(cable.d1, expected_amount == 1 ? 0 : NORTH, "The stub and straight fixtures must parse distinct cable orientations")
		var/old_handle = entity_handle(cable)
		var/list/before = turf_contents_of_type(T, /obj/item/stack/cable_coil/heavyduty)
		cable.welder_act_tool_done(actor, T)
		// Register the actual material product before assertions can end the test.
		own_turf_contents(T)
		TEST_ASSERT(QDELETED(cable), "A completed cut must destroy its original floor cable")
		var/list/created = turf_contents_of_type(T, /obj/item/stack/cable_coil/heavyduty) - before
		TEST_ASSERT_EQUAL(length(created), 1, "A completed cut must create exactly one heavy cable coil")
		var/obj/item/stack/cable_coil/heavyduty/coil = created[1]
		TEST_ASSERT_EQUAL(coil.get_amount(), expected_amount, "Straight cable must return two lengths and a stub one")
		TEST_ASSERT_EQUAL(coil.loc, T, "Recovered cable must remain on the actual cut floor")
		TEST_ASSERT_EQUAL(coil.color, COLOR_BLUE, "Recovered cable must preserve its original color")
		TEST_ASSERT_NULL(resolve_handle(old_handle), "An installed cable handle must terminate for an item/stack successor")
