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
	/// Cards a test tied to a pAI.
	var/list/hct_cards
	/// The map's contact levels before a test widened them (a list holding the old list).
	var/list/hct_saved_levels

/datum/unit_test/dq_hc_tgui/Run()
	test_driver_begin()
	test_rng(1)
	p2cl_capture_prompts()
	run_gate()
	for(var/datum/tgui/ui as anything in hct_windows)
		if(!QDELETED(ui))
			qdel(ui)
	hct_windows = null
	for(var/obj/item/paicard/card as anything in hct_cards)
		card.removePersonality() // the card lets go of its pAI before the block is swept, so no spark outlives the test
	for(var/turf/N in range(3, run_loc_floor_bottom_left))
		own_turf_contents(N)
	if(hct_saved_levels)
		using_map.contact_levels = hct_saved_levels[1]
		hct_saved_levels = null
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
	FI.set_id_tag("fuel_a") // the setter refiles it in its registry under the tag
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
	C.set_id_tag("core_a") // the setter refiles it in its registry under the tag
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
	G.set_id_tag("gyro_a") // the setter refiles it in its registry under the tag
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

// ---- batch 3: communications console (COMM_* are local to communications.dm: authentication 0 none, 2 captain; screens 1 main, 2 status) ----

/// A communications console whose user may log in as the captain, on a level the station's contact range covers.
/datum/unit_test/dq_hc_tgui/proc/hct_comms()
	if(!hct_saved_levels)
		hct_saved_levels = list(using_map.contact_levels)
		using_map.contact_levels = using_map.contact_levels.Copy() + run_loc_floor_bottom_left.z
	var/datum/tgui_module/communications/M = hct_track(new /datum/tgui_module/communications(hct_host()))
	M.using_access = list(ACCESS_HEADS, ACCESS_CAPTAIN)
	return M

/datum/unit_test/dq_hc_tgui/comms_needs_login
/datum/unit_test/dq_hc_tgui/comms_needs_login/run_gate()
	var/datum/tgui_module/communications/M = hct_comms()
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "status")
	TEST_ASSERT_NOTEQUAL(M.menu_state, 2, "nothing works before logging in")
	M.set_login(H, 2)
	press(H, M, "status")
	TEST_ASSERT_EQUAL(M.menu_state, 2, "the status screen opens once logged in")
	press(H, M, "main")
	TEST_ASSERT_EQUAL(M.menu_state, 1, "the main screen opens")

/datum/unit_test/dq_hc_tgui/comms_status_messages
/datum/unit_test/dq_hc_tgui/comms_status_messages/run_gate()
	var/datum/tgui_module/communications/M = hct_comms()
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "setmsg1")
	TEST_ASSERT_NULL(M.stat_msg1, "a line is not asked for before logging in")
	M.set_login(H, 2)
	press(H, M, "setmsg1")
	TEST_ASSERT(p2cl_has_question(H), "line 1 is asked for")
	p2cl_answer(H, "Hello station")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.stat_msg1, "Hello station", "line 1 is set")
	TEST_ASSERT_EQUAL(M.menu_state, 2, "and the status screen shows")
	press(H, M, "setmsg2")
	p2cl_answer(H, "Second line")
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.stat_msg2, "Second line", "line 2 is set")
	press(H, M, "setmsg1")
	p2cl_answer(H, "", TRUE)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(M.stat_msg1, "Hello station", "a cancelled question changes nothing")

/datum/unit_test/dq_hc_tgui/comms_shuttle_question
/datum/unit_test/dq_hc_tgui/comms_shuttle_question/run_gate()
	var/datum/tgui_module/communications/M = hct_comms()
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "callshuttle")
	TEST_ASSERT(!p2cl_has_question(H), "the shuttle is not offered before logging in")
	M.set_login(H, 2)
	press(H, M, "callshuttle")
	TEST_ASSERT(p2cl_has_question(H), "calling the shuttle is confirmed first")
	p2cl_answer(H, FALSE)
	test_time(10 SECONDS)
	TEST_ASSERT(!SSemergency_shuttle.online(), "a no calls nothing")
	press(H, M, "announce")
	TEST_ASSERT(p2cl_has_question(H), "an announcement is asked for")
	p2cl_answer(H, "x", TRUE)
	test_time(10 SECONDS)
	TEST_ASSERT(COOLDOWN_FINISHED(M, message_cooldown), "a cancelled announcement costs no cooldown")

