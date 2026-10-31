// A docking handshake runs to completion through the embedded controller's wake-on-signal step (it used to stop after one step
// because the docking program never reported "processing"), and the storage bar routes a click on a slot by what the actor holds.

/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_test_client
	id_tag = "dq_test_dock_client"

/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_test_server
	id_tag = "dq_test_dock_server"

/// Builds a client and a server docking controller on the test floor, with the kernel on its injected clock.
/datum/unit_test/dq_docking_controller_work
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/client
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/server

/datum/unit_test/dq_docking_controller_work/Run()
	test_driver_begin()
	var/turf/floor = test_floor()
	client = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_test_client, floor)
	server = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller/dq_test_server, floor)
	run_docking()
	test_driver_end()

/datum/unit_test/dq_docking_controller_work/proc/run_docking()
	return

/// The docking state of `C`'s program as its text.
/datum/unit_test/dq_docking_controller_work/proc/status(obj/machinery/embedded_controller/C)
	var/datum/embedded_program/docking/D = C.program
	return D.get_docking_status()

/// Docks the client with the server and lets time pass until both report docked.
/datum/unit_test/dq_docking_controller_work/proc/dock()
	var/datum/embedded_program/docking/client_program = client.program
	client_program.initiate_docking(server.program.id_tag)
	test_time(30 SECONDS)

/datum/unit_test/dq_docking_controller_work/docks_to_completion

/datum/unit_test/dq_docking_controller_work/docks_to_completion/run_docking()
	dock()
	TEST_ASSERT_EQUAL(status(client), "docked", "the client finished docking")
	TEST_ASSERT_EQUAL(status(server), "docked", "the server finished docking")

/datum/unit_test/dq_docking_controller_work/undocks_to_completion

/datum/unit_test/dq_docking_controller_work/undocks_to_completion/run_docking()
	dock()
	TEST_ASSERT_EQUAL(status(client), "docked", "docked before undocking")
	var/datum/embedded_program/docking/client_program = client.program
	client_program.initiate_undocking()
	test_time(30 SECONDS)
	TEST_ASSERT_EQUAL(status(client), "undocked", "the client finished undocking")
	TEST_ASSERT_EQUAL(status(server), "undocked", "the server finished undocking")

/// A click on a bag's storage bar segment: another item in hand goes to the bag, an empty hand takes the stored item.
/datum/unit_test/dq_storage_slot_click_routing

/datum/unit_test/dq_storage_slot_click_routing/Run()
	var/turf/floor = test_floor()
	var/obj/item/storage/backpack/bag = allocate(/obj/item/storage/backpack, floor)
	var/obj/item/storage/box/stored = allocate(/obj/item/storage/box, floor)
	var/obj/item/clipboard/held = allocate(/obj/item/clipboard, floor)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, floor)
	bag.handle_item_insertion(stored, TRUE)
	var/atom/movable/storage_slot/slot = allocate(/atom/movable/storage_slot, null, stored)
	TEST_ASSERT_EQUAL(slot.slot_click_target(user, stored), stored, "an empty hand clicks the stored item")
	user.put_in_active_hand(held)
	TEST_ASSERT_EQUAL(user.get_active_hand(), held, "the clipboard is in hand")
	TEST_ASSERT_EQUAL(slot.slot_click_target(user, stored), bag, "an item in hand clicks the bag")
	TEST_ASSERT_EQUAL(slot.slot_click_target(user, held), held, "holding the slot's own item still clicks it")

// ---- Airlock docking ports: doors, pump and controller of each port on the radio ----

/obj/machinery/embedded_controller/radio/airlock/docking_port/dq_test_client
	id_tag = "dq_air_client"

/obj/machinery/embedded_controller/radio/airlock/docking_port/dq_test_server
	id_tag = "dq_air_server"

/obj/machinery/door/airlock/dq_test_door
	frequency = AIRLOCK_FREQ

/obj/machinery/door/airlock/dq_test_door/client_outer
	id_tag = "dq_air_client_outer"
/obj/machinery/door/airlock/dq_test_door/client_inner
	id_tag = "dq_air_client_inner"
/obj/machinery/door/airlock/dq_test_door/server_outer
	id_tag = "dq_air_server_outer"
/obj/machinery/door/airlock/dq_test_door/server_inner
	id_tag = "dq_air_server_inner"

/obj/machinery/atmospherics/unary/vent_pump/dq_test_pump
	frequency = AIRLOCK_FREQ

/obj/machinery/atmospherics/unary/vent_pump/dq_test_pump/client
	id_tag = "dq_air_client_pump"
/obj/machinery/atmospherics/unary/vent_pump/dq_test_pump/server
	id_tag = "dq_air_server_pump"

/// Two airlock docking ports, each with its own doors and chamber pump on the airlock radio frequency.
/datum/unit_test/dq_airlock_docking_ports
	var/obj/machinery/embedded_controller/radio/airlock/docking_port/client
	var/obj/machinery/embedded_controller/radio/airlock/docking_port/server
	var/list/doors

/datum/unit_test/dq_airlock_docking_ports/Run()
	test_driver_begin()
	var/turf/floor = test_floor()
	client = allocate(/obj/machinery/embedded_controller/radio/airlock/docking_port/dq_test_client, floor)
	server = allocate(/obj/machinery/embedded_controller/radio/airlock/docking_port/dq_test_server, floor)
	allocate(/obj/machinery/atmospherics/unary/vent_pump/dq_test_pump/client, floor)
	allocate(/obj/machinery/atmospherics/unary/vent_pump/dq_test_pump/server, floor)
	doors = list(
		allocate(/obj/machinery/door/airlock/dq_test_door/client_outer, floor),
		allocate(/obj/machinery/door/airlock/dq_test_door/client_inner, floor),
		allocate(/obj/machinery/door/airlock/dq_test_door/server_outer, floor),
		allocate(/obj/machinery/door/airlock/dq_test_door/server_inner, floor))
	test_time(5 SECONDS) // the doors report their state to their controllers
	run_ports()
	test_driver_end()

/datum/unit_test/dq_airlock_docking_ports/proc/run_ports()
	return

/datum/unit_test/dq_airlock_docking_ports/proc/status(obj/machinery/embedded_controller/C)
	var/datum/embedded_program/docking/D = C.program
	return D.get_docking_status()

/datum/unit_test/dq_airlock_docking_ports/proc/dock()
	var/datum/embedded_program/docking/client_program = client.program
	client_program.initiate_docking("dq_air_server")
	test_time(60 SECONDS)

/datum/unit_test/dq_airlock_docking_ports/docks_and_undocks

/datum/unit_test/dq_airlock_docking_ports/docks_and_undocks/run_ports()
	dock()
	TEST_ASSERT_EQUAL(status(client), "docked", "the client port finished docking")
	TEST_ASSERT_EQUAL(status(server), "docked", "the server port finished docking")
	for(var/obj/machinery/door/airlock/D as anything in doors)
		TEST_ASSERT(!D.density, "[D.id_tag] opened when docking finished")
	var/datum/embedded_program/docking/client_program = client.program
	client_program.initiate_undocking()
	test_time(60 SECONDS)
	TEST_ASSERT_EQUAL(status(client), "undocked", "the client port finished undocking")
	TEST_ASSERT_EQUAL(status(server), "undocked", "the server port finished undocking")
	for(var/obj/machinery/door/airlock/D as anything in doors)
		TEST_ASSERT(D.density, "[D.id_tag] closed for undocking")
