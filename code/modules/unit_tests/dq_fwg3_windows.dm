// fw-gaps3 content pins for window routing (fallback, forward, override): the embedded controllers, the telecrystal storage, the sleeper and its
// console, the air alarm and the atmospherics filters. Written on the legacy UI declarations first; buttons go through hc_ui() (the engine's op when
// the host has one for the action, else today's tgui_act() with an interactive window), data through hc_data(), questions through p2cl_answer().

/datum/unit_test/dq_fwg3_ui
	abstract_type = /datum/unit_test/dq_fwg3_ui

/datum/unit_test/dq_fwg3_ui/Run()
	test_driver_begin()
	p2cl_capture_prompts()
	run_fwg3()
	test_driver_end()

/datum/unit_test/dq_fwg3_ui/proc/run_fwg3()
	return

/datum/unit_test/dq_fwg3_ui/proc/person(turf/T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T || run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// A docking controller's program commands are the window's fallback: a listed command reaches the program, an unlisted one does nothing.
/datum/unit_test/dq_fwg3_ui/docking_controller
/datum/unit_test/dq_fwg3_ui/docking_controller/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/C = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller, T)
	var/datum/embedded_program/docking/simple/P = C.program
	TEST_ASSERT(!P.override_enabled, "the override starts off")
	hc_ui(H, C, "toggle_override")
	TEST_ASSERT(P.override_enabled, "toggle_override reaches the program through the fallback")
	hc_ui(H, C, "no_such_command")
	TEST_ASSERT(P.override_enabled, "an unlisted command does nothing")
	hc_ui(H, C, "toggle_override")
	TEST_ASSERT(!P.override_enabled, "and the listed one toggles it back")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["internalTemplateName"], "DockingConsoleSimple", "the subtype's own window data")
	TEST_ASSERT_EQUAL(data["override_enabled"], P.override_enabled, "with the program's override")
	var/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod/pod = allocate(/obj/machinery/embedded_controller/radio/simple_docking_controller/escape_pod, T)
	data = hc_data(pod, H)
	TEST_ASSERT_EQUAL(data["internalTemplateName"], "EscapePodConsole", "an escape pod's data replaces the docking controller's")

/// An airlock controller's tag and frequency settings work only with its panel open; its program commands work with the panel shut.
/datum/unit_test/dq_fwg3_ui/airlock_controller
/datum/unit_test/dq_fwg3_ui/airlock_controller/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/embedded_controller/radio/airlock/docking_port/C = allocate(/obj/machinery/embedded_controller/radio/airlock/docking_port, T)
	var/start = C.frequency
	var/target = start == 1381 ? 1383 : 1381
	hc_ui(H, C, "set_frequency", list("freq" = target))
	TEST_ASSERT_EQUAL(C.frequency, start, "a shut panel refuses the frequency")
	C.set_panel_open(TRUE)
	hc_ui(H, C, "set_frequency", list("freq" = target))
	TEST_ASSERT_EQUAL(C.frequency, target, "an open panel sets it")
	var/obj/machinery/embedded_controller/radio/airlock/plain = allocate(/obj/machinery/embedded_controller/radio/airlock, T)
	plain.set_panel_open(TRUE)
	TEST_ASSERT_EQUAL(hc_data(plain, H)["panel_open"], TRUE, "a plain airlock controller's window shows its panel")
	C.set_panel_open(FALSE)
	var/datum/embedded_program/docking/airlock/P = C.program
	var/before = P.override_enabled
	hc_ui(H, C, "toggle_override")
	TEST_ASSERT(P.override_enabled != before, "a program command works with the panel shut (the window's fallback is not behind the panel)")

/// Telecrystal storage: Release with an amount takes that many out; without one it asks how many. The fridge's own Release runs first.
/datum/unit_test/dq_fwg3_ui/telecrystal_storage
/datum/unit_test/dq_fwg3_ui/telecrystal_storage/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/smartfridge/tcrystal/S = allocate(/obj/machinery/smartfridge/tcrystal, T)
	S.stock(new /obj/item/stack/telecrystal(T, 10))
	TEST_ASSERT_EQUAL(LAZYLEN(S.item_records), 1, "one record of crystals")
	var/datum/stored_item/R = S.item_records[1]
	TEST_ASSERT_EQUAL(R.get_amount(), 10, "ten stocked")
	hc_ui(H, S, "Release", list("amount" = 3, "index" = 1))
	TEST_ASSERT_EQUAL(R.get_amount(), 7, "three taken out")
	hc_ui(H, S, "Release", list("index" = 1))
	p2cl_answer(H, 2)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(R.get_amount(), 5, "asked, two more taken out")
	var/count = 0
	for(var/obj/item/stack/telecrystal/C in T.contents.Copy())
		count += C.get_amount()
		qdel(C)
	TEST_ASSERT_EQUAL(count, 5, "five crystals on the floor")
	var/list/data = hc_data(S, H)
	TEST_ASSERT_EQUAL(length(data["contents"]), 1, "the window lists the record")
	qdel(S) // its stock spills: clear it off the block
	for(var/obj/item/stack/telecrystal/C in T.contents.Copy())
		qdel(C)

