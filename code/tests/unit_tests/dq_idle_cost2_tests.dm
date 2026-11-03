// Idle-cost fixes, second set (doc/rewrite/server_bench_20261027.md): a vent that rewrote its flow reading every frame, docking controllers woken by every
// door broadcast on the frequency, and turrets that looked around with nobody there.

/// A flow reading is written when the value the gauge shows (one decimal) changes, and only then.
/datum/unit_test/dq_flow_rate_is_written_when_the_display_changes

/datum/unit_test/dq_flow_rate_is_written_when_the_display_changes/Run()
	var/obj/machinery/atmospherics/unary/vent_pump/vent = allocate(/obj/machinery/atmospherics/unary/vent_pump, run_loc_floor_bottom_left)
	vent.set_last_flow_rate(5)
	atmos_note_flow_rate(vent, 5.04)
	TEST_ASSERT_EQUAL(vent.last_flow_rate, 5, "a change below the display's resolution was written")
	atmos_note_flow_rate(vent, 5.2)
	TEST_ASSERT_EQUAL(vent.last_flow_rate, 5.2, "a change the display shows was not written")
	atmos_note_flow_rate(vent, 0)
	TEST_ASSERT_EQUAL(vent.last_flow_rate, 0, "a vent that stopped moving gas still showed a flow")

/// A docking controller wakes for a docking signal addressed to it, and for any traffic while a dock is in progress; not for the frequency's other traffic.
/datum/unit_test/dq_docking_controller_ignores_unrelated_radio

/datum/unit_test/dq_docking_controller_ignores_unrelated_radio/Run()
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/controller = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller, run_loc_floor_bottom_left)
	var/datum/embedded_program/docking/simple/program = controller.program
	TEST_ASSERT_NOTNULL(program, "the controller has a docking program")
	program.set_id_tag("dq_test_dock")
	program.tag_door = "dq_test_dock_hatch"
	var/datum/signal/door_report = new
	door_report.data = list("tag" = program.tag_door, "door_status" = "closed", "lock_status" = "locked")
	TEST_ASSERT(!program.signal_requires_processing(door_report), "an undocked controller woke for its door's status report")
	var/datum/signal/unrelated = new
	unrelated.data = list("tag" = "another_airlock", "recipient" = "someone_else")
	TEST_ASSERT(!program.signal_requires_processing(unrelated), "an undocked controller woke for another controller's traffic")
	var/datum/signal/addressed = new
	addressed.data = list("tag" = "shuttle", "command" = "request_dock", "recipient" = "dq_test_dock")
	TEST_ASSERT(program.signal_requires_processing(addressed), "a docking request addressed to the controller did not wake it")
	program.response_sent = 1 // a dock in progress is waiting on its peer
	TEST_ASSERT(program.signal_requires_processing(door_report), "a dock in progress ignored its door's report")
	program.response_sent = 0
	qdel(door_report)
	qdel(unrelated)
	qdel(addressed)

/// A turret looks around only when a mob is near, and the pre-test never misses a mob the look would find.
/datum/unit_test/dq_turret_mob_nearby_matches_what_it_sees

/datum/unit_test/dq_turret_mob_nearby_matches_what_it_sees/Run()
	var/turf/at = run_loc_floor_bottom_left
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, at)
	var/turf/beside = get_step(at, EAST)
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human, beside)
	TEST_ASSERT(turret.mob_nearby(world.view + 1), "a mob next to the turret was not found")
	TEST_ASSERT(!turret.mob_nearby(0) || person.loc == at, "a mob on the next tile counted as on the turret's own tile")
	for(var/mob/M in turret.scan_candidates())
		TEST_ASSERT(turret.mob_nearby(world.view + 1), "the look found [M] but the pre-test did not")

/// The pre-test follows a mob that walks between chunks, drops one that left or died out of the world.
/datum/unit_test/dq_turret_mob_nearby_follows_moves

/datum/unit_test/dq_turret_mob_nearby_follows_moves/Run()
	var/turf/at = run_loc_floor_bottom_left
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, at)
	TEST_ASSERT(!turret.mob_nearby(1), "nobody is beside the turret yet")
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human, locate(at.x + 3, at.y, at.z))
	TEST_ASSERT(turret.mob_nearby(3), "a mob three tiles off was not found")
	TEST_ASSERT(!turret.mob_nearby(2), "a mob three tiles off counted at two")
	person.forceMove(get_step(at, EAST))
	TEST_ASSERT(turret.mob_nearby(1), "a mob that moved beside the turret was not found")
	person.forceMove(locate(at.x + 40, at.y, at.z))
	TEST_ASSERT(!turret.mob_nearby(8), "a mob that crossed chunks away still counted")
	person.forceMove(get_step(at, EAST))
	TEST_ASSERT(turret.mob_nearby(1), "a mob that crossed chunks back was not found")
	qdel(person)
	TEST_ASSERT(!turret.mob_nearby(1), "a deleted mob still counted")

