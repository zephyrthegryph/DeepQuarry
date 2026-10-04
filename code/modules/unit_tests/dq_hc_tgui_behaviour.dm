// Behaviour tests for the datum-hosted windows (tgui modules, panels, programs): they pin what each window button does, what a refused viewer
// gets, and the data a viewer is sent, so the same file passes before and after the windows move from DECLARE_UI / UI_ACT / act_ask to
// interface() / op(ui_act()) / asks().
//   - Input goes through hct_ui(): the engine's op if the host has one for the action, else today's tgui_act() with an interactive window
//     that stays alive until the test ends (a question the handler asks re-runs it against that window).
//   - A question is answered through p2cl_answer() (the engine's request first, else the collected legacy prompt).
//   - State is read through plain vars and the window data; nothing depends on message text or an op key.

/// The live, interactive window `actor` has on `host` (made when they have none, deleted when the test ends).
/proc/hct_window(datum/unit_test/dq_hc_tgui/T, mob/actor, datum/host)
	var/datum/tgui/ui = SStgui.get_open_ui(actor, host)
	if(ui)
		return ui
	ui = new(actor, host, "HcTest")
	ui.status = STATUS_INTERACTIVE
	ui.set_state(GLOB.tgui_always_state) // a test person has no client, which every real state needs for interactive use
	SStgui.on_open(ui)
	LAZYADD(T.hct_windows, ui)
	return ui

/// Presses a window button as `actor` (see the file header).
/proc/hct_ui(datum/unit_test/dq_hc_tgui/T, mob/actor, datum/host, action, list/args)
	var/datum/tgui/ui = hct_window(T, actor, host)
	var/datum/op_result/result = test_ui(actor, host, action, args)
	if(result)
		return result
	return host.tgui_act(action, args || list(), ui, ui.state())

/datum/unit_test/dq_hc_tgui
	abstract_type = /datum/unit_test/dq_hc_tgui
	var/list/hct_windows
	var/list/hct_made

/datum/unit_test/dq_hc_tgui/Run()
	test_driver_begin()
	test_rng(1)
	p2cl_capture_prompts()
	run_gate()
	for(var/datum/tgui/ui as anything in hct_windows)
		if(!QDELETED(ui))
			qdel(ui)
	hct_windows = null
	for(var/datum/D as anything in hct_made)
		if(!QDELETED(D))
			qdel(D)
	test_driver_end()

/datum/unit_test/dq_hc_tgui/proc/run_gate()
	return

/// A thing the test made, deleted when it ends.
/datum/unit_test/dq_hc_tgui/proc/hct_track(datum/D)
	LAZYADD(hct_made, D)
	return D

/// Where things stand.
/datum/unit_test/dq_hc_tgui/proc/hct_spot()
	return get_step(run_loc_floor_bottom_left, EAST)

/// The thing a module is hosted by: next to the person, so the window is in reach.
/datum/unit_test/dq_hc_tgui/proc/hct_host()
	return allocate(/obj/item/paper, hct_spot())

/// A conscious person who cannot be hurt by the passing time.
/datum/unit_test/dq_hc_tgui/proc/hct_actor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.enable_godmode()
	return H

/// The actor presses a button and time passes (a converted op may wait where the old code was instant).
/datum/unit_test/dq_hc_tgui/proc/press(mob/actor, datum/host, action, list/args)
	. = hct_ui(src, actor, host, action, args)
	test_time(10 SECONDS)

/// The window data a viewer is sent (the dynamic part).
/datum/unit_test/dq_hc_tgui/proc/data_of(datum/host, mob/viewer)
	return hc_data(host, viewer)

// ---- batch 1: monitors and consoles hosted by a module ----

