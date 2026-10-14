/// Public window inputs change the real lending period and create owned checkout records.
/datum/unit_test/interim_library_checkout_controls/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/librarycomp/console = allocate(/obj/machinery/librarycomp, T)
	TEST_ASSERT_EQUAL(console.checkoutperiod, 5, "A real lending console starts with a five-minute period")
	test_ui(actor, console, "increasetime", list())
	test_drain()
	TEST_ASSERT_EQUAL(console.checkoutperiod, 6, "The actual increase button extends the lending period")
	console.checkoutperiod = 1
	test_ui(actor, console, "decreasetime", list())
	test_drain()
	TEST_ASSERT_EQUAL(console.checkoutperiod, 1, "The actual decrease button cannot shorten the period below one minute")
	console.buffer_book = "Interim lending book"
	console.buffer_mob = "Interim borrower"
	TEST_ASSERT_EQUAL(length(console.checkouts), 0, "The real console begins without checkout records")
	test_ui(actor, console, "checkout", list())
	test_drain()
	TEST_ASSERT_EQUAL(length(console.checkouts), 1, "The checkout button creates one actual lending record")
	var/datum/borrowbook/record = console.checkouts[1]
	TEST_ASSERT(record && !QDELETED(record), "The created lending record is live")
	TEST_ASSERT_EQUAL(record.bookname, "Interim lending book", "The lending record retains the selected book")
	TEST_ASSERT_EQUAL(record.mobname, "Interim borrower", "The lending record retains the selected borrower")
	TEST_ASSERT_EQUAL(EXPIRY_LEFT(record, duedate, CLOCK_WORLD), 1 MINUTES, "The real record expires after the selected one-minute lending period")
	qdel(console)
	TEST_ASSERT(QDELETED(record), "Deleting the actual console deletes its owned lending record")
	test_driver_end()