/// Sleeper: its console's window is the sleeper's (forwarded buttons, the sleeper's data); an open panel refuses the sleeper's buttons.
/datum/unit_test/dq_fwg3_ui/sleeper
/datum/unit_test/dq_fwg3_ui/sleeper/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/next = locate(T.x + 1, T.y, T.z)
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, next)
	var/obj/machinery/sleep_console/console = allocate(/obj/machinery/sleep_console, T)
	test_time(1 SECOND) // paired_console(): the console pairs when its init is complete
	TEST_ASSERT_EQUAL(console.sleeper, S, "the console found its sleeper")
	hc_ui(H, console, "auto_eject_dead_on")
	TEST_ASSERT(S.auto_eject_dead, "a button pressed on the console reaches the sleeper")
	hc_ui(H, S, "auto_eject_dead_off")
	TEST_ASSERT(!S.auto_eject_dead, "and on the sleeper itself")
	var/list/data = hc_data(console, H)
	TEST_ASSERT_EQUAL(data["maxchem"], S.max_chem, "the console shows the sleeper's data")
	TEST_ASSERT_EQUAL(data["auto_eject_dead"], FALSE, "including its settings")
	S.set_panel_open(TRUE)
	hc_ui(H, S, "auto_eject_dead_on")
	TEST_ASSERT(!S.auto_eject_dead, "an open panel refuses the buttons")
	S.set_panel_open(FALSE)
	hc_ui(H, S, "changestasis")
	p2cl_answer(H, "Light (50%)")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(S.stasis_rate, 0.5, "the stasis question sets the level")

/// Air alarm: a locked alarm refuses a person's mode change; unlocked it takes it; the thermostat question sets the target.
/datum/unit_test/dq_fwg3_ui/air_alarm
/datum/unit_test/dq_fwg3_ui/air_alarm/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/alarm/A = allocate(/obj/machinery/alarm, T)
	cap_key_set(A, LOCK_LOCKED, TRUE, null)
	var/start = A.mode
	var/other = start == 1 ? 2 : 1 // scrubbing (1) or replacement (2), the alarm file's own defines
	hc_ui(H, A, "mode", list("mode" = other))
	TEST_ASSERT_EQUAL(A.mode, start, "a locked alarm refuses a person's mode change")
	cap_key_set(A, LOCK_LOCKED, FALSE, null)
	hc_ui(H, A, "mode", list("mode" = other))
	TEST_ASSERT_EQUAL(A.mode, other, "unlocked, the mode changes")
	hc_ui(H, A, "temperature")
	var/datum/prompt/number/Q = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(Q, "the thermostat question is open")
	TEST_ASSERT_EQUAL("[Q?.min_value]-[Q?.max_value]", "0-40", "the thermostat question is bounded by the temperature thresholds")
	p2cl_answer(H, 25, TRUE)
	TEST_ASSERT_EQUAL(hc_data(A, H)["locked"], FALSE, "the window shows the lock")

/// Omni filter: the flow rate is asked only while configuring and off; the answer is clamped to the maximum.
/datum/unit_test/dq_fwg3_ui/omni_filter
/datum/unit_test/dq_fwg3_ui/omni_filter/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/atmospherics/omni/atmos_filter/F = allocate(/obj/machinery/atmospherics/omni/atmos_filter, T)
	var/start = F.set_flow_rate
	hc_ui(H, F, "set_flow_rate")
	p2cl_answer(H, 7)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(F.set_flow_rate, start, "not configuring: no question, nothing set")
	hc_ui(H, F, "configure")
	TEST_ASSERT(F.configuring, "configure turns configuring on")
	TEST_ASSERT(!F.use_power, "and the power off")
	hc_ui(H, F, "set_flow_rate")
	p2cl_answer(H, 7)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(F.set_flow_rate, 7, "configuring: the answered rate is set")
	hc_ui(H, F, "configure")
	TEST_ASSERT(!F.configuring, "configure again turns it off")