/// New with the conversion: the legacy window's "auth" button had no handler (see intended_changes.md), so this passes only on the op.
/datum/unit_test/dq_hc_tgui/comms_login_button
/datum/unit_test/dq_hc_tgui/comms_login_button/run_gate()
	var/datum/tgui_module/communications/M = hct_comms()
	var/mob/living/carbon/human/H = hct_actor()
	press(H, M, "auth")
	TEST_ASSERT_EQUAL(M.is_authenticated(H, FALSE), 2, "a person with captain access logs in as captain")
	press(H, M, "auth")
	TEST_ASSERT_EQUAL(M.is_authenticated(H, FALSE), 0, "pressing it again logs out")
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	press(R, M, "auth")
	TEST_ASSERT_EQUAL(M.is_authenticated(R, FALSE), 0, "a cyborg cannot log in")
	press(H, M, "auth")
	var/mob/living/carbon/human/other = hct_actor()
	TEST_ASSERT_EQUAL(M.is_authenticated(H, FALSE), 2, "logged in again")
	TEST_ASSERT_EQUAL(M.is_authenticated(other, FALSE), 0, "a login is the person's own: someone else at the console is not logged in by it")
	press(other, M, "status")
	TEST_ASSERT_NOTEQUAL(M.menu_state, 2, "and their buttons do nothing")

/// Deleting a message deletes the one whose button was pressed, even when another is opened while the question is up; the station's own list
/// (a console's) cannot be deleted from.
/datum/unit_test/dq_hc_tgui/comms_delete_the_message_pressed
/datum/unit_test/dq_hc_tgui/comms_delete_the_message_pressed/run_gate()
	if(!hct_saved_levels)
		hct_saved_levels = list(using_map.contact_levels)
		using_map.contact_levels = using_map.contact_levels.Copy() + run_loc_floor_bottom_left.z
	var/obj/item/modular_computer/laptop/L = allocate(/obj/item/modular_computer/laptop, hct_spot())
	var/datum/computer_file/program/comm/P = hct_track(new /datum/computer_file/program/comm(L))
	var/datum/tgui_module/communications/M = hct_track(new /datum/tgui_module/communications(P))
	var/mob/living/carbon/human/H = hct_actor()
	P.message_core.messages = list()
	P.message_core.Add(list("id" = 9001, "title" = "One", "contents" = "first"))
	P.message_core.Add(list("id" = 9002, "title" = "Two", "contents" = "second"))
	M.set_login(H, 2)
	press(H, M, "delmessage", list("msgid" = 9001))
	TEST_ASSERT(p2cl_has_question(H), "deleting is confirmed first")
	var/mob/living/carbon/human/other = hct_actor()
	M.set_login(other, 2)
	press(other, M, "messagelist", list("msgid" = 9002))
	p2cl_answer(H, TRUE)
	test_time(10 SECONDS)
	TEST_ASSERT(!M.message_by_id(9001), "the message pressed is deleted")
	TEST_ASSERT(M.message_by_id(9002), "not the one opened while the question was up")
	var/datum/tgui_module/communications/G = hct_comms()
	G.set_login(H, 2)
	var/before = length(GLOB.global_message_listener.messages)
	press(H, G, "delmessage", list("msgid" = 1))
	TEST_ASSERT(!p2cl_has_question(H), "a console's station list is not offered for deletion")
	TEST_ASSERT_EQUAL(length(GLOB.global_message_listener.messages), before, "and keeps its messages")

