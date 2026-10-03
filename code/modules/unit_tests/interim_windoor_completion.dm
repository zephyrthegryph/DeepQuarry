/// Real final completion must preserve configured parts and prepare exactly one floor windoor.
/datum/unit_test/interim_windoor_completion
	var/secure_case = FALSE

/datum/unit_test/interim_windoor_completion/secure
	secure_case = TRUE

/datum/unit_test/interim_windoor_completion/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/assembly_type = secure_case ? /obj/structure/windoor_assembly/secure : /obj/structure/windoor_assembly
	var/obj/structure/windoor_assembly/frame = allocate(assembly_type, T)
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, frame)
	own_set(frame, nameof(frame.electronics), board)
	frame.state = "02"
	frame.step = 2
	frame.set_anchored(TRUE)
	frame.set_dir(EAST)
	frame.facing = secure_case ? "r" : "l"
	frame.created_name = "Configured test windoor"
	board.conf_access = list(ACCESS_SECURITY)
	board.set_one_access(secure_case)
	var/frame_handle = om_handle(frame)
	var/list/before = turf_contents_of_type(T, /obj/machinery/door/window)
	frame.crowbar_act_tool_done(actor)
	// Register the real callback-generated successor before any assertion can stop the test.
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(frame), "The completed assembly must be removed")
	var/list/created = turf_contents_of_type(T, /obj/machinery/door/window) - before
	TEST_ASSERT_EQUAL(length(created), 1, "Completion must prepare exactly one windoor")
	var/obj/machinery/door/window/door = created[1]
	var/expected_type = secure_case ? /obj/machinery/door/window/brigdoor : /obj/machinery/door/window
	TEST_ASSERT_EQUAL(door.type, expected_type, "The secure setting must select the actual windoor type")
	TEST_ASSERT_EQUAL(door.loc, T, "The installed windoor must remain on the assembly floor")
	TEST_ASSERT_EQUAL(door.dir, EAST, "Completion must preserve the configured direction")
	TEST_ASSERT_EQUAL(door.name, "Configured test windoor", "Completion must preserve the configured name")
	TEST_ASSERT_EQUAL(door.base_state, secure_case ? "rightsecure" : "left", "Completion must preserve the configured facing")
	TEST_ASSERT_EQUAL(door.density, FALSE, "The prepared windoor must start open before its existing close timer fires")
	TEST_ASSERT(!QDELETED(board), "Deleting the old assembly must preserve its transferred electronics")
	TEST_ASSERT_EQUAL(door.electronics, board, "The exact configured electronics must belong to the successor")
	TEST_ASSERT_EQUAL(board.loc, door, "The transferred electronics must physically remain inside the successor")
	if(secure_case)
		TEST_ASSERT_NULL(door.req_access, "One-access electronics must clear all-access requirements")
		TEST_ASSERT_EQUAL(length(door.req_one_access), 1, "The one-access list must retain exactly the configured access")
		TEST_ASSERT_EQUAL(door.req_one_access[1], ACCESS_SECURITY, "The one-access setting must survive construction")
	else
		TEST_ASSERT_EQUAL(length(door.req_access), 1, "The all-access list must retain exactly the configured access")
		TEST_ASSERT_EQUAL(door.req_access[1], ACCESS_SECURITY, "The all-access setting must survive construction")
	TEST_ASSERT_NULL(om_resolve(frame_handle), "A structure assembly handle must terminate for its cross-family machinery successor")
	qdel(door)
	TEST_ASSERT(QDELETED(board), "The successor must own and delete the transferred electronics")
