/// Observe the real successor before its existing zero-delay close timer drains.
/datum/interim_windoor_completion_trace
	var/prepared_open = FALSE
	var/prepared_ref

/datum/interim_windoor_completion_trace/proc/record(turf/T)
	var/obj/machinery/door/window/door = locate_within(T, /obj/machinery/door/window)
	if(door)
		prepared_open = !door.density
		prepared_ref = REF(door)

/obj/structure/windoor_assembly/interim_completion_trace
	var/datum/interim_windoor_completion_trace/trace

/obj/structure/windoor_assembly/interim_completion_trace/finish_windoor(datum/act/op/A)
	var/datum/interim_windoor_completion_trace/saved_trace = trace
	var/turf/T = get_turf(src)
	. = ..()
	saved_trace.record(T)

/obj/structure/windoor_assembly/secure/interim_completion_trace
	var/datum/interim_windoor_completion_trace/trace

/obj/structure/windoor_assembly/secure/interim_completion_trace/finish_windoor(datum/act/op/A)
	var/datum/interim_windoor_completion_trace/saved_trace = trace
	var/turf/T = get_turf(src)
	. = ..()
	saved_trace.record(T)

/// Real final completion must preserve configured parts and prepare exactly one floor windoor.
/datum/unit_test/interim_windoor_completion
	parent_type = /datum/unit_test/dq_p2_reagents
	var/secure_case = FALSE

/datum/unit_test/interim_windoor_completion/secure
	secure_case = TRUE

/datum/unit_test/interim_windoor_completion/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/assembly_type = secure_case ? /obj/structure/windoor_assembly/secure/interim_completion_trace : /obj/structure/windoor_assembly/interim_completion_trace
	var/obj/structure/windoor_assembly/frame = allocate(assembly_type, T)
	var/datum/interim_windoor_completion_trace/trace = allocate(/datum/interim_windoor_completion_trace)
	if(secure_case)
		var/obj/structure/windoor_assembly/secure/interim_completion_trace/probe = frame
		rel_set(probe, nameof(probe.trace), trace)
	else
		var/obj/structure/windoor_assembly/interim_completion_trace/probe = frame
		rel_set(probe, nameof(probe.trace), trace)
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_FRAME), "actual frame starts at the bare construction stage")
	frame.set_dir(EAST)
	if(secure_case)
		test_menu(actor, frame, "flip")
		test_time(1 SECOND)
	TEST_ASSERT_EQUAL(frame.facing, secure_case ? "r" : "l", "actual flip input preserves configured facing")
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	rc_click(actor, frame, pen, I_HELP, FALSE)
	test_answer(actor, "Configured test windoor")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(frame.created_name, "Configured test windoor", "actual typed rename input configures the assembly name")
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	rc_click(actor, frame, wrench, I_HELP, FALSE)
	test_time(5 SECONDS)
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_SECURED) && frame.anchored, "actual wrench secures the construction stage")
	var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 2)
	rc_click(actor, frame, cable, I_HELP, FALSE)
	test_time(5 SECONDS)
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_WIRED), "actual cable insertion completes wiring")
	TEST_ASSERT_EQUAL(cable.get_amount(), 1, "actual wiring consumes exactly one cable length")
	var/obj/item/airlock_electronics/board = allocate(/obj/item/airlock_electronics, T)
	board.conf_access = list(ACCESS_SECURITY)
	board.set_one_access(secure_case)
	rc_click(actor, frame, board, I_HELP, FALSE)
	test_time(5 SECONDS)
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_BOARDED), "actual board insertion completes the installed-electronics stage")
	TEST_ASSERT_EQUAL(frame.electronics, board, "real board insertion retains exact configured electronics")
	var/frame_handle = entity_handle(frame)
	var/list/before = turf_contents_of_type(T, /obj/machinery/door/window)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	rc_click(actor, frame, crowbar, I_HELP, FALSE)
	test_time(5 SECONDS)
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
	TEST_ASSERT(trace.prepared_open, "The real completion prepares the successor open before its existing close timer drains")
	TEST_ASSERT_EQUAL(trace.prepared_ref, REF(door), "The observed open successor is the exact native construction product")
	TEST_ASSERT(door.density, "The existing zero-delay close timer closes the actual native successor")
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
	TEST_ASSERT_NULL(resolve_handle(frame_handle), "A structure assembly handle must terminate for its cross-family machinery successor")
	qdel(door)
	TEST_ASSERT(QDELETED(board), "The successor must own and delete the transferred electronics")