/// The command console's emag scrambles the routing (the Syndicate line opens); restoring the backup routing from the window undoes it.
/datum/unit_test/dq_hc_tgui/comms_emag_and_restore
/datum/unit_test/dq_hc_tgui/comms_emag_and_restore/run_gate()
	if(!hct_saved_levels)
		hct_saved_levels = list(using_map.contact_levels)
		using_map.contact_levels = using_map.contact_levels.Copy() + run_loc_floor_bottom_left.z
	var/obj/machinery/computer/communications/C = allocate(/obj/machinery/computer/communications, hct_spot())
	var/datum/tgui_module/communications/M = C.communications
	var/mob/living/carbon/human/H = hct_actor()
	TEST_ASSERT(!M.routing_scrambled(), "(the routing starts whole)")
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, hct_spot())
	E.uses = 3
	H.put_in_active_hand(E)
	hci_click(H, C, E)
	test_time(1 SECOND)
	TEST_ASSERT(M.routing_scrambled(), "the emag scrambles the routing")
	M.set_login(H, 2)
	press(H, M, "RestoreBackup")
	TEST_ASSERT(!M.routing_scrambled(), "restoring the backup routing undoes it")
	TEST_ASSERT(E.uses == 2, "the emag spent one charge")

// ---- batch 4: admin panels (the windows keep their rights: an admin state, per-action rights where the panel had them) ----

/// The window state `D` opens with: its interface's, else its tgui_state().
/datum/unit_test/dq_hc_tgui/proc/hct_state_of(datum/D, mob/user)
	return interface_state(D) || D.tgui_state(user)

/datum/unit_test/dq_hc_tgui/admin_panels_need_rights
/datum/unit_test/dq_hc_tgui/admin_panels_need_rights/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/mob/living/carbon/human/T = allocate(/mob/living/carbon/human, hct_spot())
	var/datum/eventkit/player_effects/E = hct_track(new /datum/eventkit/player_effects)
	rel_set(E, nameof(/datum/accessory_stat_modifier::target), T)
	var/datum/edit_player_panel/EP = hct_track(new /datum/edit_player_panel(null, T))
	var/datum/newscaster_panel/NP = hct_track(new /datum/newscaster_panel(null))
	for(var/datum/D in list(E, EP, NP))
		var/datum/tgui_state/S = hct_state_of(D, H)
		TEST_ASSERT(S != GLOB.tgui_default_state, "[D.type] has an admin state")
		TEST_ASSERT(D.tgui_status(H, S) < STATUS_INTERACTIVE, "a player cannot work [D.type]")

/datum/unit_test/dq_hc_tgui/player_effects_refuse_a_player
/datum/unit_test/dq_hc_tgui/player_effects_refuse_a_player/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/mob/living/carbon/human/T = allocate(/mob/living/carbon/human, hct_spot())
	var/datum/eventkit/player_effects/E = hct_track(new /datum/eventkit/player_effects)
	rel_set(E, nameof(/datum/accessory_stat_modifier::target), T)
	for(var/action in list("break_legs", "paralyse", "drop_all", "dust", "gib", "spin", "stasis"))
		press(H, E, action)
	var/obj/item/organ/external/leg = T.get_organ(BP_L_LEG)
	TEST_ASSERT(!leg.is_broken(), "the target's leg is not broken by somebody without rights")
	TEST_ASSERT(!QDELETED(T), "the target is still there")
	TEST_ASSERT(!p2cl_has_question(H), "no question is asked of a player")
	TEST_ASSERT_EQUAL(E.target(), T, "the target is unchanged")
	var/list/data = E.tgui_static_data(H)
	TEST_ASSERT_EQUAL(data["real_name"], T.name, "the static data names the target")

