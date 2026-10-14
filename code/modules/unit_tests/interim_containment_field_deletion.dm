/datum/unit_test/interim_containment_field_deletion
	var/delete_generator = FALSE

/datum/unit_test/interim_containment_field_deletion/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/first = get_step(start, EAST)
	var/turf/second = get_step(first, EAST)
	var/turf/finish = get_step(second, EAST)
	TEST_ASSERT(finish && finish.x <= run_loc_floor_top_right.x, "The fixture requires four floor tiles inside its test block")
	TEST_ASSERT(!first.density && !second.density && !finish.density, "The actual field path must be unobstructed")
	var/obj/machinery/field_generator/left = allocate(/obj/machinery/field_generator/pre_mapped, start)
	var/obj/machinery/field_generator/right = allocate(/obj/machinery/field_generator/pre_mapped, finish)
	left.set_active(1)
	right.set_active(1)
	left.setup_field(EAST)
	own_turf_contents(first)
	own_turf_contents(second)
	var/obj/machinery/containment_field/field_one = locate_on(first, /obj/machinery/containment_field)
	var/obj/machinery/containment_field/field_two = locate_on(second, /obj/machinery/containment_field)
	TEST_ASSERT_NOTNULL(field_one, "Actual generator setup must create the first beam tile")
	TEST_ASSERT_NOTNULL(field_two, "Actual generator setup must create the second beam tile")
	TEST_ASSERT_EQUAL(field_one.FG1(), left, "The actual beam must retain its source generator")
	TEST_ASSERT_EQUAL(field_one.FG2(), right, "The actual beam must retain its destination generator")
	TEST_ASSERT_EQUAL(LAZYLEN(left.fields), 2, "The source generator must track both real beam tiles")
	TEST_ASSERT_EQUAL(LAZYLEN(right.fields), 2, "The destination generator must track both real beam tiles")
	if(delete_generator)
		qdel(left)
	else
		qdel(field_one)
	TEST_ASSERT(QDELETED(field_one) && QDELETED(field_two), "Deleting a beam tile or generator must collapse the entire actual beam")
	TEST_ASSERT(!QDELETED(right), "Beam collapse must preserve the remote generator")
	TEST_ASSERT(!LAZYLEN(right.fields), "The remote generator must release all beam references")
	TEST_ASSERT(!LAZYLEN(right.connected_gens), "The remote generator must release its connection")
	if(!delete_generator)
		TEST_ASSERT(!QDELETED(left), "Deleting a beam tile must preserve both generators")
		TEST_ASSERT(!LAZYLEN(left.fields), "The source generator must release all beam references")
		TEST_ASSERT(!LAZYLEN(left.connected_gens), "The source generator must release its connection")

/datum/unit_test/interim_containment_field_deletion/generator
	delete_generator = TRUE