/// An armed turret with nobody near stops scanning, and a mob coming near wakes it through its chunk watch.
/datum/unit_test/dq_turret_parks_until_a_mob_stirs

/datum/unit_test/dq_turret_parks_until_a_mob_stirs/Run()
	var/turf/at = run_loc_floor_bottom_left
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, at)
	TEST_ASSERT(length(turret.watched_chunks), "the turret watches no mob chunks")
	turret.scan(null)
	TEST_ASSERT(!turret.mob_near, "a scan with nobody near kept the turret scanning")
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human, locate(at.x + 2, at.y, at.z))
	person.forceMove(get_step(at, EAST))
	TEST_ASSERT(turret.mob_near, "a mob coming near did not wake the turret's scan")

/// A cell's look follows its quarter charge step, not every change of charge: a whole-percent report that keeps the step changes nothing it draws.
/datum/unit_test/dq_cell_draw_follows_its_charge_step

/datum/unit_test/dq_cell_draw_follows_its_charge_step/Run()
	var/obj/item/cell/C = allocate(/obj/item/cell, run_loc_floor_bottom_left)
	C.set_charge(C.maxcharge)
	stat_drain_point()
	TEST_ASSERT_EQUAL(C.charge_step, 100, "a full cell does not show its full step")
	C.set_charge(C.maxcharge * 0.99)
	stat_drain_point()
	TEST_ASSERT_EQUAL(C.charge_step, 100, "a 1% drop moved the shown step")
	C.set_charge(C.maxcharge * 0.6)
	stat_drain_point()
	TEST_ASSERT_EQUAL(C.charge_step, 50, "crossing a quarter did not move the shown step")
	C.set_maxcharge(C.maxcharge * 4)
	stat_drain_point()
	TEST_ASSERT_EQUAL(C.charge_step, 25, "a larger capacity did not move the shown step")

/// A turret that sees only a mob it will not shoot (and no player) stops scanning until a mob stirs; a control panel's settings wake it.
/datum/unit_test/dq_turret_parks_beside_a_non_target

/datum/unit_test/dq_turret_parks_beside_a_non_target/Run()
	var/turf/at = run_loc_floor_bottom_left
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, at)
	turret.set_check_anomalies(FALSE) // an animal is then no target
	turret.set_check_all(FALSE)
	allocate(/mob/living/simple_mob/animal/passive/mouse, locate(at.x + 2, at.y, at.z))
	TEST_ASSERT(turret.mob_nearby(world.view + 1), "the mouse is not near the turret")
	turret.scan(null)
	TEST_ASSERT(!turret.mob_near, "a scan that found only a mouse it will not shoot kept the turret scanning")
	turret.setState(new /datum/turret_checks)
	TEST_ASSERT(turret.mob_near, "new settings from a control panel did not wake the turret's scan")

/// A docked airlock port rests like a door-only one: its handshake is over and the airlock is not cycling.
/datum/unit_test/dq_docked_airlock_port_rests

/datum/unit_test/dq_docked_airlock_port_rests/Run()
	var/obj/machinery/embedded_controller/radio/airlock/docking_port/port = allocate(/obj/machinery/embedded_controller/radio/airlock/docking_port, test_floor())
	var/datum/embedded_program/docking/airlock/program = port.program
	TEST_ASSERT_NOTNULL(program, "the port has its program")
	program.control_mode = 2 // MODE_CLIENT
	program.set_dock_state(3) // STATE_DOCKED
	TEST_ASSERT(!program.airlock_program.needs_processing(), "the port's airlock is cycling with nobody about")
	TEST_ASSERT(!program.needs_processing(), "a docked airlock port kept stepping")

/// An empty cryopod's despawn watch stops, and an everburn candle has no burn step.
/datum/unit_test/dq_idle_cryopod_and_everburn_rest

/datum/unit_test/dq_idle_cryopod_and_everburn_rest/Run()
	var/obj/machinery/cryopod/pod = allocate(/obj/machinery/cryopod, test_floor())
	TEST_ASSERT_EQUAL(pod.work_step(null), PROCESS_KILL, "an empty cryopod kept its despawn watch running")
	var/obj/item/flame/candle/everburn/candle = allocate(/obj/item/flame/candle/everburn, test_floor())
	TEST_ASSERT(candle.lit, "the everburn candle is not lit")
	TEST_ASSERT(!candle.burns_fuel, "the everburn candle still burns fuel every 2 s")