/datum/unit_test/dq_hc_tgui/modify_robot_buttons
/datum/unit_test/dq_hc_tgui/modify_robot_buttons/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/eventkit/modify_robot/M = hct_track(new /datum/eventkit/modify_robot)
	rel_set(M, nameof(/datum/accessory_stat_modifier::target), R)
	var/crisis = R.crisis_override
	press(H, M, "toggle_crisis")
	TEST_ASSERT_NOTEQUAL(R.crisis_override, crisis, "the crisis override is toggled")
	press(H, M, "rename", list("new_name" = "Bolt"))
	TEST_ASSERT_EQUAL(R.real_name, "Bolt", "the robot is renamed")
	TEST_ASSERT_EQUAL(R.custom_name, "Bolt", "and its custom name is set")
	var/mob/living/silicon/robot/R2 = allocate(/mob/living/silicon/robot, hct_spot())
	press(H, M, "select_target", list("new_target" = "\ref[R2]"))
	TEST_ASSERT_EQUAL(M.target(), R2, "another robot is selected")
	press(H, M, "add_restriction", list("new_restriction" = "no such module"))
	TEST_ASSERT(!length(R2.restrict_modules_to), "an unknown module is not added to the restrictions")

// ---- batch 5: pAI, robot windows ----

/// A pAI standing next to the person, with a card.
/datum/unit_test/dq_hc_tgui/proc/hct_pai()
	var/obj/item/paicard/card = allocate(/obj/item/paicard, hct_spot())
	var/mob/living/silicon/pai/P = allocate(/mob/living/silicon/pai, card)
	if(!card.pai)
		rel_set(card, nameof(card.pai), P)
	LAZYADD(hct_cards, card)
	P.forceMove(get_step(hct_spot(), NORTH))
	return P

/datum/unit_test/dq_hc_tgui/pai_software_window
/datum/unit_test/dq_hc_tgui/pai_software_window/run_gate()
	var/mob/living/silicon/pai/P = hct_pai()
	var/datum/pai_software/S
	for(var/key in GLOB.pai_software_by_key)
		var/datum/pai_software/candidate = GLOB.pai_software_by_key[key]
		if(!(key in P.software) && candidate.ram_cost > 0 && candidate.ram_cost <= P.ram)
			S = candidate
			break
	TEST_ASSERT(S, "there is a program the pAI can buy")
	var/ram = P.ram
	press(P, P, "purchase", list("purchase" = S.id))
	TEST_ASSERT(P.software[S.id], "the program is bought")
	TEST_ASSERT_EQUAL(P.ram, ram - S.ram_cost, "and its RAM is spent")
	press(P, P, "purchase", list("purchase" = "no such program"))
	TEST_ASSERT_EQUAL(P.ram, ram - S.ram_cost, "an unknown program costs nothing")
	var/list/data = data_of(P, P)
	TEST_ASSERT(islist(data["bought"]), "the bought programs are sent")
	TEST_ASSERT(islist(data["not_bought"]), "and the others")
	var/emotion = P.card.current_emotion
	press(P, P, "image", list("image" = 3))
	TEST_ASSERT_EQUAL(P.card.current_emotion, 3, "the face is picked")
	TEST_ASSERT_NOTEQUAL(emotion, 3, "and it changed")

/datum/unit_test/dq_hc_tgui/pai_signaller_window
/datum/unit_test/dq_hc_tgui/pai_signaller_window/run_gate()
	var/mob/living/silicon/pai/P = hct_pai()
	var/datum/pai_software/signaller/S = GLOB.pai_software_by_key["signaller"]
	TEST_ASSERT(S, "the signaller program exists")
	var/mob/living/carbon/human/H = hct_actor()
	var/obj/item/radio/integrated/signal/R = P.sradio
	press(P, S, "code", list("code" = 42))
	TEST_ASSERT_EQUAL(R.code, 42, "the signal code is set")
	press(P, S, "reset", list("reset" = "code"))
	TEST_ASSERT_EQUAL(R.code, initial(R.code), "and reset")
	press(H, S, "code", list("code" = 77))
	TEST_ASSERT_NOTEQUAL(R.code, 77, "only a pAI works the program")
	var/list/data = data_of(S, P)
	TEST_ASSERT_EQUAL(data["code"], R.code, "the code is sent")

