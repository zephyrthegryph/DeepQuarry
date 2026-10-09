/// Removing the actual watched pipe must replace its mounted meter with one portable item.
/datum/unit_test/interim_pipe_meter_replacement/Run()
	var/turf/T = test_floor()
	var/obj/machinery/atmospherics/pipe/simple/pipe = allocate(/obj/machinery/atmospherics/pipe/simple, T)
	var/obj/machinery/meter/meter = allocate(/obj/machinery/meter, T)
	meter.set_target(pipe)
	TEST_ASSERT_EQUAL(meter.target_ref(), pipe, "The real meter must watch its actual selected pipe")
	var/meter_handle = entity_handle(meter)
	var/list/before = turf_contents_of_type(T, /obj/item/pipe_meter)
	qdel(pipe)
	// Register the real event-generated replacement before any assertion terminates the test.
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(pipe), "The actual watched pipe must be deleted")
	TEST_ASSERT(QDELETED(meter), "The pipe's real deletion event must remove its mounted meter")
	var/list/created = turf_contents_of_type(T, /obj/item/pipe_meter) - before
	TEST_ASSERT_EQUAL(length(created), 1, "Pipe deletion must produce exactly one portable meter")
	var/obj/item/pipe_meter/portable = created[1]
	TEST_ASSERT(!QDELETED(portable), "The mounted meter's deletion must preserve its portable successor")
	TEST_ASSERT_EQUAL(portable.loc, T, "The portable meter must remain on the actual pipe floor")
	TEST_ASSERT_NULL(resolve_handle(meter_handle), "The machinery meter handle must terminate for an item successor")