/// Trinary filter: the filter and rate buttons.
/datum/unit_test/dq_fwg3_ui/trinary_filter
/datum/unit_test/dq_fwg3_ui/trinary_filter/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/atmospherics/trinary/atmos_filter/F = allocate(/obj/machinery/atmospherics/trinary/atmos_filter, T)
	hc_ui(H, F, "filter", list("filterset" = 3))
	TEST_ASSERT_EQUAL(F.filter_type, 3, "the filter button sets the filtered gas")
	hc_ui(H, F, "rate", list("rate" = 50))
	TEST_ASSERT_EQUAL(F.set_flow_rate, 50, "the rate button sets the rate")
	var/was = F.use_power
	hc_ui(H, F, "power")
	TEST_ASSERT(F.use_power != was, "the power button toggles it")
	var/list/data = hc_data(F, H)
	TEST_ASSERT_EQUAL(data["rate"], 50, "the window shows the rate")

/// Gas pumps: "min" and "max" set the target at once; "set" asks for the value (the old act_ask re-run inside a switch: an asks() step with when =).
/datum/unit_test/dq_fwg3_ui/gas_pumps
/datum/unit_test/dq_fwg3_ui/gas_pumps/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/atmospherics/binary/pump/P = allocate(/obj/machinery/atmospherics/binary/pump, T)
	hc_ui(H, P, "set_press", list("press" = "max"))
	TEST_ASSERT_EQUAL(P.get_target_pressure(), P.max_pressure_setting, "max sets the most")
	hc_ui(H, P, "set_press", list("press" = "min"))
	TEST_ASSERT_EQUAL(P.get_target_pressure(), 0, "min sets none")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "and neither asks")
	hc_ui(H, P, "set_press", list("press" = "set"))
	p2cl_answer(H, 150)
	test_time(1)
	TEST_ASSERT_EQUAL(P.get_target_pressure(), 150, "set asks for the pressure")
	var/obj/machinery/atmospherics/binary/volume_pump/V = allocate(/obj/machinery/atmospherics/binary/volume_pump, T)
	hc_ui(H, V, "set_press", list("press" = "set"))
	p2cl_answer(H, 20)
	test_time(1)
	TEST_ASSERT_EQUAL(V.transfer_rate, 20, "a volume pump asks for the rate")

/// Shield generator: the range and input-cap questions are asked while the modes are unlocked; the shutdown questions only while it runs.
/datum/unit_test/dq_fwg3_ui/shield_generator
/datum/unit_test/dq_fwg3_ui/shield_generator/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/power/shield_generator/S = allocate(/obj/machinery/power/shield_generator, T)
	S.mode_changes_locked = FALSE
	hc_ui(H, S, "set_range")
	p2cl_answer(H, 7)
	test_time(1)
	TEST_ASSERT_EQUAL(S.target_radius, 7, "the answered range is the target")
	hc_ui(H, S, "set_input_cap")
	p2cl_answer(H, 12)
	test_time(1)
	TEST_ASSERT_EQUAL(S.input_cap, 12000, "the answered cap, in kW")
	S.running = 0
	hc_ui(H, S, "begin_shutdown")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "an idle generator asks nothing")
	S.mode_changes_locked = TRUE
	hc_ui(H, S, "set_range")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "locked modes ask nothing")

/// ATM and artifact harvester: their windows' data, and buttons that need an account or a battery do nothing without one.
/datum/unit_test/dq_fwg3_ui/atm_and_harvester
/datum/unit_test/dq_fwg3_ui/atm_and_harvester/run_fwg3()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = person(T)
	var/obj/machinery/atm/M = allocate(/obj/machinery/atm, T)
	hc_ui(H, M, "change_security_level", list("new_security_level" = 0))
	TEST_ASSERT_NULL(SSrequests.open_for(H), "no account: no PIN question")
	TEST_ASSERT("locked_down" in hc_data(M, H), "the window data has the lockdown")
	var/obj/machinery/artifact_harvester/A = allocate(/obj/machinery/artifact_harvester, T)
	hc_ui(H, A, "drainbattery")
	TEST_ASSERT_NULL(SSrequests.open_for(H), "no battery: no drain question")
	TEST_ASSERT("info" in hc_data(A, H), "the harvester's window data")
