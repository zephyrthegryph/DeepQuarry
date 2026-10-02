/// Real airlock dismantling leaves one assembly and separately released electronics on the floor.
/datum/unit_test/interim_airlock_dismantle
	var/has_installed_board = TRUE

/datum/unit_test/interim_airlock_dismantle/generated_electronics
	has_installed_board = FALSE

/datum/unit_test/interim_airlock_dismantle/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, T)
	door.set_anchored(TRUE)
	door.name = "Configured airlock"
	door.glass = TRUE
	door.req_access = null
	door.req_one_access = list(ACCESS_SECURITY)
	var/obj/item/airlock_electronics/board
	if(has_installed_board)
		board = allocate(/obj/item/airlock_electronics, door)
		board.conf_access = list(ACCESS_SECURITY)
		board.one_access = TRUE
		own_set(door, nameof(door.electronics), board)
	else
		TEST_ASSERT_NULL(door.electronics, "The generated-board case must start without installed electronics")
	var/door_handle = om_handle(door)
	var/list/before_frames = turf_contents_of_type(T, /obj/structure/door_assembly)
	var/list/before_boards = turf_contents_of_type(T, /obj/item/airlock_electronics)
	door.crowbar_act_tool_done(actor)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(door), "The real completion callback must remove the airlock")
	var/list/frames = turf_contents_of_type(T, /obj/structure/door_assembly) - before_frames
	TEST_ASSERT_EQUAL(length(frames), 1, "Dismantling must produce exactly one assembly")
	var/obj/structure/door_assembly/frame = frames[1]
	TEST_ASSERT_EQUAL(frame.type, /obj/structure/door_assembly, "The configured assembly type must be produced")
	TEST_ASSERT_EQUAL(frame.loc, T, "The prepared assembly must stay on the airlock floor")
	TEST_ASSERT_EQUAL(frame.anchored, TRUE, "The prepared assembly must remain secured")
	TEST_ASSERT_EQUAL(frame.glass, 1, "The glass configuration must survive dismantling")
	TEST_ASSERT_EQUAL(frame.state, 1, "The prepared assembly must retain the wired state")
	TEST_ASSERT_EQUAL(frame.created_name, "Configured airlock", "The configured name must survive dismantling")
	TEST_ASSERT_NULL(frame.electronics, "The released board must remain separate from the prepared assembly")
	var/list/boards = turf_contents_of_type(T, /obj/item/airlock_electronics) - before_boards
	TEST_ASSERT_EQUAL(length(boards), 1, "Dismantling must release exactly one electronics board")
	if(has_installed_board)
		TEST_ASSERT_EQUAL(boards[1], board, "The exact installed electronics must be released")
	else
		board = boards[1]
	TEST_ASSERT(!QDELETED(board), "The released electronics must survive removal of their old owner")
	TEST_ASSERT_EQUAL(board.loc, T, "The released electronics must remain on the actual floor")
	TEST_ASSERT_EQUAL(board.one_access, TRUE, "The one-access mode must survive")
	TEST_ASSERT_EQUAL(length(board.conf_access), 1, "The configured access count must survive")
	TEST_ASSERT_EQUAL(board.conf_access[1], ACCESS_SECURITY, "Security access must survive")
	TEST_ASSERT_NULL(om_resolve(door_handle), "An airlock handle must terminate for its cross-family structure successor")
	qdel(frame)
	TEST_ASSERT(!QDELETED(board), "The separate electronics must not become owned by the successor assembly")
	TEST_ASSERT_EQUAL(board.loc, T, "Deleting the assembly must preserve the independent floor board")
