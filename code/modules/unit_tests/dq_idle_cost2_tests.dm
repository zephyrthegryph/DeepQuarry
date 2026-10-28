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
	program.id_tag = "dq_test_dock"
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
