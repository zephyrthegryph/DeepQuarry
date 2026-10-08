/// Complete current non-machine frame edges without inventing new construction forms.
/datum/unit_test/proc/interim_finish_console_frame(board_type, alarm)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	var/obj/structure/frame/frame = allocate(/obj/structure/frame, T)
	var/obj/item/circuitboard/board = allocate(board_type, T)
	rel_set(frame, nameof(frame.frame_type), frame_type_copy(board.board_type))
	frame.set_dir(WEST)
	frame.pixel_x = 7
	frame.pixel_y = -3
	var/expected_type = board.build_path
	var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 6)
	TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_placed.anchor"), "The console fixture must anchor")
	TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_board_in.insert_board", board), "The console fixture must accept its real board")
	TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_fastened.fasten_board"), "The console fixture must fasten its board")
	TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_wired.wire", cable), "The console fixture must consume wiring")
	TEST_ASSERT_EQUAL(cable.get_amount(), 1, "Wiring must consume exactly five cable lengths")
	var/finish_type = "construction.build:machine_frame_finished.finish_alarm"
	if(!alarm)
		var/obj/item/stack/material/glass/glass = allocate(/obj/item/stack/material/glass, T, 3)
		TEST_ASSERT(interim_native_frame_step(frame, actor, "construction.build:machine_frame_paneled.add_glass", glass), "Computer construction must install its glass panel")
		TEST_ASSERT_EQUAL(glass.get_amount(), 1, "Panel installation must consume exactly two glass sheets")
		finish_type = "construction.build:machine_frame_finished.connect_monitor"
	var/old_handle = om_handle(frame)
	var/completed = interim_native_frame_step(frame, actor, finish_type)
	// Generated successors must be registered even if a following assertion fails.
	own_turf_contents(T)
	TEST_ASSERT(completed, "The real final construction edge must complete")
	TEST_ASSERT(QDELETED(frame), "Completing construction must destroy the original frame")
	TEST_ASSERT_NULL(om_resolve(old_handle), "The frame identity must terminate for a successor outside the structure/frame family")
	var/obj/machinery/successor = locate_within(T, expected_type)
	TEST_ASSERT(successor, "Completion must build the exact board-declared machinery type")
	TEST_ASSERT_EQUAL(successor.circuit, board, "The successor must own the player's exact circuit board")
	TEST_ASSERT(!QDELETED(board), "Destroying the frame must preserve the transferred board")
	TEST_ASSERT_NULL(board.loc, "Current console construction keeps its owned board in nullspace")
	TEST_ASSERT_EQUAL(successor.dir, WEST, "Completion must preserve frame direction")
	TEST_ASSERT_EQUAL(successor.pixel_x, 7, "Completion must preserve horizontal frame offset")
	TEST_ASSERT_EQUAL(successor.pixel_y, -3, "Completion must preserve vertical frame offset")

/datum/unit_test/interim_alarm_frame_finalization/Run()
	test_driver_begin()
	defer_cleanup(src, PROC_REF(interim_native_frame_driver_end))
	interim_finish_console_frame(/obj/item/circuitboard/firealarm, TRUE)

/datum/unit_test/interim_computer_frame_finalization/Run()
	test_driver_begin()
	defer_cleanup(src, PROC_REF(interim_native_frame_driver_end))
	interim_finish_console_frame(/obj/item/circuitboard/arcade/battle, FALSE)