/datum/unit_test/dq_hc_tgui/power_monitor_buttons
/datum/unit_test/dq_hc_tgui/power_monitor_buttons/run_gate()
	var/datum/tgui_module/power_monitor/M = hct_track(new /datum/tgui_module/power_monitor(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "setsensor", list("id" = "Main grid"))
	TEST_ASSERT_EQUAL(M.active_sensor, "Main grid", "a sensor is selected")
	var/list/data = data_of(M, H)
	TEST_ASSERT(islist(data["all_sensors"]), "the window lists the sensors")
	TEST_ASSERT_NULL(data["focus"], "no sensor of that name, nothing in focus")
	press(H, M, "clear")
	TEST_ASSERT_NULL(M.active_sensor, "clearing deselects")
	press(H, M, "refresh")
	TEST_ASSERT_NULL(M.active_sensor, "refreshing keeps nothing selected")

/datum/unit_test/dq_hc_tgui/crew_manifest_data
/datum/unit_test/dq_hc_tgui/crew_manifest_data/run_gate()
	var/datum/tgui_module/crew_manifest/M = hct_track(new /datum/tgui_module/crew_manifest(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/list/data = data_of(M, H)
	TEST_ASSERT(("manifest" in data), "the manifest is sent")
	var/datum/tgui_module/crew_manifest/robot/R = hct_track(new /datum/tgui_module/crew_manifest/robot(hct_host()))
	TEST_ASSERT_EQUAL(R.tgui_state(H), GLOB.tgui_self_state, "a cyborg's manifest works through its self state")
	TEST_ASSERT_EQUAL(M.tgui_state(H), GLOB.tgui_default_state, "the plain one through the default state")

/datum/unit_test/dq_hc_tgui/crew_manifest_self_deleting
/datum/unit_test/dq_hc_tgui/crew_manifest_self_deleting/run_gate()
	var/datum/tgui_module/crew_manifest/self_deleting/M = new(hct_host())
	var/mob/living/carbon/human/H = hct_actor()
	M.tgui_close(H)
	TEST_ASSERT(QDELETED(M), "the module deletes itself when its window closes")

/datum/unit_test/dq_hc_tgui/trait_tutorial_select
/datum/unit_test/dq_hc_tgui/trait_tutorial_select/run_gate()
	var/datum/tgui_module/trait_tutorial_tgui/M = hct_track(new /datum/tgui_module/trait_tutorial_tgui(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	M.set_vars(list("a", "b"), list("c1", "c2"), list("d1", "d2"), list("t1", "t2"))
	press(H, M, "select_trait", list("name" = "b"))
	TEST_ASSERT_EQUAL(M.trait_selected, "b", "the trait is selected")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(data["selection"], "b", "the selection is sent")
	TEST_ASSERT_EQUAL(length(data["names"]), 2, "the names are sent")
	TEST_ASSERT_EQUAL(length(data["tutorials"]), 2, "the tutorials are sent")

/datum/unit_test/dq_hc_tgui/shutoff_monitor_toggle
/datum/unit_test/dq_hc_tgui/shutoff_monitor_toggle/run_gate()
	var/datum/tgui_module/shutoff_monitor/M = hct_track(new /datum/tgui_module/shutoff_monitor(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/atmospherics/valve/shutoff/V = allocate(/obj/machinery/atmospherics/valve/shutoff, hct_spot())
	var/leaks = V.close_on_leaks
	press(H, M, "toggle_enable", list("valve" = "\ref[V]"))
	TEST_ASSERT_NOTEQUAL(V.close_on_leaks, leaks, "the leak shutoff is toggled")
	press(H, M, "toggle_enable", list("valve" = "\ref[H]"))
	TEST_ASSERT_NOTEQUAL(V.close_on_leaks, leaks, "a ref that is not a shutoff valve changes nothing")
	var/list/data = data_of(M, H)
	var/found = FALSE
	for(var/list/row in data["valves"])
		if(row["ref"] == "\ref[V]")
			found = TRUE
	TEST_ASSERT(found, "the valve is listed")

/datum/unit_test/dq_hc_tgui/rustfuel_control_buttons
/datum/unit_test/dq_hc_tgui/rustfuel_control_buttons/run_gate()
	var/datum/tgui_module/rustfuel_control/M = hct_track(new /datum/tgui_module/rustfuel_control(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/fusion_fuel_injector/FI = allocate(/obj/machinery/fusion_fuel_injector, hct_spot())
	FI.id_tag = "fuel_a"
	press(H, M, "set_tag", null)
	TEST_ASSERT(p2cl_has_question(H), "the tag is asked for")
	p2cl_answer(H, "fuel_a")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.fuel_tag, "fuel_a", "the tag is set")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(length(data["fuels"]), 1, "the injector with that tag is listed")
	press(H, M, "toggle_active", list("fuel" = "\ref[H]"))
	TEST_ASSERT_EQUAL(M.fuel_tag, "fuel_a", "a ref that is not an injector does nothing")

/datum/unit_test/dq_hc_tgui/rustcore_monitor_buttons
/datum/unit_test/dq_hc_tgui/rustcore_monitor_buttons/run_gate()
	var/datum/tgui_module/rustcore_monitor/M = hct_track(new /datum/tgui_module/rustcore_monitor(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/power/fusion_core/C = allocate(/obj/machinery/power/fusion_core, hct_spot())
	C.id_tag = "core_a"
	press(H, M, "set_tag", null)
	TEST_ASSERT(p2cl_has_question(H), "the tag is asked for")
	p2cl_answer(H, "core_a")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.core_tag, "core_a", "the tag is set")
	var/dump = C.reactant_dump
	press(H, M, "toggle_reactantdump", list("core" = "\ref[C]"))
	TEST_ASSERT_NOTEQUAL(C.reactant_dump, dump, "the reactant dump is toggled")
	press(H, M, "set_fieldstr", list("core" = "\ref[C]", "fieldstr" = 40))
	TEST_ASSERT_EQUAL(C.target_field_strength, 40, "the field strength is set")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(length(data["cores"]), 1, "the core with that tag is listed")

/datum/unit_test/dq_hc_tgui/gyrotron_control_buttons
/datum/unit_test/dq_hc_tgui/gyrotron_control_buttons/run_gate()
	var/datum/tgui_module/gyrotron_control/M = hct_track(new /datum/tgui_module/gyrotron_control(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/power/emitter/gyrotron/G = allocate(/obj/machinery/power/emitter/gyrotron, hct_spot())
	G.id_tag = "gyro_a"
	press(H, M, "set_tag", null)
	TEST_ASSERT(p2cl_has_question(H), "the tag is asked for")
	p2cl_answer(H, "gyro_a")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.gyro_tag, "gyro_a", "the tag is set")
	press(H, M, "set_str", list("gyro" = "\ref[G]", "str" = 3))
	TEST_ASSERT_EQUAL(G.mega_energy, 3, "the beam strength is set")
	press(H, M, "set_rate", list("gyro" = "\ref[G]", "rate" = 12))
	TEST_ASSERT_EQUAL(G.rate, 12, "the fire rate is set")
	press(H, M, "set_str", list("gyro" = "\ref[G]", "str" = 0))
	TEST_ASSERT_EQUAL(G.mega_energy, 3, "a zero strength changes nothing")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(length(data["gyros"]), 1, "the gyrotron with that tag is listed")

/datum/unit_test/dq_hc_tgui/supermatter_monitor_buttons
/datum/unit_test/dq_hc_tgui/supermatter_monitor_buttons/run_gate()
	var/datum/tgui_module/supermatter_monitor/M = hct_track(new /datum/tgui_module/supermatter_monitor(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "refresh")
	press(H, M, "set", list("set" = 12345))
	TEST_ASSERT_NULL(M.active(), "an id that is no crystal selects nothing")
	press(H, M, "clear")
	TEST_ASSERT_NULL(M.active(), "clearing keeps nothing selected")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(data["active"], 0, "with no crystal selected the window lists the crystals")

/datum/unit_test/dq_hc_tgui/rcon_buttons
/datum/unit_test/dq_hc_tgui/rcon_buttons/run_gate()
	var/datum/tgui_module/rcon/M = hct_track(new /datum/tgui_module/rcon(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "set_smes_page", list("index" = 2))
	TEST_ASSERT_EQUAL(M.current_page, 2, "the page is set")
	var/list/data = data_of(M, H)
	TEST_ASSERT(islist(data["smes_info"]), "the SMES list is sent")
	TEST_ASSERT(islist(data["breaker_info"]), "the breaker list is sent")
	press(H, M, "smes_in_toggle", list("smes" = "NOPE"))
	press(H, M, "toggle_breaker", list("breaker" = "NOPE"))
	TEST_ASSERT_EQUAL(M.current_page, 2, "unknown tags change nothing")

/datum/unit_test/dq_hc_tgui/alarm_monitor_switch
/datum/unit_test/dq_hc_tgui/alarm_monitor_switch/run_gate()
	var/datum/tgui_module/alarm_monitor/all/M = hct_track(new /datum/tgui_module/alarm_monitor/all(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, hct_spot())
	press(H, M, "switchTo", list("camera" = "\ref[C]"))
	TEST_ASSERT(H.client?.eye != C, "only an AI switches to a camera")
	var/list/data = data_of(M, H)
	TEST_ASSERT(islist(data["categories"]), "the alarm categories are sent")

/datum/unit_test/dq_hc_tgui/atmos_control_no_window
/datum/unit_test/dq_hc_tgui/atmos_control_no_window/run_gate()
	var/datum/tgui_module/atmos_control/M = hct_track(new /datum/tgui_module/atmos_control(hct_host(), null, null, null))
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/machinery/alarm/A = allocate(/obj/machinery/alarm, hct_spot())
	press(H, M, "alarm", list("alarm" = "\ref[A]"))
	TEST_ASSERT_NULL(M.ui_ref, "opening an alarm needs the console's own window")
	var/list/data = data_of(M, H)
	TEST_ASSERT(islist(data["map_levels"]), "the visible levels are sent")

/datum/unit_test/dq_hc_tgui/crew_monitor_data
/datum/unit_test/dq_hc_tgui/crew_monitor_data/run_gate()
	var/datum/tgui_module/crew_monitor/M = hct_track(new /datum/tgui_module/crew_monitor(hct_host()))
	var/mob/living/carbon/human/H = hct_actor()
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(data["isAI"], FALSE, "a person is not an AI")
	TEST_ASSERT(islist(data["crewmembers"]), "the crew is sent")
	press(H, M, "track", list("track" = "\ref[H]"))
	TEST_ASSERT_EQUAL(data["isAI"], FALSE, "only an AI tracks")

// ---- batch 2: agent card, law manager, camera, admin windows ----

/datum/unit_test/dq_hc_tgui/agentcard_buttons
/datum/unit_test/dq_hc_tgui/agentcard_buttons/run_gate()
	var/obj/item/card/id/syndicate/S = allocate(/obj/item/card/id/syndicate, hct_spot())
	var/datum/tgui_module/agentcard/M = hct_track(new /datum/tgui_module/agentcard(S))
	var/mob/living/carbon/human/H = hct_actor()
	S.register_user(H)
	var/warfare = S.electronic_warfare
	press(H, M, "electronic_warfare")
	TEST_ASSERT_NOTEQUAL(S.electronic_warfare, warfare, "electronic warfare is toggled")
	press(H, M, "age")
	TEST_ASSERT(p2cl_has_question(H), "an age is asked for")
	p2cl_answer(H, 41)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.age, 41, "the age is set")
	press(H, M, "assignment")
	p2cl_answer(H, "Janitor")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.assignment, "Janitor", "the assignment is set")
	press(H, M, "sex")
	p2cl_answer(H, "Other")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.sex, "Other", "the sex is set")
	press(H, M, "species")
	p2cl_answer(H, "Slime")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.species, "Slime", "the species is set")
	press(H, M, "age")
	p2cl_answer(H, 0, TRUE)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.age, 41, "a cancelled question changes nothing")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(length(data["entries"]), 11, "the entries are sent")

/datum/unit_test/dq_hc_tgui/agentcard_factory_reset
/datum/unit_test/dq_hc_tgui/agentcard_factory_reset/run_gate()
	var/obj/item/card/id/syndicate/S = allocate(/obj/item/card/id/syndicate, hct_spot())
	var/datum/tgui_module/agentcard/M = hct_track(new /datum/tgui_module/agentcard(S))
	var/mob/living/carbon/human/H = hct_actor()
	S.register_user(H)
	S.age = 99
	S.assignment = "Captain"
	press(H, M, "factoryreset")
	TEST_ASSERT(p2cl_has_question(H), "the reset is confirmed first")
	p2cl_answer(H, FALSE)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.age, 99, "a no changes nothing")
	press(H, M, "factoryreset")
	p2cl_answer(H, "Yes")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(S.age, initial(S.age), "a yes resets the age")
	TEST_ASSERT_EQUAL(S.assignment, initial(S.assignment), "and the assignment")

/datum/unit_test/dq_hc_tgui/law_manager_buttons
/datum/unit_test/dq_hc_tgui/law_manager_buttons/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/tgui_module/law_manager/M = hct_law_manager(R)
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "change_ion_law", list("val" = "Do the dance"))
	TEST_ASSERT_EQUAL(M.ion_law, "Do the dance", "the drafted ion law is set")
	press(H, M, "change_inherent_law", list("val" = "Be kind"))
	TEST_ASSERT_EQUAL(M.inherent_law, "Be kind", "the drafted inherent law is set")
	var/ions = length(R.laws.ion_laws)
	press(H, M, "add_ion_law")
	TEST_ASSERT_EQUAL(length(R.laws.ion_laws), ions, "a person who is not an antagonist adds no law")
	press(H, M, "change_supplied_law_position")
	TEST_ASSERT(p2cl_has_question(H), "a position is asked for")
	p2cl_answer(H, 3)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.supplied_law_position, 3, "the position is set")
	press(H, M, "change_supplied_law_position")
	p2cl_answer(H, 999)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.supplied_law_position, MAX_SUPPLIED_LAW_NUMBER, "a position past the end is clamped")
	var/list/data = data_of(M, H)
	TEST_ASSERT_EQUAL(data["isMalf"], FALSE, "the viewer is not an antagonist")
	TEST_ASSERT(islist(data["law_sets"]), "the law sets are sent")

/// A law manager of a silicon that stands on a thing next to the person (a robot is no place for a window to be reached through).
/datum/unit_test/dq_hc_tgui/proc/hct_law_manager(mob/living/silicon/S, type = /datum/tgui_module/law_manager)
	var/datum/tgui_module/law_manager/M = hct_track(new type(S))
	rel_set(M, nameof(/datum/tgui_module::host), hct_host())
	return M

/datum/unit_test/dq_hc_tgui/law_manager_refusals
/datum/unit_test/dq_hc_tgui/law_manager_refusals/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/tgui_module/law_manager/M = hct_law_manager(R)
	var/mob/living/carbon/human/H = hct_actor()
	R.laws.add_ion_law("Seed law")
	var/ions = length(R.laws.ion_laws)
	var/datum/ai_law/L = R.laws.ion_laws[ions]
	press(H, M, "delete_law", list("delete_law" = "ef[L]"))
	TEST_ASSERT_EQUAL(length(R.laws.ion_laws), ions, "a person who is not an antagonist deletes no law")
	press(H, M, "edit_law", list("edit_law" = "ef[L]"))
	TEST_ASSERT(!p2cl_has_question(H), "and is not asked for a new text")
	press(H, M, "state_law", list("ref" = "ef[L]", "state_law" = 1))
	TEST_ASSERT(R.laws.get_state_law(L), "a law's stated flag is switched by anybody at the window")

/datum/unit_test/dq_hc_tgui/camera_switch
/datum/unit_test/dq_hc_tgui/camera_switch/run_gate()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, hct_spot())
	C.network = list("hct_net")
	C.c_tag = "hct cam"
	var/datum/tgui_module/camera/M = hct_track(new /datum/tgui_module/camera(hct_host(), list("hct_net")))
	var/mob/living/carbon/human/H = hct_actor()
	TEST_ASSERT_NULL(M.active_camera(), "no camera is active at first")
	press(H, M, "switch_camera", list("name" = "hct cam"))
	TEST_ASSERT_EQUAL(M.active_camera(), C, "the camera is selected by its tag")
	press(H, M, "switch_camera", list("name" = "no such camera"))
	var/list/data = data_of(M, H)
	TEST_ASSERT(islist(data["activeCamera"]) || isnull(data["activeCamera"]), "the active camera is sent")

/datum/unit_test/dq_hc_tgui/admin_windows_need_rights
/datum/unit_test/dq_hc_tgui/admin_windows_need_rights/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/tgui_module/admin_shuttle_controller/A = hct_track(new /datum/tgui_module/admin_shuttle_controller(hct_host()))
	var/datum/tgui_state/S = interface_state(A) || A.tgui_state(H)
	TEST_ASSERT(S != GLOB.tgui_default_state, "the shuttle controller has an admin state")
	TEST_ASSERT(A.tgui_status(H, S) < STATUS_INTERACTIVE, "a player cannot work the shuttle controller")
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/tgui_module/law_manager/admin/L = hct_law_manager(R, /datum/tgui_module/law_manager/admin)
	var/datum/tgui_state/LS = interface_state(L) || L.tgui_state(H)
	TEST_ASSERT(LS != GLOB.tgui_default_state, "the admin law manager has an admin state")
	TEST_ASSERT(L.tgui_status(H, LS) < STATUS_INTERACTIVE, "a player cannot work the admin law manager")