/datum/unit_test/dq_hc_tgui/pai_chassis_window
/datum/unit_test/dq_hc_tgui/pai_chassis_window/run_gate()
	var/mob/living/silicon/pai/P = hct_pai()
	var/datum/tgui_module/pai_chassis/M = hct_track(new /datum/tgui_module/pai_chassis(P))
	press(P, M, "change_color", list("color" = "#12ab34"))
	TEST_ASSERT_EQUAL(M.selected_color, "#12ab34", "the colour is picked")
	var/list/chassises = SSpai.get_chassis_list()
	var/choice = chassises[1]
	press(P, M, "pick_icon", list("value" = choice))
	TEST_ASSERT_EQUAL(M.selected_chassis, choice, "a chassis is picked")
	press(P, M, "pick_icon", list("value" = "no such chassis"))
	TEST_ASSERT_EQUAL(M.selected_chassis, choice, "an unknown chassis changes nothing")
	press(P, M, "confirm")
	TEST_ASSERT_EQUAL(P.eye_color, "#12ab34", "confirming applies the colour")

/datum/unit_test/dq_hc_tgui/robot_window_buttons
/datum/unit_test/dq_hc_tgui/robot_window_buttons/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/tgui_module/robot_ui/M = hct_track(new /datum/tgui_module/robot_ui(R))
	press(R, M, "set_light_col", list("value" = "#00ff00"))
	TEST_ASSERT_EQUAL(R.robot_light_col, "#00ff00", "the lamp colour is set")
	press(R, M, "set_light_col", list("value" = "green"))
	TEST_ASSERT_EQUAL(R.robot_light_col, "#00ff00", "a bad colour changes nothing")
	press(R, M, "toggle_module", list("ref" = "\ref[R]"))
	press(R, M, "activate_module", list("ref" = "\ref[R]"))
	var/list/data = data_of(M, R)
	TEST_ASSERT(islist(data), "the window data is sent")

/datum/unit_test/dq_hc_tgui/robot_module_picker
/datum/unit_test/dq_hc_tgui/robot_module_picker/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, hct_spot())
	var/datum/tgui_module/robot_ui_module/M = hct_track(new /datum/tgui_module/robot_ui_module(R))
	press(R, M, "rename", list("value" = "Sprocket"))
	TEST_ASSERT_EQUAL(M.new_name, "Sprocket", "the name is picked")
	TEST_ASSERT_EQUAL(R.sprite_name, "Sprocket", "and kept on the robot")
	press(R, M, "pick_module", list("value" = "no such module"))
	TEST_ASSERT_NULL(M.selected_module, "an unknown module is not picked")
	press(R, M, "confirm")
	TEST_ASSERT(!R.module, "confirming with nothing picked changes nothing")
	var/datum/tgui_module/robot_ui_decals/D = hct_track(new /datum/tgui_module/robot_ui_decals(R))
	press(R, D, "toggle_decal", list("value" = "stripe"))
	TEST_ASSERT(!LAZYLEN(R.robotdecal_on), "a robot with no sprite has no decals to switch")

// ---- batch 6: programs of a modular computer (code/modules/modular_computers/file_system) ----

/// A laptop with a real processor and drive, nothing else.
/obj/item/modular_computer/hct_laptop
	hardware_flag = PROGRAM_LAPTOP

/obj/item/modular_computer/hct_laptop/install_default_hardware()
	. = ..()
	install_hardware(new /obj/item/computer_hardware/processor_unit/small(src))
	install_hardware(new /obj/item/computer_hardware/hard_drive(src))

/// A program of `type` run on a fresh laptop next to the person.
/datum/unit_test/dq_hc_tgui/proc/hct_program(type)
	var/obj/item/modular_computer/hct_laptop/L = allocate(/obj/item/modular_computer/hct_laptop, hct_spot())
	var/datum/computer_file/program/P = hct_track(new type(L))
	return P

/// A text file stored on the program's computer.
/datum/unit_test/dq_hc_tgui/proc/hct_file(datum/computer_file/program/P, name, data = "")
	var/datum/computer_file/data/F = new /datum/computer_file/data()
	F.filename = name
	F.filetype = "TXT"
	F.stored_data = data
	F.calculate_size()
	TEST_ASSERT(P.computer().hard_drive.store_file(F), "the drive stores the file")
	return F

