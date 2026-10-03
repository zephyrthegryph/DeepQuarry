/// Real dismantling must preserve the installed configuration and electronics.
/datum/unit_test/interim_windoor_dismantle
	var/has_installed_board = TRUE

/datum/unit_test/interim_windoor_dismantle/generated_electronics
	has_installed_board = FALSE

/datum/unit_test/interim_windoor_dismantle/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/window/brigdoor/door = allocate(/obj/machinery/door/window/brigdoor, T)
	door.set_dir(WEST)
	door.set_density(FALSE)
	door.base_state = "rightsecure"
	door.name = "Preserved windoor"
	door.req_access = null
	door.req_one_access = list(ACCESS_SECURITY)
	var/obj/item/airlock_electronics/board
	if(has_installed_board)
		board = allocate(/obj/item/airlock_electronics, door)
		board.conf_access = list(ACCESS_SECURITY)
		board.set_one_access(TRUE)
		own_set(door, nameof(door.electronics), board)
	else
		TEST_ASSERT_NULL(door.electronics, "The generated-electronics fixture must have no installed board")
	var/door_handle = om_handle(door)
	var/list/before = turf_contents_of_type(T, /obj/structure/windoor_assembly)
	door.crowbar_act_tool_done(actor)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(door), "Dismantling must remove the installed windoor")
	var/list/created = turf_contents_of_type(T, /obj/structure/windoor_assembly) - before
	TEST_ASSERT_EQUAL(length(created), 1, "Dismantling must create exactly one assembly")
	var/obj/structure/windoor_assembly/frame = created[1]
	TEST_ASSERT_EQUAL(frame.loc, T, "The assembly must stay on the actual windoor floor")
	TEST_ASSERT_EQUAL(frame.anchored, TRUE, "The assembly must remain secured")
	TEST_ASSERT_EQUAL(frame.secure, "secure_", "The secure configuration must survive")
	TEST_ASSERT_EQUAL(frame.facing, "r", "The right-facing configuration must survive")
	TEST_ASSERT_EQUAL(frame.dir, WEST, "Direction must survive")
	TEST_ASSERT_EQUAL(frame.created_name, "Preserved windoor", "The configured name must survive")
	TEST_ASSERT_EQUAL(frame.state, "02", "The wired state must survive")
	TEST_ASSERT_EQUAL(frame.step, 2, "The installed-electronics step must survive")
	TEST_ASSERT(frame.electronics && !QDELETED(frame.electronics), "The assembly must have surviving electronics")
	if(has_installed_board)
		TEST_ASSERT_EQUAL(frame.electronics, board, "The exact installed board must transfer")
	else
		board = frame.electronics
	TEST_ASSERT_EQUAL(board.loc, frame, "The board must physically remain inside the assembly")
	TEST_ASSERT_EQUAL(board.one_access, TRUE, "The one-access mode must survive")
	TEST_ASSERT_EQUAL(length(board.conf_access), 1, "The exact configured access count must survive")
	TEST_ASSERT_EQUAL(board.conf_access[1], ACCESS_SECURITY, "Security access must survive")
	TEST_ASSERT_NULL(om_resolve(door_handle), "The machinery handle must terminate for its cross-family structure successor")
	qdel(frame)
	TEST_ASSERT(QDELETED(board), "The successor must own and delete its electronics")
