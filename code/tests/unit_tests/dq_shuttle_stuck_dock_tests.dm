// The round never ended because the emergency shuttle waited at the station for a docking port that never finished docking: the port
// stayed "docking" (an airlock cycle that did not complete), a launch asked it to undock (a no-op unless docked), and the shuttle sat in
// WAIT_LAUNCH for hours. A launch now abandons a docking in flight, and a launch whose undock never completes forces it after the dock timeout.

/datum/shuttle/autodock/ferry/dq_stuck_dock_stub
	shuttle_area = /area
	defer_initialisation = TRUE

/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_stuck_client
	id_tag = "dq_stuck_client"

/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_stuck_server
	id_tag = "dq_stuck_server"

/datum/unit_test/dq_shuttle_stuck_dock
	abstract_type = /datum/unit_test/dq_shuttle_stuck_dock
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/client
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/server
	var/datum/shuttle/autodock/ferry/dq_stuck_dock_stub/ferry

/datum/unit_test/dq_shuttle_stuck_dock/Run()
	test_driver_begin()
	var/turf/floor = test_floor()
	client = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_stuck_client, floor)
	server = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_stuck_server, floor)
	ferry = allocate(/datum/shuttle/autodock/ferry/dq_stuck_dock_stub)
	ferry.set_shuttle_docking_controller(client.port)
	run_case()
	test_driver_end()

/datum/unit_test/dq_shuttle_stuck_dock/proc/run_case()
	return

/// A launch asked while the port is still docking abandons the docking: both ports are undocked at once, so the shuttle can leave.
/datum/unit_test/dq_shuttle_stuck_dock/launch_while_docking

/datum/unit_test/dq_shuttle_stuck_dock/launch_while_docking/run_case()
	client.port.initiate_docking(server.port.id_tag)
	TEST_ASSERT_EQUAL(client.port.get_docking_status(), "docking", "the client is mid-docking")
	TEST_ASSERT(!ferry.check_undocked(), "a docking in flight is not undocked")
	ferry.undock()
	TEST_ASSERT(ferry.check_undocked(), "asking to leave a docking in flight abandons it")
	TEST_ASSERT_EQUAL(server.port.get_docking_status(), "undocked", "the server port was reset with the client")

/// A shuttle queued to launch whose port never undocks leaves after the dock timeout.
/datum/unit_test/dq_shuttle_stuck_dock/launch_times_out

/datum/unit_test/dq_shuttle_stuck_dock/launch_times_out/run_case()
	client.port.initiate_docking(server.port.id_tag)
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(client.port.get_docking_status(), "docked", "docked before the launch")
	ferry.set_process_state(WAIT_LAUNCH)
	STAMP(ferry, launch_queued_at, CLOCK_WORLD)
	ferry.shuttle_step()
	TEST_ASSERT_EQUAL(ferry.process_state, WAIT_LAUNCH, "within the timeout it keeps waiting for the undock")
	ferry.launch_queued_at = world.time - (DOCK_ATTEMPT_TIMEOUT + 10)
	ferry.shuttle_step()
	TEST_ASSERT(ferry.process_state != WAIT_LAUNCH, "after the timeout the launch proceeds")
	TEST_ASSERT_EQUAL(client.port.get_docking_status(), "undocked", "the port was forced undocked")

/// The round ends when the emergency shuttle has been to the station and is idle back at centcom.
/datum/unit_test/dq_emergency_return_ends_round

/datum/unit_test/dq_emergency_return_ends_round/Run()
	var/datum/system/emergency_shuttle/original_owner = SSemergency_shuttle
	var/datum/system/emergency_shuttle/original_registered = system_table()[/datum/system/emergency_shuttle]
	defer_cleanup(src, PROC_REF(restore_owner), original_owner, original_registered)
	var/datum/system/emergency_shuttle/emergency = allocate(/datum/system/emergency_shuttle)
	SSemergency_shuttle = emergency
	var/datum/shuttle/autodock/ferry/emergency/boundary/ferry = allocate(/datum/shuttle/autodock/ferry/emergency/boundary)
	restore_owner(original_owner, original_registered)
	set_var(ferry, "moving_status", SHUTTLE_IDLE)
	set_var(ferry, "location", FERRY_LOCATION_STATION)
	TEST_ASSERT(!emergency.returned(), "never departed: the round goes on")
	emergency.departed = TRUE
	TEST_ASSERT(!emergency.returned(), "departed but still at the station: the round goes on")
	set_var(ferry, "location", FERRY_LOCATION_OFFSITE)
	TEST_ASSERT(emergency.returned(), "back at centcom after leaving the station: the round ends")

/datum/unit_test/dq_emergency_return_ends_round/proc/restore_owner(datum/system/emergency_shuttle/owner, datum/system/emergency_shuttle/registered)
	SSemergency_shuttle = owner
	var/list/table = system_table()
	if(registered)
		table[/datum/system/emergency_shuttle] = registered
	else
		table -= /datum/system/emergency_shuttle

/// A holomap whose setup never made its image builds one when someone looks, instead of runtime-ing on a null image.
/datum/unit_test/dq_holomap_builds_missing_image

/datum/unit_test/dq_holomap_builds_missing_image/Run()
	var/obj/machinery/station_map/map = allocate(/obj/machinery/station_map, test_floor())
	map.holomap_datum.station_map = null
	TEST_ASSERT(map.ensure_map_image(null), "a map with no image builds one")
	TEST_ASSERT_NOTNULL(map.holomap_datum.station_map, "the image exists to fade in")