/datum/unit_test/dq_hc_tgui/word_processor_files
/datum/unit_test/dq_hc_tgui/word_processor_files/run_gate()
	var/datum/computer_file/program/wordprocessor/P = hct_program(/datum/computer_file/program/wordprocessor)
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/computer_file/data/doc = hct_file(P, "doc", "hello")
	press(H, P, "PRG_openfile", list("PRG_openfile" = "doc"))
	TEST_ASSERT_EQUAL(P.open_file, "doc", "the file is opened")
	TEST_ASSERT_EQUAL(P.loaded_data, "hello", "and its text loaded")
	P.loaded_data = "changed"
	press(H, P, "PRG_savefile")
	TEST_ASSERT_EQUAL(P.get_file("doc").stored_data, "changed", "saving writes the text back")
	press(H, P, "PRG_newfile", list("PRG_saveasfile" = "x"))
	TEST_ASSERT(p2cl_has_question(H), "a name is asked for")
	p2cl_answer(H, "memo")
	test_time(10 SECONDS)
	TEST_ASSERT(P.get_file("memo"), "the new file is made")
	TEST_ASSERT_EQUAL(P.open_file, "memo", "and opened")
	press(H, P, "PRG_openfile", list("PRG_openfile" = "no such file"))
	TEST_ASSERT(P.error, "opening a file that is not there is an error")
	press(H, P, "PRG_backtomenu")
	TEST_ASSERT_NULL(P.error, "the error is cleared")
	P.loaded_data = "unsaved"
	P.is_edited = TRUE
	press(H, P, "PRG_openfile", list("PRG_openfile" = "doc"))
	TEST_ASSERT(p2cl_has_question(H), "unsaved changes are asked about first")
	p2cl_answer(H, FALSE)
	test_time(10 SECONDS)
	TEST_ASSERT_EQUAL(P.get_file("memo").stored_data, "", "answering no does not save them")
	TEST_ASSERT_EQUAL(P.open_file, "doc", "and the other file opens")
	qdel(doc)

/datum/unit_test/dq_hc_tgui/file_manager_files
/datum/unit_test/dq_hc_tgui/file_manager_files/run_gate()
	var/datum/computer_file/program/filemanager/P = hct_program(/datum/computer_file/program/filemanager)
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/computer_file/data/F = hct_file(P, "notes", "text")
	press(H, P, "PRG_openfile", list("uid" = F.uid))
	TEST_ASSERT_EQUAL(P.open_file, F.uid, "the file is opened")
	var/count = length(P.computer().hard_drive.stored_files)
	press(H, P, "PRG_clone", list("uid" = F.uid))
	TEST_ASSERT_EQUAL(length(P.computer().hard_drive.stored_files), count + 1, "a copy is stored")
	press(H, P, "PRG_rename", list("uid" = F.uid, "new_name" = "renamed"))
	TEST_ASSERT_EQUAL(F.filename, "renamed", "the file is renamed")
	press(H, P, "PRG_newtextfile")
	TEST_ASSERT(p2cl_has_question(H), "a file name is asked for")
	p2cl_answer(H, "fresh")
	test_time(10 SECONDS)
	TEST_ASSERT(P.computer().hard_drive.find_file_by_name("fresh"), "the new file is stored")
	press(H, P, "PRG_closefile")
	TEST_ASSERT_NULL(P.open_file, "closing the file clears it")
	var/uid = F.uid
	press(H, P, "PRG_deletefile", list("uid" = uid))
	TEST_ASSERT_NULL(P.computer().find_file_by_uid(uid), "the file is deleted")

// ---- batch 7: appearance changer ----

/// An appearance changer working on a human, with everything it may change allowed.
/datum/unit_test/dq_hc_tgui/proc/hct_changer(mob/living/carbon/human/owner)
	var/datum/tgui_module/appearance_changer/M = hct_track(new /datum/tgui_module/appearance_changer(hct_host(), owner))
	M.flags = APPEARANCE_ALL
	M.generate_data(owner, owner)
	return M

