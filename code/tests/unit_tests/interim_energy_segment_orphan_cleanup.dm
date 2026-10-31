/datum/unit_test/interim_energy_segment_orphan_cleanup
	var/endpoint = 1

/datum/unit_test/interim_energy_segment_orphan_cleanup/pass
	endpoint = 2

/datum/unit_test/interim_energy_segment_orphan_cleanup/bump
	endpoint = 3

/datum/unit_test/interim_energy_segment_orphan_cleanup/flags
	endpoint = 4

/datum/unit_test/interim_energy_segment_orphan_cleanup/Run()
	var/turf/T = test_floor()
	var/obj/machinery/power/shield_generator/generator = allocate(/obj/machinery/power/shield_generator, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	generator.regenerate_field()
	TEST_ASSERT(length(generator.field_segments) > 1, "The actual real generator creates multiple original owned field segments")
	var/list/segments = generator.field_segments.Copy()
	for(var/obj/effect/shield/S as anything in segments)
		own(S)
	var/obj/effect/shield/segment = segments[1]
	TEST_ASSERT(segment && !QDELETED(segment), "The actual regeneration creates a real original segment")
	TEST_ASSERT_EQUAL(segment.gen(), generator, "The actual generated segment records its exact original generator")
	var/atom/original_location = segment.loc
	TEST_ASSERT(isturf(original_location), "The actual generator places its original segment on a real world turf")
	var/energy_before = generator.current_energy
	segment.take_damage(0, SHIELD_DAMTYPE_PHYSICAL, pen)
	segment.flags_updated()
	TEST_ASSERT(!QDELETED(segment), "Actual live-generator zero-damage and flag-update controls preserve the exact original segment")
	TEST_ASSERT_EQUAL(segment.gen(), generator, "Actual live-generator controls preserve the original generator relation")
	TEST_ASSERT_EQUAL(segment.loc, original_location, "Actual live-generator controls preserve original segment location")
	TEST_ASSERT_EQUAL(generator.current_energy, energy_before, "Actual zero-damage control spends none of the original generator energy")
	TEST_ASSERT_EQUAL(own_take_member(generator, nameof(generator.field_segments), segment), segment, "The actual supported ownership release returns the exact original retained segment")
	TEST_ASSERT(!(segment in generator.field_segments), "Actual ownership release removes only the retained segment from the generator's shutdown list")
	TEST_ASSERT(consume(generator), "The actual real generator is genuinely removed through its public lifecycle")
	TEST_ASSERT(QDELETED(generator), "The actual original generator is gone before orphan cleanup")
	for(var/obj/effect/shield/other as anything in segments)
		if(other != segment)
			TEST_ASSERT(QDELETED(other), "Actual generator shutdown deletes each other exact original owned segment")
	TEST_ASSERT(!QDELETED(segment), "The actual released original segment survives until its orphan endpoint")
	TEST_ASSERT_NULL(segment.gen(), "Actual generator deletion clears the released segment's real generator relation")
	if(endpoint == 1)
		TEST_ASSERT_NULL(segment.take_damage(1, SHIELD_DAMTYPE_PHYSICAL, pen), "Actual orphan damage cleanup retains its original null result")
	else if(endpoint == 2)
		TEST_ASSERT_EQUAL(segment.CanPass(pen, T), 1, "Actual orphan passage cleanup retains its original permissive result")
	else if(endpoint == 3)
		TEST_ASSERT_EQUAL(segment.Bumped(pen), 0, "Actual orphan bump cleanup retains its original zero result")
	else
		TEST_ASSERT_NULL(segment.flags_updated(), "Actual orphan flag cleanup retains its original null result")
	TEST_ASSERT(QDELETED(segment), "The actual orphan endpoint consumes the exact original released segment")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual segment orphan cleanup preserves the exact original unrelated floor item")
