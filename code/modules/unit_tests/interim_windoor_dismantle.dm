/// Real dismantling must preserve the installed configuration and electronics.
/datum/unit_test/interim_windoor_dismantle
	parent_type = /datum/unit_test/dq_p2_reagents
	var/has_installed_board = TRUE

/datum/unit_test/interim_windoor_dismantle/generated_electronics
	has_installed_board = FALSE

/datum/unit_test/interim_windoor_dismantle/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/obj/machinery/door/window/brigdoor/door = allocate(/obj/machinery/door/window/brigdoor, T)
	door.set_dir(WEST)
	door.base_state = "rightsecure"
	door.name = "Preserved windoor"
	door.req_access = null
	door.req_one_access = list(ACCESS_SECURITY)
	var/obj/item/airlock_electronics/board
	if(has_installed_board)
		board = allocate(/obj/item/airlock_electronics, door)
		board.conf_access = list(ACCESS_SECURITY)
		board.set_one_access(TRUE)
		rel_set(door, nameof(door.electronics), board)
	else
		TEST_ASSERT_NULL(door.electronics, "The generated-electronics fixture must have no installed board")
	var/obj/item/clothing/under/color/grey/uniform = allocate(/obj/item/clothing/under/color/grey, T)
	TEST_ASSERT(actor.equip_to_slot(uniform, SLOT_ID_UNIFORM), "actual uniform provides the real ID attachment slot")
	var/obj/item/card/id/id = allocate(/obj/item/card/id, T)
	id.access = list(ACCESS_SECURITY)
	TEST_ASSERT(actor.equip_to_slot(id, SLOT_ID_ID), "actual security ID satisfies the real windoor access guard")
	rc_click(actor, door, null, I_HELP, FALSE)
	test_time(2 SECONDS)
	TEST_ASSERT(!door.density && !door.operating, "actual admitted hand input opens and settles the windoor before prying")
	var/door_handle = entity_handle(door)
	var/list/before = turf_contents_of_type(T, /obj/structure/windoor_assembly)
	var/obj/item/tool/crowbar/crowbar = allocate(/obj/item/tool/crowbar, T)
	rc_click(actor, door, crowbar, I_HELP, FALSE)
	test_time(5 SECONDS)
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
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_BOARDED), "The actual boarded construction stage must survive")
	TEST_ASSERT_EQUAL(frame.sprite_state(), "02", "The real boarded stage retains the wired sprite state")
	TEST_ASSERT(frame.electronics && !QDELETED(frame.electronics), "The assembly must have surviving electronics")
	if(has_installed_board)
		TEST_ASSERT_EQUAL(frame.electronics, board, "The exact installed board must transfer")
	else
		board = frame.electronics
	TEST_ASSERT_EQUAL(board.loc, frame, "The board must physically remain inside the assembly")
	TEST_ASSERT_EQUAL(board.one_access, TRUE, "The one-access mode must survive")
	TEST_ASSERT_EQUAL(length(board.conf_access), 1, "The exact configured access count must survive")
	TEST_ASSERT_EQUAL(board.conf_access[1], ACCESS_SECURITY, "Security access must survive")
	TEST_ASSERT_NULL(resolve_handle(door_handle), "The machinery handle must terminate for its cross-family structure successor")
	qdel(frame)
	TEST_ASSERT(QDELETED(board), "The successor must own and delete its electronics")