/// A press on the changer after its half-second cooldown (it reads world.time, which the test clock does not advance).
/datum/unit_test/dq_hc_tgui/proc/cpress(datum/tgui_module/appearance_changer/M, mob/actor, action, list/args)
	M.cooldown = 0
	press(actor, M, action, args)

/// Answers the question the person was asked, after the cooldown.
/datum/unit_test/dq_hc_tgui/proc/canswer(datum/tgui_module/appearance_changer/M, mob/actor, value, cancel = FALSE)
	M.cooldown = 0
	p2cl_answer(actor, value, cancel)
	test_time(10 SECONDS)

/datum/unit_test/dq_hc_tgui/appearance_changer_styles
/datum/unit_test/dq_hc_tgui/appearance_changer_styles/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/tgui_module/appearance_changer/M = hct_changer(H)
	var/style = M.valid_hairstyles[length(M.valid_hairstyles)]
	cpress(M, H, "hair", list("name" = style))
	TEST_ASSERT_EQUAL(H.h_style, style, "the hairstyle is changed")
	cpress(M, H, "hair", list("name" = "no such style"))
	TEST_ASSERT_EQUAL(H.h_style, style, "an unknown style changes nothing")
	var/gender_id = all_genders_define_list[1]
	cpress(M, H, "gender_id", list("gender_id" = gender_id))
	TEST_ASSERT_EQUAL(H.identifying_gender, gender_id, "the identifying gender is changed")
	var/list/data = data_of(M, H)
	TEST_ASSERT(("hair_style" in data), "the window data is sent")

/datum/unit_test/dq_hc_tgui/appearance_changer_cooldown
/datum/unit_test/dq_hc_tgui/appearance_changer_cooldown/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/tgui_module/appearance_changer/M = hct_changer(H)
	var/first = M.valid_hairstyles[1]
	var/second = M.valid_hairstyles[length(M.valid_hairstyles)]
	hct_ui(src, H, M, "hair", list("name" = first))
	hct_ui(src, H, M, "hair", list("name" = second))
	TEST_ASSERT_EQUAL(H.h_style, first, "a second button inside half a second is refused")
	M.cooldown = 0
	hct_ui(src, H, M, "hair", list("name" = second))
	TEST_ASSERT_EQUAL(H.h_style, second, "and works once the half second has passed")

/datum/unit_test/dq_hc_tgui/appearance_changer_questions
/datum/unit_test/dq_hc_tgui/appearance_changer_questions/run_gate()
	var/mob/living/carbon/human/H = hct_actor()
	var/datum/tgui_module/appearance_changer/M = hct_changer(H)
	cpress(M, H, "eye_color")
	TEST_ASSERT(p2cl_has_question(H), "a colour is asked for")
	canswer(M, H, "#336699")
	TEST_ASSERT_EQUAL(H.r_eyes, 51, "the eye colour's red is set")
	TEST_ASSERT_EQUAL(H.b_eyes, 153, "and its blue")
	cpress(M, H, "rename")
	canswer(M, H, "Zed Quill")
	TEST_ASSERT_EQUAL(H.real_name, "Zed Quill", "the name is set")
	cpress(M, H, "rename")
	canswer(M, H, "", TRUE)
	TEST_ASSERT_EQUAL(H.real_name, "Zed Quill", "a cancelled question changes nothing")
	cpress(M, H, "weight")
	canswer(M, H, 150)
	TEST_ASSERT(p2cl_has_question(H), "the unit of the weight is asked for")
	canswer(M, H, "Pounds")
	TEST_ASSERT_EQUAL(H.weight, 152, "the weight is set (rounded to four pounds)")
	var/flavor_key = "general"
	H.flavor_texts = list("general" = "")
	cpress(M, H, "flavor_text", list("target" = flavor_key))
	canswer(M, H, "A tall figure.")
	TEST_ASSERT_EQUAL(H.flavor_texts[flavor_key], "A tall figure.", "the flavor text is set")
