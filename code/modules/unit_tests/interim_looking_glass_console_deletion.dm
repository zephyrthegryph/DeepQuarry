/// Matched IDs exercise the real console Initialize binding without modifying live map areas.
/area/looking_glass/interim_deletion_fixture
	lg_id = "interim_deletion_fixture"

/obj/machinery/computer/looking_glass/interim_deletion_fixture
	lg_id = "interim_deletion_fixture"

/// Deleting a running console must actually end its independent area's program.
/datum/unit_test/interim_looking_glass_console_deletion/Run()
	var/turf/T = test_floor()
	var/area/looking_glass/interim_deletion_fixture/display_area = allocate(/area/looking_glass/interim_deletion_fixture)
	var/obj/machinery/computer/looking_glass/interim_deletion_fixture/console = allocate(/obj/machinery/computer/looking_glass/interim_deletion_fixture, T)
	TEST_ASSERT_EQUAL(console.my_area(), display_area, "The real Initialize search must bind the matched display area")
	TEST_ASSERT(!display_area.active, "The actual independent display area must begin inactive")
	console.load_program("Diagnostics")
	TEST_ASSERT(display_area.active, "The actual console program API must activate the display area")
	console.unload_program()
	TEST_ASSERT(!display_area.active, "Explicit unload must actually stop the display area")
	console.load_program("Diagnostics")
	TEST_ASSERT(display_area.active, "The display area must actually be running before console deletion")
	qdel(console)
	TEST_ASSERT(QDELETED(console), "The actual running console must be deleted")
	TEST_ASSERT(!QDELETED(display_area), "The independent display area must survive console deletion")
	TEST_ASSERT(!display_area.active, "Console deletion must unload the actual program before its area relation clears")
