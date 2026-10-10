// Behaviour-preservation tests for the hand-converted machines (code/game/machinery, code/modules/reagents/machinery). Same rules and helpers as
// dq_hc_struct_behaviour.dm (its base type, hci_click / hci_answer / hc_ui / hc_data): they pin what a player observes through window buttons,
// clicks, hits and questions, so the file passes before and after a machine moves to the final forms.

// ---------------------------------------------------------------------------------------------------------------------
// Navigation beacon
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/navbeacon_codes_are_edited_through_the_window
/datum/unit_test/dq_hc_struct/navbeacon_codes_are_edited_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/navbeacon/N = mach(/obj/machinery/navbeacon, tile(3, 2))
	N.open = TRUE
	N.set_locked(FALSE)
	press(H, N, "loc_edit", list("new_loc" = "Cargo Bay"))
	TEST_ASSERT_EQUAL(N.location, "Cargo Bay", "the location is set")
	press(H, N, "trans_add_code", list("new_key" = "patrol", "new_val" = "1"))
	TEST_ASSERT_EQUAL(N.codes["patrol"], "1", "a code is added")
	press(H, N, "trans_edit_key", list("code" = "patrol", "new_key" = "route"))
	TEST_ASSERT_EQUAL(N.codes["route"], "1", "a code is renamed")
	TEST_ASSERT_NULL(N.codes["patrol"], "and the old name is gone")
	press(H, N, "trans_edit_code", list("code" = "route", "new_val" = "2"))
	TEST_ASSERT_EQUAL(N.codes["route"], "2", "a code's value is changed")
	var/list/data = hc_data(N, H)
	TEST_ASSERT_EQUAL(data["location"], "Cargo Bay", "the window shows the location")
	TEST_ASSERT_EQUAL(data["codes"]["route"], "2", "and the codes")
	press(H, N, "trans_del", list("code" = "route"))
	TEST_ASSERT_NULL(N.codes?["route"], "a code is deleted")

/datum/unit_test/dq_hc_struct/locked_navbeacon_refuses_edits
/datum/unit_test/dq_hc_struct/locked_navbeacon_refuses_edits/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/navbeacon/N = mach(/obj/machinery/navbeacon, tile(3, 2))
	N.open = TRUE
	N.location = "Home"
	press(H, N, "loc_edit", list("new_loc" = "Away"))
	TEST_ASSERT_EQUAL(N.location, "Home", "a locked beacon keeps its location")
	N.set_locked(FALSE)
	N.open = FALSE
	press(H, N, "loc_edit", list("new_loc" = "Away"))
	TEST_ASSERT_EQUAL(N.location, "Home", "so does one whose cover is shut")

// ---------------------------------------------------------------------------------------------------------------------
// Fire alarm and party button
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/fire_alarm_goes_off_when_shot
/datum/unit_test/dq_hc_struct/fire_alarm_goes_off_when_shot/run_gate()
	var/obj/machinery/firealarm/F = mach(/obj/machinery/firealarm, tile(3, 2))
	TEST_ASSERT(!F.firewarn, "starts quiet")
	var/obj/item/projectile/bullet/B = allocate(/obj/item/projectile/bullet)
	F.bullet_act(B)
	TEST_ASSERT(F.firewarn, "a hit sets it off")

/datum/unit_test/dq_hc_struct/fire_alarm_may_go_off_in_an_emp
/datum/unit_test/dq_hc_struct/fire_alarm_may_go_off_in_an_emp/run_gate()
	var/obj/machinery/firealarm/F = mach(/obj/machinery/firealarm, tile(3, 2))
	for(var/i in 1 to 30)
		F.emp_act(1)
		if(F.firewarn)
			break
	TEST_ASSERT(F.firewarn, "a few EMPs set it off")

/datum/unit_test/dq_hc_struct/party_button_window
/datum/unit_test/dq_hc_struct/party_button_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/partyalarm/P = mach(/obj/machinery/partyalarm, tile(3, 2))
	var/area/A = get_area(P)
	press(H, P, "time", list("value" = 1))
	TEST_ASSERT_EQUAL(P.timing, 1, "the timer is switched on")
	press(H, P, "tp", list("value" = 5))
	TEST_ASSERT_EQUAL(P.time, 15, "the time is stepped")
	press(H, P, "tp", list("value" = 500))
	TEST_ASSERT_EQUAL(P.time, 120, "up to a ceiling")
	var/list/data = hc_data(P, H)
	TEST_ASSERT_EQUAL(data["timing"], TRUE, "the window shows the timer")
	TEST_ASSERT_EQUAL(data["scrambled"], FALSE, "to a human in clear text")
	press(H, P, "alarm")
	TEST_ASSERT(A.party, "the alarm button starts the party")
	press(H, P, "reset")
	TEST_ASSERT(!A.party, "the reset button ends it")
	P.set_grid_power(FALSE)
	press(H, P, "tp", list("value" = 5))
	TEST_ASSERT_EQUAL(P.time, 120, "a dead button takes no presses")

// ---------------------------------------------------------------------------------------------------------------------
// AI liquid dispenser
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/ai_slipper_window
/datum/unit_test/dq_hc_struct/ai_slipper_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/ai_slipper/S = mach(/obj/machinery/ai_slipper, tile(3, 2))
	TEST_ASSERT(S.locked, "starts locked")
	press(H, S, "toggle_on")
	TEST_ASSERT(S.disabled, "a locked dispenser takes no presses from a human")
	S.set_locked(FALSE)
	press(H, S, "toggle_on")
	TEST_ASSERT(!S.disabled, "an unlocked one is switched on")
	var/uses = S.uses
	press(H, S, "toggle_use")
	TEST_ASSERT_EQUAL(S.uses, uses - 1, "firing it spends a use")
	TEST_ASSERT(S.cooldown_on, "and starts the cooldown")
	press(H, S, "toggle_use")
	TEST_ASSERT_EQUAL(S.uses, uses - 1, "a second shot during the cooldown does nothing")
	var/list/data = hc_data(S, H)
	TEST_ASSERT_EQUAL(data["uses"], uses - 1, "the window shows the uses")
	TEST_ASSERT_EQUAL(data["is_silicon"], FALSE, "and who is looking")

// ---------------------------------------------------------------------------------------------------------------------
// Oxygen pump
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/oxygen_pump_pressure_is_set_through_the_window
/datum/unit_test/dq_hc_struct/oxygen_pump_pressure_is_set_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/oxygen_pump/anesthetic/P = mach(/obj/machinery/oxygen_pump/anesthetic, tile(3, 2))
	TEST_ASSERT_NOTNULL(P.tank, "the pump has a tank")
	press(H, P, "pressure", list("pressure" = "max"))
	TEST_ASSERT(abs(P.tank.distribute_pressure - TANK_MAX_RELEASE_PRESSURE) < 1, "max sets the ceiling")
	press(H, P, "pressure", list("pressure" = 50))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, 50, "a number is taken")
	press(H, P, "pressure", list("pressure" = "reset"))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, TANK_DEFAULT_RELEASE_PRESSURE, "reset restores the default")
	press(H, P, "pressure", list("pressure" = "min"))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, 0, "min closes it")
	var/list/data = hc_data(P, H)
	TEST_ASSERT_EQUAL(data["maxReleasePressure"], round(TANK_MAX_RELEASE_PRESSURE), "the window shows the limits")

// ---------------------------------------------------------------------------------------------------------------------
// Pipe dispenser
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/pipe_dispenser_window
/datum/unit_test/dq_hc_struct/pipe_dispenser_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/pipedispenser/D = mach(/obj/machinery/pipedispenser, T)
	press(H, D, "p_layer", list("p_layer" = 3))
	TEST_ASSERT_EQUAL(D.p_layer, 3, "the layer is set")
	var/list/data = hc_data(D, H)
	TEST_ASSERT(length(data["categories"]) > 0, "the window lists the recipes")
	var/list/first = GLOB.atmos_pipe_recipes[GLOB.atmos_pipe_recipes[1]]
	var/datum/pipe_recipe/recipe = first[1]
	press(H, D, "dispense_pipe", list("ref" = "\ref[recipe]"))
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe) in T, "a pipe is dispensed")
	for(var/obj/item/pipe/P in T)
		qdel(P)
	D.unwrenched = 1
	press(H, D, "dispense_pipe", list("ref" = "\ref[recipe]"))
	TEST_ASSERT_NULL(locate(/obj/item/pipe) in T, "an unwrenched dispenser gives nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Floor layer
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/floorlayer_work_mode_is_chosen_with_a_wrench
/datum/unit_test/dq_hc_struct/floorlayer_work_mode_is_chosen_with_a_wrench/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/floorlayer/F = mach(/obj/machinery/floorlayer, tile(3, 2))
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, tile(2, 2))
	TEST_ASSERT(!F.work_modes["laying"], "laying starts off")
	hci_click(H, F, W)
	hci_answer(H, "laying")
	settle()
	TEST_ASSERT(F.work_modes["laying"], "the chosen mode is switched on")
	hci_click(H, F, W)
	hci_answer(H, "laying")
	settle()
	TEST_ASSERT(!F.work_modes["laying"], "and off again")

/datum/unit_test/dq_hc_struct/floorlayer_work_mode_answer_is_dropped_when_the_person_walks_away
/datum/unit_test/dq_hc_struct/floorlayer_work_mode_answer_is_dropped_when_the_person_walks_away/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/floorlayer/F = mach(/obj/machinery/floorlayer, tile(3, 2))
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, tile(2, 2))
	hci_click(H, F, W)
	H.forceMove(tile(0, 0))
	hci_answer(H, "collect")
	settle()
	TEST_ASSERT(!F.work_modes["collect"], "an answer from someone no longer next to it is dropped")

// ---------------------------------------------------------------------------------------------------------------------
// Portable atmospherics (canister, pump, scrubber)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/canister_window
/datum/unit_test/dq_hc_struct/canister_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/portable_atmospherics/canister/C = mach(/obj/machinery/portable_atmospherics/canister, tile(3, 2))
	TEST_ASSERT(!C.valve_open, "starts closed")
	press(H, C, "valve")
	TEST_ASSERT(C.valve_open, "the valve button opens the valve")
	TEST_ASSERT(length(C.release_log) > 0, "and the log says who did it")
	press(H, C, "valve")
	TEST_ASSERT(!C.valve_open, "and closes it again")
	press(H, C, "pressure", list("pressure" = 500))
	TEST_ASSERT_EQUAL(C.release_pressure, 500, "a number sets the release pressure")
	press(H, C, "pressure", list("pressure" = 100000))
	TEST_ASSERT_EQUAL(C.release_pressure, 10 * ONE_ATMOSPHERE, "up to a ceiling")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["valveOpen"], 0, "the window shows the valve")
	TEST_ASSERT_EQUAL(data["releasePressure"], round(C.release_pressure), "and the release pressure")

/datum/unit_test/dq_hc_struct/pump_window_and_emp
/datum/unit_test/dq_hc_struct/pump_window_and_emp/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/portable_atmospherics/powered/pump/P = mach(/obj/machinery/portable_atmospherics/powered/pump, tile(3, 2))
	TEST_ASSERT(!P.on, "starts off")
	press(H, P, "power")
	TEST_ASSERT(P.on, "the power button switches it on")
	var/dir_out = P.direction_out
	press(H, P, "direction")
	TEST_ASSERT_NOTEQUAL(P.direction_out, dir_out, "the direction button flips the direction")
	press(H, P, "pressure", list("pressure" = 2000))
	TEST_ASSERT_EQUAL(P.target_pressure, 2000, "a number sets the target pressure")
	var/list/data = hc_data(P, H)
	TEST_ASSERT_EQUAL(data["target_pressure"], 2000, "the window shows it")
	TEST_ASSERT_EQUAL(data["on"], TRUE, "and the power")
	dir_out = P.direction_out
	P.emp_act(1)
	TEST_ASSERT_NOTEQUAL(P.direction_out, dir_out, "a direct EMP always flips the direction")

/datum/unit_test/dq_hc_struct/scrubber_window_and_emp
/datum/unit_test/dq_hc_struct/scrubber_window_and_emp/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/portable_atmospherics/powered/scrubber/S = mach(/obj/machinery/portable_atmospherics/powered/scrubber, tile(3, 2))
	TEST_ASSERT(!S.on, "starts off")
	press(H, S, "power")
	TEST_ASSERT(S.on, "the power button switches it on")
	press(H, S, "volume_adj", list("vol" = 100))
	TEST_ASSERT_EQUAL(S.volume_rate, clamp(100, S.minrate, S.maxrate), "the rate button sets the rate within its limits")
	var/list/data = hc_data(S, H)
	TEST_ASSERT_EQUAL(data["on"], 1, "the window shows the power")
	var/was = S.on
	for(var/i in 1 to 30)
		S.emp_act(1)
		if(S.on != was)
			break
	TEST_ASSERT_NOTEQUAL(S.on, was, "a few EMPs toggle it")

// ---------------------------------------------------------------------------------------------------------------------
// Biogenerator
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/biogenerator_sells_for_biomass
/datum/unit_test/dq_hc_struct/biogenerator_sells_for_biomass/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/biogenerator/B = mach(/obj/machinery/biogenerator, T)
	B.points = 1000
	press(H, B, "purchase", list("amount" = 1, "cat" = "Leather Products", "name" = "Wallet"))
	TEST_ASSERT_NOTNULL(locate(/obj/item/storage/wallet) in T, "a wallet is made")
	TEST_ASSERT(B.points < 1000, "and costs biomass")
	var/points = B.points
	press(H, B, "purchase", list("amount" = 1, "cat" = "Leather Products", "name" = "No Such Thing"))
	TEST_ASSERT_EQUAL(B.points, points, "something that is not for sale costs nothing")
	B.points = 0
	var/count = 0
	for(var/obj/item/storage/wallet/W in T)
		count++
	press(H, B, "purchase", list("amount" = 1, "cat" = "Leather Products", "name" = "Wallet"))
	var/after = 0
	for(var/obj/item/storage/wallet/W in T)
		after++
	TEST_ASSERT_EQUAL(after, count, "with no biomass nothing is made")
	var/list/data = hc_data(B, H)
	TEST_ASSERT_EQUAL(data["points"], 0, "the window shows the biomass")
	TEST_ASSERT_EQUAL(data["beaker"], !!B.beaker, "and whether a beaker is loaded")

// Added with the conversion: the legacy label question needed a window state no player-less test can meet.
/datum/unit_test/dq_hc_struct/canister_is_relabelled
/datum/unit_test/dq_hc_struct/canister_is_relabelled/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/portable_atmospherics/canister/C = mach(/obj/machinery/portable_atmospherics/canister, tile(3, 2))
	press(H, C, "relabel")
	TEST_ASSERT(asked(H), "a relabellable canister asks for a label")
	hci_answer(H, "\[O2\]")
	settle()
	TEST_ASSERT_EQUAL(C.canister_color, "blue", "the label paints the canister")
	TEST_ASSERT_EQUAL(C.name, "Canister: \[O2\]", "and names it")

// ---------------------------------------------------------------------------------------------------------------------
// Window shapes: the keys of the data every converted machine window sends (captured from the legacy forms)
// ---------------------------------------------------------------------------------------------------------------------

/// The sorted keys of the window data `host` sends `viewer`, as text.
/proc/hcs_window_keys(datum/host, mob/viewer)
	var/list/data = hc_data(host, viewer)
	var/list/keys = list()
	for(var/key in data)
		keys += "[key]"
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	return keys.Join(",")

/datum/unit_test/dq_hc_struct/machinery_window_shapes
/datum/unit_test/dq_hc_struct/machinery_window_shapes/run_gate()
	var/mob/living/carbon/human/H = person()
	var/list/expected = list(
		"/obj/machinery/atmospherics/unary/cryo_cell" = "beakerLabel,beakerVolume,cellTemperature,cellTemperatureStatus,hasOccupant,isBeakerLoaded,isOperating,occupant",
		"/obj/machinery/bodyscanner" = "occupant,occupied",
		"/obj/machinery/alarm" = "atmos_alarm,danger_level,environment_data,fire_alarm,locked,rcon,remoteUser,siliconUser,target_temperature",
		"/obj/machinery/autolathe" = "active,materialChoices,materials,materialsmax,materialtotal",
		"/obj/machinery/bomb_tester" = "canister,mode,simulating,sim_canister_output,tank1,tank1ref,tank2,tank2ref",
		"/obj/machinery/doppler_array" = "explosions",
		"/obj/machinery/computer/general_air_control" = "sensors",
		"/obj/machinery/computer/general_air_control/large_tank_control" = "input_flow_setting,input_info,max_flowrate,max_pressure,output_info,pressure_setting,sensors,tanks",
		"/obj/machinery/computer/general_air_control/supermatter_core" = "core,input_flow_setting,input_info,max_flowrate,max_pressure,output_info,pressure_setting,sensors",
		"/obj/machinery/computer/general_air_control/fuel_injection" = "automation,device_info,fuel,sensors",
		"/obj/machinery/computer/cryopod" = "allow_items,crew,items,real_name",
		"/obj/machinery/exonet_node" = "allowCommunicators,allowNewscasters,allowPDAs,logs,on",
		"/obj/machinery/media/jukebox" = "admin,current_genre,current_track,current_track_ref,loop_mode,percent,playing,tracks,volume",
		"/obj/machinery/newscaster" = "active_num,channels,channel_name,company,c_locked,message_num,msg,paper_remaining,photo_data,securityCaster,temp,title,total_num,unit_no,user,viewing_channel,wanted_issue",
		"/obj/machinery/nuclearbomb" = "anchored,auth,code_display,lighthack,safety,status_label,timeleft,timing,wires,wire_view,yes_code",
		"/obj/machinery/gear_painter" = "activemode,buildhue,buildsat,buildval,item_name,item_preview,item_sprite,matrixcolors",
		"/obj/machinery/partslathe" = "building,buildPercent,copyBoard,copyBoardReqComponents,error,materials,panelOpen,queue,recipies,SHEET_MATERIAL_AMOUNT",
		"/obj/machinery/petrification" = "able_to_unpetrify,adjective,can_remote,discard_clothes,identifier,material,t,target,tint",
		"/obj/machinery/porta_turret" = "check_weapons,lethal,lethal_is_configurable,locked,neutralize_all,neutralize_criminals,neutralize_down,neutralize_noaccess,neutralize_nonsynth,neutralize_norecord,neutralize_unidentified,on,targetting_is_configurable",
		"/obj/machinery/requests_console" = "announceAuth,announcementConsole,assist_dept,department,info_dept,message,message_log,msgStamped,msgVerified,newmessagepriority,priority,recipient,screen,silent,supply_dept",
		"/obj/machinery/robotic_fabricator" = "metal_amount,operating",
		"/obj/machinery/suit_cycler" = "active,can_repair,damage,helmet,locked,max_uv_level,model_text,occupied,safeties,suit,userHasAccess,uv_active,uv_level",
		"/obj/machinery/suit_storage_unit" = "broken,helmet,locked,mask,occupied,open,panelopen,safeties,storage,suit,uv_active,uv_super",
		"/obj/machinery/turretid" = "access_is_configurable,check_weapons,lethal,lethal_is_configurable,locked,neutralize_all,neutralize_criminals,neutralize_down,neutralize_noaccess,neutralize_nonsynth,neutralize_norecord,neutralize_unidentified,on,one_access,selectedAccess,targetting_is_configurable",
		"/obj/machinery/chem_master" = "beaker,bottlesprite,condi,loaded_pill_bottle,modal,mode,pillsprite,printing",
		"/obj/machinery/chemical_analyzer" = "beakerMax,beakerTotal,scannedReagents",
		"/obj/machinery/chemical_synthesizer" = "bottle_icon,busy,catalyst,catalystCurrentVolume,catalystMaxVolume,catalyst_reagents,chemicals,drug_substance,modal,panel_open,patch_icon,pill_icon,production_mode,queue,recipes,rxn_vessel,use_catalyst",
		"/obj/machinery/chemical_dispenser" = "amount,beakerContents,beakerCurrentVolume,beakerMaxVolume,chemicals,glass,isBeakerLoaded,recipes,recordingRecipe",
	)
	for(var/type in expected)
		var/obj/machinery/M = allocate(type, tile(3, 2))
		M.set_grid_power(TRUE)
		M.set_broken_condition(FALSE)
		TEST_ASSERT_EQUAL(hcs_window_keys(M, H), expected[type], "[type] sends the window data it always did")

// ---------------------------------------------------------------------------------------------------------------------
// Medical machines, exonet node, turrets, fabricator, requests console, suit cycler
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/cryo_cell_is_switched_through_the_window
/datum/unit_test/dq_hc_struct/cryo_cell_is_switched_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/atmospherics/unary/cryo_cell/C = mach(/obj/machinery/atmospherics/unary/cryo_cell, tile(3, 2))
	TEST_ASSERT(!C.cooling, "starts off")
	press(H, C, "switchOn")
	TEST_ASSERT(C.cooling, "the on button switches it on")
	var/list/data = hc_data(C, H)
	TEST_ASSERT(data["isOperating"], "the window shows it")
	press(H, C, "switchOff")
	TEST_ASSERT(!C.cooling, "and the off button switches it off")

/datum/unit_test/dq_hc_struct/body_scanner_prints_a_sheet
/datum/unit_test/dq_hc_struct/body_scanner_prints_a_sheet/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/bodyscanner/S = mach(/obj/machinery/bodyscanner, T)
	press(H, S, "print_p")
	TEST_ASSERT_NOTNULL(locate(/obj/item/paper) in T, "the print button prints a scan sheet")

/datum/unit_test/dq_hc_struct/exonet_node_ports_are_toggled
/datum/unit_test/dq_hc_struct/exonet_node_ports_are_toggled/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/exonet_node/E = mach(/obj/machinery/exonet_node, tile(3, 2))
	E.toggle = 0
	press(H, E, "toggle_power")
	TEST_ASSERT(E.toggle, "the power button switches the node on")
	TEST_ASSERT(E.allow_external_PDAs, "its PDA port starts open")
	press(H, E, "toggle_PDA_port")
	TEST_ASSERT(!E.allow_external_PDAs, "the PDA port button closes it")
	var/list/data = hc_data(E, H)
	TEST_ASSERT_EQUAL(data["allowPDAs"], 0, "the window shows it")
	TEST_ASSERT_EQUAL(data["on"], 1, "and the power")

/datum/unit_test/dq_hc_struct/portable_turret_window_obeys_its_lock
/datum/unit_test/dq_hc_struct/portable_turret_window_obeys_its_lock/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/porta_turret/T = mach(/obj/machinery/porta_turret, tile(3, 2))
	var/all = T.check_all
	press(H, T, "authall")
	TEST_ASSERT_EQUAL(T.check_all, all, "a locked turret takes no presses from a human")
	cap_key_set(T, LOCK_LOCKED, FALSE, null)
	press(H, T, "authall")
	TEST_ASSERT_NOTEQUAL(T.check_all, all, "an unlocked one toggles the setting")
	var/enabled = T.enabled
	press(H, T, "power")
	TEST_ASSERT_NOTEQUAL(T.enabled, enabled, "and its power")

/datum/unit_test/dq_hc_struct/portable_turret_is_emagged_and_scrambled_by_an_emp
/datum/unit_test/dq_hc_struct/portable_turret_is_emagged_and_scrambled_by_an_emp/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/porta_turret/T = mach(/obj/machinery/porta_turret, tile(3, 2))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	T.set_enabled(TRUE)
	hci_click(H, T, E)
	settle()
	TEST_ASSERT(emag_emagged(T), "an emag subverts it")
	test_time(7 SECONDS)
	T.emp_act(1)
	TEST_ASSERT(!T.armed, "an EMP on a running turret knocks it out")

/datum/unit_test/dq_hc_struct/turret_controller_window_and_emag
/datum/unit_test/dq_hc_struct/turret_controller_window_and_emag/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/turretid/C = mach(/obj/machinery/turretid, tile(3, 2))
	var/all = C.check_all
	press(H, C, "authall")
	TEST_ASSERT_EQUAL(C.check_all, all, "a locked panel takes no presses from a human")
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	hci_click(H, C, E)
	settle()
	TEST_ASSERT(emag_emagged(C), "an emag subverts it")
	TEST_ASSERT(!lock_locked(C), "and unlocks it")
	press(H, C, "authall")
	TEST_ASSERT_NOTEQUAL(C.check_all, all, "an unlocked panel toggles the setting")

/datum/unit_test/dq_hc_struct/robotic_fabricator_builds_when_idle
/datum/unit_test/dq_hc_struct/robotic_fabricator_builds_when_idle/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/robotic_fabricator/F = mach(/obj/machinery/robotic_fabricator, tile(3, 2))
	F.metal_amount = 100000
	F.operating = TRUE
	press(H, F, "build_l_arm")
	TEST_ASSERT_EQUAL(F.metal_amount, 100000, "a busy fabricator takes no order")
	F.operating = FALSE
	press(H, F, "build_l_arm")
	TEST_ASSERT_EQUAL(F.metal_amount, 75000, "an idle one spends the metal")
	var/list/data = hc_data(F, H)
	TEST_ASSERT_EQUAL(data["metal_amount"], 75000, "the window shows what is left")

/datum/unit_test/dq_hc_struct/requests_console_window
/datum/unit_test/dq_hc_struct/requests_console_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/requests_console/R = mach(/obj/machinery/requests_console, tile(3, 2))
	var/silent = R.silent
	press(H, R, "toggleSilent")
	TEST_ASSERT_NOTEQUAL(R.silent, silent, "the silence button flips it")
	press(H, R, "setScreen", list("setScreen" = 1))
	TEST_ASSERT_EQUAL(R.screen, 1, "the screen button shows a screen")
	press(H, R, "write", list("priority" = 1, "write" = "Cargo"))
	TEST_ASSERT(asked(H), "writing a message asks for its text")
	hci_answer(H, "Crates, please")
	settle()
	TEST_ASSERT_EQUAL(R.recipient, "Cargo", "for the chosen recipient")
	TEST_ASSERT_EQUAL(R.message, "Crates, please", "the answer is the message")

/datum/unit_test/dq_hc_struct/suit_cycler_is_emagged_and_dials_its_radiation
/datum/unit_test/dq_hc_struct/suit_cycler_is_emagged_and_dials_its_radiation/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/suit_cycler/S = mach(/obj/machinery/suit_cycler, tile(3, 2))
	press(H, S, "radlevel", list("radlevel" = 5))
	TEST_ASSERT_EQUAL(S.radiation_level, 3, "an ordinary cycler stops at level 3")
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	hci_click(H, S, E)
	settle()
	TEST_ASSERT(S.emagged(), "an emag subverts it")
	TEST_ASSERT(!S.safeties, "and takes the safeties off")
	press(H, S, "radlevel", list("radlevel" = 5))
	TEST_ASSERT_EQUAL(S.radiation_level, 5, "an emagged one goes to 5")

// Added with the conversion: the legacy text question needed a window state no player-less test can meet.
/datum/unit_test/dq_hc_struct/requests_console_message_is_written
/datum/unit_test/dq_hc_struct/requests_console_message_is_written/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/requests_console/R = mach(/obj/machinery/requests_console, tile(3, 2))
	press(H, R, "write", list("priority" = 1, "write" = "Cargo"))
	hci_answer(H, "Send crates")
	settle()
	TEST_ASSERT_EQUAL(R.message, "Send crates", "the text is the message")
	TEST_ASSERT_EQUAL(R.priority, 1, "at the chosen priority")
	var/list/data = hc_data(R, H)
	TEST_ASSERT_EQUAL(data["message"], "Send crates", "the window shows it")

// ---------------------------------------------------------------------------------------------------------------------
// Hits and emags of machines and tanks
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/tanks_burst_when_hit
/datum/unit_test/dq_hc_struct/tanks_burst_when_hit/run_gate()
	// A burst canister empties into the room: its air is put back after the test (restore_atmos()), or the next test's mobs are blown about.
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		dq_atmos_test_snapshot_air(T)
	// The oil barrel splashes the room (radius 3): the slick floor is dried after the test, or the next test's people slide across it.
	defer_cleanup(src, PROC_REF(dry_the_room))
	var/obj/structure/reagent_dispensers/watertank/W = allocate(/obj/structure/reagent_dispensers/watertank, tile(3, 2))
	W.blob_act()
	TEST_ASSERT(QDELETED(W), "a blob bursts a water tank")
	var/obj/structure/reagent_dispensers/cookingoil/O = allocate(/obj/structure/reagent_dispensers/cookingoil, tile(3, 3))
	O.ex_act(1)
	TEST_ASSERT(QDELETED(O), "a blast bursts a cooking oil barrel")
	var/obj/machinery/portable_atmospherics/canister/C = allocate(/obj/machinery/portable_atmospherics/canister, tile(2, 3))
	C.blob_act()
	TEST_ASSERT(QDELETED(C), "a blob bursts a canister")

/datum/unit_test/dq_hc_struct/tanks_burst_when_hit/proc/dry_the_room()
	for(var/turf/simulated/T in block(locate(run_loc_floor_bottom_left.x - 1, run_loc_floor_bottom_left.y - 1, run_loc_floor_bottom_left.z), locate(run_loc_floor_top_right.x + 1, run_loc_floor_top_right.y + 1, run_loc_floor_top_right.z)))
		if(T.wet)
			T.wet_floor_finish()

/datum/unit_test/dq_hc_struct/operating_table_may_be_knocked_flat_by_a_light_blast
/datum/unit_test/dq_hc_struct/operating_table_may_be_knocked_flat_by_a_light_blast/run_gate()
	var/obj/machinery/optable/T = mach(/obj/machinery/optable, tile(3, 2))
	TEST_ASSERT(T.density, "starts standing")
	for(var/i in 1 to 60)
		T.ex_act(3)
		if(!T.density)
			break
	TEST_ASSERT(!T.density, "light blasts knock it flat in the end")

/datum/unit_test/dq_hc_struct/barrier_takes_two_sequencers
/datum/unit_test/dq_hc_struct/barrier_takes_two_sequencers/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/deployable/barrier/B = mach(/obj/machinery/deployable/barrier, tile(3, 2))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	E.uses = 10
	hci_click(H, B, E)
	settle()
	TEST_ASSERT_EQUAL(B.emagged, 1, "the first sequencer breaks the access lock")
	hci_click(H, B, E)
	settle()
	TEST_ASSERT_EQUAL(B.emagged, 2, "the second shorts out the anchoring")

/datum/unit_test/dq_hc_struct/gear_dispenser_is_emagged_but_the_custom_one_refuses
/datum/unit_test/dq_hc_struct/gear_dispenser_is_emagged_but_the_custom_one_refuses/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/gear_dispenser/G = mach(/obj/machinery/gear_dispenser, tile(3, 2))
	var/obj/machinery/gear_dispenser/custom/C = mach(/obj/machinery/gear_dispenser/custom, tile(3, 3))
	var/obj/item/card/emag/E = allocate(/obj/item/card/emag, tile(2, 2))
	E.uses = 10
	hci_click(H, G, E)
	settle()
	TEST_ASSERT(G.emagged(), "an emag subverts the dispenser")
	hci_click(H, C, E)
	settle()
	TEST_ASSERT(!C.emagged(), "the custom one will not be emagged")

/datum/unit_test/dq_hc_struct/thermoregulator_is_switched_on_by_an_emp
/datum/unit_test/dq_hc_struct/thermoregulator_is_switched_on_by_an_emp/run_gate()
	var/obj/machinery/power/thermoregulator/T = mach(/obj/machinery/power/thermoregulator, tile(3, 2))
	TEST_ASSERT(!T.on, "starts off")
	T.emp_act(1)
	TEST_ASSERT(T.on, "an EMP switches it on")

// ---------------------------------------------------------------------------------------------------------------------
// Bomb tester and point defence (batch M5)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/bomb_tester_takes_settings_only_when_idle
/datum/unit_test/dq_hc_struct/bomb_tester_takes_settings_only_when_idle/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/bomb_tester/B = mach(/obj/machinery/bomb_tester, tile(3, 2))
	press(H, B, "set_mode", list("mode" = 2))
	TEST_ASSERT_EQUAL(B.sim_mode, 2, "the mode button sets the mode")
	press(H, B, "set_can_pressure", list("pressure" = 1e9))
	TEST_ASSERT(B.sim_canister_output <= ONE_ATMOSPHERE * 10, "the canister pressure is clamped")
	B.simulating = 1
	press(H, B, "set_mode", list("mode" = 1))
	TEST_ASSERT_EQUAL(B.sim_mode, 2, "a running simulation takes no new mode")

/datum/unit_test/dq_hc_struct/point_defense_gun_is_retagged_with_a_multitool
/datum/unit_test/dq_hc_struct/point_defense_gun_is_retagged_with_a_multitool/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/pointdefense/P = mach(/obj/machinery/pointdefense, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	hci_click(H, P, M)
	TEST_ASSERT(asked(H), "the multitool asks for the new tag")
	hci_answer(H, "northern_net")
	settle()
	TEST_ASSERT_EQUAL(P.id_tag, "northern_net", "the answer becomes the tag")

// ---------------------------------------------------------------------------------------------------------------------
// Newscaster, suit storage, jukebox, colour painter (batch M6)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/newscaster_draft_is_edited_through_its_window
/datum/unit_test/dq_hc_struct/newscaster_draft_is_edited_through_its_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/newscaster/N = mach(/obj/machinery/newscaster, tile(3, 2))
	var/locked_before = N.c_locked
	press(H, N, "set_channel_lock")
	TEST_ASSERT(N.c_locked != locked_before, "the lock button flips the new channel's lock")
	press(H, N, "set_channel_name", list("val" = "Daily Tidings"))
	TEST_ASSERT_EQUAL(N.channel_name, "Daily Tidings", "the name box names the channel")
	N.set_temp("hello", "info", FALSE)
	press(H, N, "cleartemp")
	TEST_ASSERT_NULL(N.temp, "the clear button drops the notice")
	press(H, N, "set_new_title")
	TEST_ASSERT(asked(H), "the title button asks for a title")
	hci_answer(H, "Headline")
	settle()
	TEST_ASSERT_EQUAL(N.title, "Headline", "the answer becomes the title")

/datum/unit_test/dq_hc_struct/suit_storage_door_and_lock_work_until_it_is_broken
/datum/unit_test/dq_hc_struct/suit_storage_door_and_lock_work_until_it_is_broken/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/suit_storage_unit/U = mach(/obj/machinery/suit_storage_unit, tile(3, 2))
	var/open_before = U.isopen
	press(H, U, "door")
	TEST_ASSERT(U.isopen != open_before, "the door button works the door")
	var/open_now = U.isopen
	U.isbroken = TRUE
	press(H, U, "door")
	TEST_ASSERT_EQUAL(U.isopen, open_now, "a broken unit answers no button")

/datum/unit_test/dq_hc_struct/jukebox_volume_and_loop_are_set_through_its_window
/datum/unit_test/dq_hc_struct/jukebox_volume_and_loop_are_set_through_its_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/media/jukebox/J = mach(/obj/machinery/media/jukebox, tile(3, 2))
	press(H, J, "volume", list("val" = 7))
	TEST_ASSERT_EQUAL(J.volume, 1, "the volume is clamped to full")
	press(H, J, "volume", list("val" = 0.25))
	TEST_ASSERT_EQUAL(J.volume, 0.25, "and set as given")
	press(H, J, "loopmode", list("loopmode" = JUKEMODE_REPEAT_SONG))
	TEST_ASSERT_EQUAL(J.loop_mode, JUKEMODE_REPEAT_SONG, "the loop mode follows the button")
	press(H, J, "loopmode", list("loopmode" = 99))
	TEST_ASSERT_EQUAL(J.loop_mode, JUKEMODE_REPEAT_SONG, "an unknown loop mode changes nothing")

/datum/unit_test/dq_hc_struct/painter_takes_no_setting_while_empty
/datum/unit_test/dq_hc_struct/painter_takes_no_setting_while_empty/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/gear_painter/P = mach(/obj/machinery/gear_painter, tile(3, 2))
	var/mode_before = P.active_mode
	press(H, P, "switch_modes", list("mode" = mode_before + 1))
	TEST_ASSERT_EQUAL(P.active_mode, mode_before, "with nothing inside the mode stays")
	press(H, P, "choose_color")
	TEST_ASSERT(!asked(H), "and no colour is asked for")

// ---------------------------------------------------------------------------------------------------------------------
// Atmospherics control consoles and gas sensors (batch M7)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/air_control_setpoints_are_set_through_the_window
/datum/unit_test/dq_hc_struct/air_control_setpoints_are_set_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/computer/general_air_control/large_tank_control/C = mach(/obj/machinery/computer/general_air_control/large_tank_control, tile(3, 2))
	press(H, C, "adj_pressure", list("adj_pressure" = 1000))
	TEST_ASSERT_EQUAL(C.pressure_setting, 1000, "the pressure box sets the output pressure")
	press(H, C, "adj_input_flow_rate", list("adj_input_flow_rate" = 120))
	TEST_ASSERT_EQUAL(C.input_flow_setting, 120, "the flow box sets the injector rate")
	var/obj/machinery/computer/general_air_control/supermatter_core/S = mach(/obj/machinery/computer/general_air_control/supermatter_core, tile(4, 2))
	press(H, S, "adj_pressure", list("adj_pressure" = 50))
	TEST_ASSERT_EQUAL(S.pressure_setting, 50, "the core console takes its own pressure")

/datum/unit_test/dq_hc_struct/air_sensor_output_is_toggled_through_its_menu
/datum/unit_test/dq_hc_struct/air_sensor_output_is_toggled_through_its_menu/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/air_sensor/S = mach(/obj/machinery/air_sensor, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	var/before = S.output
	H.next_click = 0
	test_click(H, S, M)
	TEST_ASSERT(asked(H), "the multitool asks what to change")
	hci_answer(H, "Pressure: \[[(before & 1) ? "YES" : "NO"]]")
	settle()
	TEST_ASSERT_EQUAL(S.output & 1, (before & 1) ? 0 : 1, "the pressure bit is flipped")

/datum/unit_test/dq_hc_struct/air_control_menu_leads_to_the_frequency_question
/datum/unit_test/dq_hc_struct/air_control_menu_leads_to_the_frequency_question/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/computer/general_air_control/C = mach(/obj/machinery/computer/general_air_control, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	H.next_click = 0
	test_click(H, C, M)
	TEST_ASSERT(asked(H), "the multitool asks what to change")
	hci_answer(H, "Frequency")
	settle()
	TEST_ASSERT(asked(H), "the frequency is asked next")

// ---------------------------------------------------------------------------------------------------------------------
// Telecommunications, small machines and the questions they ask (batch M7)
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/telecomms_node_is_configured_through_its_window
/datum/unit_test/dq_hc_struct/telecomms_node_is_configured_through_its_window/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/telecomms/relay/R = mach(/obj/machinery/telecomms/relay, tile(3, 2))
	H.put_in_active_hand(allocate(/obj/item/multitool, H)) // the window's buttons need a multitool
	var/toggled_before = R.toggled
	press(H, R, "toggle")
	TEST_ASSERT(R.toggled != toggled_before, "the power button switches the node")
	press(H, R, "id")
	TEST_ASSERT(asked(H), "the id button asks for a new id")
	hci_answer(H, "relay_north")
	settle()
	TEST_ASSERT_EQUAL(R.id, "relay_north", "the answer becomes the id")
	var/receiving_before = R.receiving
	press(H, R, "receive")
	TEST_ASSERT(R.receiving != receiving_before, "the relay's own buttons work too")
	press(H, R, "cleartemp")
	TEST_ASSERT_NULL(R.temp, "the clear button drops the notice")

/datum/unit_test/dq_hc_struct/telecomms_monitor_changes_its_network_through_a_question
/datum/unit_test/dq_hc_struct/telecomms_monitor_changes_its_network_through_a_question/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/computer/telecomms/monitor/M = mach(/obj/machinery/computer/telecomms/monitor, tile(3, 2))
	press(H, M, "network")
	TEST_ASSERT(asked(H), "the network button asks for a network")
	hci_answer(H, "tcomsat")
	settle()
	TEST_ASSERT_EQUAL(M.network, "tcomsat", "the answer becomes the network")
	var/obj/machinery/computer/telecomms/server/S = mach(/obj/machinery/computer/telecomms/server, tile(4, 2))
	press(H, S, "network")
	TEST_ASSERT(asked(H), "the log browser asks as well")
	hci_answer(H, "tcomsat2")
	settle()
	TEST_ASSERT_EQUAL(S.network, "tcomsat2", "and takes the answer")

/datum/unit_test/dq_hc_struct/thermoregulator_takes_a_temperature_from_a_multitool
/datum/unit_test/dq_hc_struct/thermoregulator_takes_a_temperature_from_a_multitool/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/power/thermoregulator/T = mach(/obj/machinery/power/thermoregulator, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	hci_click(H, T, M) // the multitool is an op that asks (it was multitool_act(), which the op replaced)
	TEST_ASSERT(asked(H), "the multitool asks for a temperature")
	hci_answer(H, 20)
	settle()
	TEST_ASSERT(abs(T.target_temp - convert_c2k(20)) < 0.1, "the answer in degrees C becomes the target")

/datum/unit_test/dq_hc_struct/meter_takes_an_id_only_while_its_panel_is_open
/datum/unit_test/dq_hc_struct/meter_takes_an_id_only_while_its_panel_is_open/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/meter/N = mach(/obj/machinery/meter, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	N.set_open(TRUE)
	test_click(H, N, M)
	TEST_ASSERT(asked(H), "an open meter asks for an id")
	hci_answer(H, "exhaust_pipe")
	settle()
	TEST_ASSERT_EQUAL(N.id, "exhaust_pipe", "the answer becomes the id")
	test_click(H, N, M)
	N.set_open(FALSE)
	var/before = N.id
	hci_answer(H, "other_tag")
	settle()
	TEST_ASSERT_EQUAL(N.id, before, "a panel shut meanwhile drops the answer")

/datum/unit_test/dq_hc_struct/mass_driver_id_is_set_with_a_multitool
/datum/unit_test/dq_hc_struct/mass_driver_id_is_set_with_a_multitool/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/mass_driver/D = mach(/obj/machinery/mass_driver, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H)
	H.put_in_active_hand(M)
	hci_click(H, D, M)
	TEST_ASSERT_EQUAL(asked(H), FALSE, "a closed driver asks nothing")
	D.set_panel_open(TRUE) // the maintenance panel, opened as a screwdriver would
	hci_click(H, D, M)
	TEST_ASSERT(asked(H), "an open driver asks for an id")
	hci_answer(H, 42)
	settle()
	TEST_ASSERT_EQUAL(D.id, 42, "the answer becomes the id")

/datum/unit_test/dq_hc_struct/camera_assembly_is_configured_through_three_questions
/datum/unit_test/dq_hc_struct/camera_assembly_is_configured_through_three_questions/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/turf/T = tile(3, 2)
	var/obj/item/camera_assembly/C = allocate(/obj/item/camera_assembly, T)
	C.state = 3
	var/obj/item/tool/screwdriver/S = allocate(/obj/item/tool/screwdriver, H)
	H.put_in_active_hand(S)
	C.interaction_tool_act(H, S, TOOL_SCREWDRIVER)
	TEST_ASSERT(asked(H), "the screwdriver asks for the networks")
	hci_answer(H, "Security,Secret")
	settle()
	TEST_ASSERT(asked(H), "then for a name")
	hci_answer(H, "Hall camera")
	settle()
	var/obj/machinery/camera/cam = locate(/obj/machinery/camera) in T
	TEST_ASSERT_NOTNULL(cam, "the camera is built")
	TEST_ASSERT_EQUAL(C.state, 4, "and the assembly is closed up")
	TEST_ASSERT(asked(H), "then for a direction")

/datum/unit_test/dq_hc_struct/oxygen_pump_tank_is_swapped_in_maintenance
/datum/unit_test/dq_hc_struct/oxygen_pump_tank_is_swapped_in_maintenance/run_gate()
	var/mob/living/carbon/human/H = person(tile(3, 3))
	var/obj/machinery/oxygen_pump/P = mach(/obj/machinery/oxygen_pump/anesthetic, tile(3, 2))
	var/obj/item/tank/T = P.tank
	TEST_ASSERT_NOTNULL(T, "the pump starts with a tank")
	P.set_maintenance(TRUE)
	hci_click(H, P, null)
	settle()
	TEST_ASSERT_NULL(P.tank, "a bare hand takes the tank out in maintenance")
	TEST_ASSERT(T in H.get_all_held_items(), "and holds it")
	hci_click(H, P, T)
	settle()
	TEST_ASSERT_EQUAL(P.tank, T, "the same tank goes back in")

/datum/unit_test/dq_hc_struct/ai_slipper_repeat_parks
/datum/unit_test/dq_hc_struct/ai_slipper_repeat_parks/run_gate()
	var/obj/machinery/ai_slipper/S = mach(/obj/machinery/ai_slipper, tile(3, 2))
	S.uses = 0
	S.cooldown_time = world.timeofday
	S.set_cooldown_on(TRUE)
	test_phase(KERNEL_PHASE_R) // drain the gate wake before measuring its interval
	test_time(0.5 SECONDS)
	TEST_ASSERT(S.cooldown_on, "exhaustion retains the original gameplay cooldown flag")
	TEST_ASSERT(S.cooldown_stopped, "the exhausted repeat is stopped")
	S.uses = 1
	test_time(1 SECOND)
	TEST_ASSERT(S.cooldown_on, "adding uses alone does not restart a stopped repeat")
	S.set_cooldown_on(FALSE)
	test_phase(KERNEL_PHASE_R) // make the separate off transition observable
	S.set_cooldown_on(TRUE)
	test_phase(KERNEL_PHASE_R) // drain the gate wake before measuring its interval
	test_time(0.5 SECONDS)
	TEST_ASSERT(!S.cooldown_on, "a new gate transition restarts and finishes the cooldown")

/datum/unit_test/dq_hc_struct/magnet_repeat_stops_until_gate_changes
/datum/unit_test/dq_hc_struct/magnet_repeat_stops_until_gate_changes/New()
	..()
	// The controller uses the persistent lazy view cache; initialize it before
	// the runner snapshots globals rather than deleting or resetting the cache.
	dview(0, test_floor())

/datum/unit_test/dq_hc_struct/magnet_repeat_stops_until_gate_changes/run_gate()
	var/obj/machinery/magnetic_controller/C = mach(/obj/machinery/magnetic_controller, tile(3, 2))
	C.rpath = list("invalid")
	C.speed = 10
	C.set_path_moving(TRUE)
	test_phase(KERNEL_PHASE_R) // drain the gate wake before measuring its interval
	test_time(0.1 SECONDS)
	TEST_ASSERT(C.path_stopped, "an invalid path stops the actual controller step")
	TEST_ASSERT(C.path_moving, "stopping retains the player's movement setting")
	C.pathpos = 55
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(C.pathpos, 55, "stopped work cannot keep revisiting and resetting the path")
	C.set_path_moving(FALSE)
	test_phase(KERNEL_PHASE_R) // make the separate off transition observable
	C.set_path_moving(TRUE)
	test_phase(KERNEL_PHASE_R) // drain the gate wake before measuring its interval
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(C.pathpos, 1, "a fresh gate transition runs the invalid path once again")
	TEST_ASSERT(C.path_stopped, "that new invalid step stops again")

/datum/unit_test/dq_hc_struct/camera_bug_click_round_trip
/datum/unit_test/dq_hc_struct/camera_bug_click_round_trip/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/camera/C = mach(/obj/machinery/camera, tile(3, 2))
	var/obj/item/camera_bug/B = allocate(/obj/item/camera_bug, H.loc)
	TEST_ASSERT(H.put_in_active_hand(B), "the operator holds the bug")
	TEST_ASSERT(C.can_use(), "the test starts with a usable camera")
	test_click(H, C, B)
	TEST_ASSERT(C.bugged, "the actual item click bugs the camera")
	test_click(H, C, B)
	TEST_ASSERT(!C.bugged, "a second item click removes its bug")
	C.set_status(FALSE)
	test_click(H, C, B)
	TEST_ASSERT(!C.bugged, "a nonfunctional camera refuses bug insertion")

/datum/unit_test/dq_hc_struct/power_hit_declarations
/datum/unit_test/dq_hc_struct/power_hit_declarations/run_gate()
	set_global("act_last_reply", GLOB.act_last_reply) // scoped restoration of hit dispatch scratch state
	var/obj/item/cell/C = allocate(/obj/item/cell, tile(3, 2))
	C.material_emp_resistance = 0
	C.charge = 1000
	C.emp_act(2)
	TEST_ASSERT_EQUAL(C.charge, 500, "the real EMP entry drains half an unprotected cell")
	var/obj/item/am_containment/J = allocate(/obj/item/am_containment, tile(4, 2))
	J.ex_act(3)
	TEST_ASSERT(!QDELETED(J), "a minor blast preserves the containment jar")
	TEST_ASSERT_EQUAL(J.stability, 80, "the hit replacement destabilizes the jar by its severity")

/datum/unit_test/dq_hc_struct/repeat_restarts_on_shared_settings
/datum/unit_test/dq_hc_struct/repeat_restarts_on_shared_settings/run_gate()
	var/obj/machinery/ai_slipper/S = mach(/obj/machinery/ai_slipper, tile(3, 2))
	S.uses = 0
	S.cooldown_time = world.timeofday
	S.set_cooldown_on(TRUE)
	test_phase(KERNEL_PHASE_R) // drain the gate wake before measuring its interval
	test_time(0.5 SECONDS)
	TEST_ASSERT(S.cooldown_stopped, "the exhausted repeat first stops")
	S.uses = 1
	S.set_density(!S.density)
	test_phase(KERNEL_PHASE_R) // the shared setting resets the stopped gate at this clock
	test_time(0.5 SECONDS)
	TEST_ASSERT(!S.cooldown_on, "a real density change restarts stopped legacy work")

/datum/unit_test/dq_hc_struct/doorbell_cancel_keeps_fingerprint
/datum/unit_test/dq_hc_struct/doorbell_cancel_keeps_fingerprint/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/button/doorbell/B = mach(/obj/machinery/button/doorbell, tile(3, 2))
	B.set_panel_open(TRUE)
	var/obj/item/pen/P = allocate(/obj/item/pen, H.loc)
	TEST_ASSERT(H.put_in_active_hand(P), "the operator holds the naming pen")
	var/original_name = B.name
	var/datum/forensics_crime/evidence = B.init_forensic_data()
	TEST_ASSERT(evidence.add_prints(H), "the actual human supplies genuine existing fingerprint evidence")
	var/list/original_prints = evidence.get_prints().Copy()
	var/datum/op_result/touch = test_click(H, B, P)
	TEST_ASSERT_EQUAL(touch?.key, "doorbell_rename", "the public item click selects the doorbell rename operation")
	TEST_ASSERT(asked(H), "the actual touch opens its rename question")
	TEST_ASSERT(length(B.forensic_data?.get_prints()), "opening the question preserves real fingerprint evidence")
	request_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT(!asked(H), "cancelling closes the actual question")
	TEST_ASSERT_EQUAL(B.name, original_name, "cancellation keeps the original name")
	var/list/remaining_prints = B.forensic_data?.get_prints()
	for(var/print in original_prints)
		TEST_ASSERT_EQUAL(remaining_prints?[print], original_prints[print], "cancellation preserves each genuine fingerprint")

/datum/unit_test/dq_hc_struct/gear_prompt_cancel_releases_busy
/datum/unit_test/dq_hc_struct/gear_prompt_cancel_releases_busy/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/gear_dispenser/D = mach(/obj/machinery/gear_dispenser, tile(3, 2))
	D.set_emagged(TRUE)
	for(var/key in D.dispenses)
		own(D.dispenses[key])
	TEST_ASSERT(length(D.dispenses), "the actual constructor supplies a nonempty gear catalog")
	var/flags_before = D.dispenser_flags
	test_click(H, D)
	TEST_ASSERT(asked(H), "the real dispenser opens its gear question")
	TEST_ASSERT(D.dispenser_flags != flags_before, "the open question acquires its busy flag")
	request_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT(!asked(H), "cancellation closes the question")
	TEST_ASSERT_EQUAL(D.dispenser_flags, flags_before, "cancellation releases exactly the temporary busy flag")
	test_click(H, D)
	TEST_ASSERT(asked(H), "the dispenser can be opened again after cancellation")
	request_answer(H, null, REQ_CANCELLED)

/datum/unit_test/dq_hc_struct/gear_answer_stays_busy_through_animation
/datum/unit_test/dq_hc_struct/gear_answer_stays_busy_through_animation/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/gear_dispenser/D = mach(/obj/machinery/gear_dispenser, tile(3, 2))
	D.set_emagged(TRUE)
	for(var/key in D.dispenses)
		own(D.dispenses[key])
	var/flags_before = D.dispenser_flags
	test_click(H, D)
	var/datum/prompt/choice/R = SSrequests.open_for(H)
	TEST_ASSERT(istype(R) && length(R.choices), "the actual dispenser offers a real gear choice")
	request_answer(H, R.choices[1])
	TEST_ASSERT(!asked(H), "the successful answer closes the question")
	TEST_ASSERT(D.dispenser_flags != flags_before, "answering retains the busy flag throughout dispensing")
	test_time(1 SECOND)
	TEST_ASSERT(D.dispenser_flags != flags_before, "the machine is still busy during the scan animation")
	test_time(4 SECONDS)
	TEST_ASSERT_EQUAL(D.dispenser_flags, flags_before, "the native completion timer releases busy only when the gear emerges")

/// Trusted AUTH_ADMIN exercises the canonical framework requirement, not a simulated native client.
/datum/unit_test/dq_hc_struct/jukebox_topic_artist_cancel_and_early_cancel
/datum/unit_test/dq_hc_struct/jukebox_topic_artist_cancel_and_early_cancel/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/media/jukebox/ghost/J = mach(/obj/machinery/media/jukebox/ghost, tile(3, 2))
	var/start = length(J.custom_tracks)
	var/datum/op_result/denied = own(op_topic_href(H, J, list("add_track" = "1"), namespace = VV_TOPIC))
	TEST_ASSERT_EQUAL(denied?.outcome, ACT_REFUSED, "a public VV link with no rights refuses before asking")
	TEST_ASSERT(!asked(H), "the actual refused dispatch opens no question")
	var/datum/op_result/early = own(op_perform_by_key(H, J, null, "vv_add_track", ORIGIN_UI, AUTH_ADMIN, FALSE))
	TEST_ASSERT_NULL(early?.outcome, "the actual URL question keeps the operation pending")
	TEST_ASSERT(asked(H), "the trusted framework op asks its URL step")
	request_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(length(J.custom_tracks), start, "cancelling the first question cannot create a track")
	var/datum/op_result/full = own(op_perform_by_key(H, J, null, "vv_add_track", ORIGIN_UI, AUTH_ADMIN, FALSE))
	TEST_ASSERT_NULL(full?.outcome, "the actual second workflow starts pending its answers")
	TEST_ASSERT(asked(H), "the second actual workflow opens")
	request_answer(H, "https://example.invalid/track")
	TEST_ASSERT(asked(H), "a real URL advances to the title question")
	request_answer(H, "Topic cancellation track")
	TEST_ASSERT(asked(H), "a real title advances to the duration question")
	request_answer(H, 10 SECONDS)
	TEST_ASSERT(asked(H), "a real duration advances to the optional artist question")
	TEST_ASSERT_EQUAL(length(J.custom_tracks), start, "the track is not created before the optional last answer")
	request_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT(!asked(H), "voluntary cancellation closes the final question")
	TEST_ASSERT_EQUAL(length(J.custom_tracks), start + 1, "only final artist cancellation creates the complete track once")
	var/datum/track/T = J.custom_tracks[length(J.custom_tracks)]
	TEST_ASSERT_EQUAL(T.title, "Topic cancellation track", "the completed track retains the actual title answer")
	TEST_ASSERT_EQUAL(T.url, "https://example.invalid/track", "the completed track retains the actual URL answer")

/datum/unit_test/dq_hc_struct/readylight_state_preserves_colour
/datum/unit_test/dq_hc_struct/readylight_state_preserves_colour/run_gate()
	var/obj/machinery/light/small/readylight/L = mach(/obj/machinery/light/small/readylight, tile(3, 2))
	TEST_ASSERT(L.set_state(1), "the concrete setter changes the saved rung")
	TEST_ASSERT_EQUAL(L.state, 1, "the light keeps its actual ready state")
	TEST_ASSERT_EQUAL(L.brightness_color, "00FF00", "the original light update runs after setting ready")
	TEST_ASSERT(L.set_state(0), "the concrete setter clears the ready state")
	TEST_ASSERT_EQUAL(L.state, 0, "the light returns to its actual idle state")
	TEST_ASSERT_EQUAL(L.brightness_color, initial(L.brightness_color), "clearing restores the original light colour")

/// The real common setter owns notification; the fixture contributes only a native emag capability.
/obj/machinery/dq_native_emag_storage
CAPABILITIES(/obj/machinery/dq_native_emag_storage)
	emag(powered = FALSE)
	on_change(PROC_REF(emagged), ANY, then(PROC_REF(emag_storage_changed)))
/obj/machinery/dq_native_emag_storage/var/emag_notifications = 0
/obj/machinery/dq_native_emag_storage/proc/emag_storage_changed(datum/act/A)
	emag_notifications++

/datum/unit_test/dq_hc_struct/emag_storage_round_trip
/datum/unit_test/dq_hc_struct/emag_storage_round_trip/run_gate()
	var/obj/machinery/plain = mach(/obj/machinery, tile(3, 2))
	TEST_ASSERT_NULL(cap_of(plain, CAP_EMAG), "the generic fixture actually has no native emag key")
	TEST_ASSERT(!plain.emagged(), "generic storage starts clean")
	TEST_ASSERT(plain.set_emagged(TRUE), "generic setter records a genuine legacy bit")
	TEST_ASSERT(capability_bits(plain) & CAP_EMAGGED, "generic storage owns the actual legacy capability bit")
	TEST_ASSERT(plain.emagged(), "generic getter observes the stored bit")
	TEST_ASSERT(!plain.set_emagged(TRUE), "unchanged generic writes do not republish")
	TEST_ASSERT(plain.set_emagged(FALSE), "generic setter clears actual storage")
	TEST_ASSERT(!plain.emagged(), "generic round trip returns clean")
	var/obj/machinery/dq_native_emag_storage/native = mach(/obj/machinery/dq_native_emag_storage, tile(4, 2))
	TEST_ASSERT(cap_of(native, CAP_EMAG), "native fixture actually declares its emag key")
	TEST_ASSERT(islist(GLOB.generated_reads_table) && length(GLOB.generated_reads_table), "the real generated dependency initializer populated its table at boot")
	TEST_ASSERT(islist(GLOB.generated_read_names) && length(GLOB.generated_read_names), "the generated dependency names were initialized at boot")
	var/list/emag_reads = change_read_keys(native, TYPE_PROC_REF(/obj/machinery, emagged))
	TEST_ASSERT("capkey:[EMAG_EMAGGED]" in emag_reads, "the getter subscribes to its actual local native capability key; actual=[json_encode(emag_reads)] expected=capkey:[EMAG_EMAGGED]")
	TEST_ASSERT(OP_KEY_CAP_STATE in emag_reads, "the getter also subscribes to its legacy capability-state key")
	native.set_emagged(TRUE)
	settle()
	TEST_ASSERT(emag_emagged(native), "native setter writes the actual key")
	TEST_ASSERT_EQUAL(native.emag_notifications, 1, "custom setter publishes its real state key once")
	cap_set(native, CAP_EMAGGED, TRUE)
	native.set_emagged(FALSE)
	settle()
	TEST_ASSERT(!emag_emagged(native), "clearing resets the native key")
	TEST_ASSERT(!(capability_bits(native) & CAP_EMAGGED), "clearing also resets a surviving legacy bit")
	TEST_ASSERT(!native.emagged(), "the unified getter stays cleared with both stores originally set")
	TEST_ASSERT_EQUAL(native.emag_notifications, 2, "clearing publishes the state key once")
	key_set(native, EMAG_EMAGGED, TRUE)
	settle()
	TEST_ASSERT_EQUAL(native.emag_notifications, 3, "a direct native key write notifies the unified getter")
	key_set(native, EMAG_EMAGGED, FALSE)
	settle()
	TEST_ASSERT_EQUAL(native.emag_notifications, 4, "a direct native key clear notifies the unified getter")
	cap_set(native, CAP_EMAGGED, TRUE)
	settle()
	TEST_ASSERT_EQUAL(native.emag_notifications, 5, "a direct legacy bit write notifies the same getter")
	cap_set(native, CAP_EMAGGED, FALSE)
	settle()
	TEST_ASSERT_EQUAL(native.emag_notifications, 6, "a direct legacy bit clear notifies the same getter")
	var/obj/machinery/deployable/barrier/barrier = mach(/obj/machinery/deployable/barrier, tile(5, 2))
	barrier.set_emagged(1)
	TEST_ASSERT_EQUAL(barrier.emagged, 1, "concrete barrier retains its first numeric damage stage")
	barrier.set_emagged(2)
	TEST_ASSERT_EQUAL(barrier.emagged, 2, "concrete barrier retains its distinct second numeric stage")

// Canonical power refusals through the public click resolver. Fixture conditions are
// established with existing setters; the busy branch starts real breaker work.
/datum/unit_test/dq_hc_struct/breaker_locked_click_refuses
/datum/unit_test/dq_hc_struct/breaker_locked_click_refuses/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/power/breakerbox/B = mach(/obj/machinery/power/breakerbox, tile(3, 2))
	B.set_update_locked(TRUE)
	var/old_on = B.on
	var/datum/op_result/R = test_click(H, B)
	TEST_ASSERT(R && (R.outcome & ACT_REFUSED), "a locked breaker refuses the public hand click")
	TEST_ASSERT_EQUAL(R.reason, MSG(breakerbox/locked), "the actual requirement returns the canonical locked reason")
	TEST_ASSERT_EQUAL(B.on, old_on, "refusal preserves the breaker state")
	TEST_ASSERT(!op_claimed(B) && !op_pending_of(H), "refusal starts no breaker work or target claim")

/datum/unit_test/dq_hc_struct/breaker_busy_click_refuses
/datum/unit_test/dq_hc_struct/breaker_busy_click_refuses/run_gate()
	var/mob/living/carbon/human/H = person()
	var/mob/living/carbon/human/other = person(tile(3, 3))
	var/obj/machinery/power/breakerbox/B = mach(/obj/machinery/power/breakerbox, tile(3, 2))
	var/old_on = B.on
	test_click(H, B)
	TEST_ASSERT(op_claimed(B) && op_pending_of(H), "the first public click starts actual breaker work and claims its target")
	var/datum/op_result/R = test_click(other, B)
	TEST_ASSERT(R && (R.outcome & ACT_REFUSED), "another actor is refused while the breaker is working")
	TEST_ASSERT_EQUAL(R.reason, /datum/msg/op/claimed, "native target contention returns the canonical claimed reason")
	TEST_ASSERT_EQUAL(B.on, old_on, "the refused click does not toggle the breaker")
	var/datum/pending_op/pending = op_pending_of(H)
	pending.cancel(/datum/msg/op/stopped)
	TEST_ASSERT(!op_claimed(B) && !op_pending_of(H), "cancellation releases both pending work and the target claim")

/datum/unit_test/dq_hc_struct/heavy_cable_rejects_normal_coil
/datum/unit_test/dq_hc_struct/heavy_cable_rejects_normal_coil/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/cable/heavyduty/C = allocate(/obj/structure/cable/heavyduty, tile(3, 2))
	var/obj/item/stack/cable_coil/W = allocate(/obj/item/stack/cable_coil, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(W), "the actor holds the actual normal coil")
	var/old_amount = W.amount
	var/old_d1 = C.d1
	var/old_d2 = C.d2
	var/datum/op_result/R = test_click(H, C, W)
	TEST_ASSERT(R && (R.outcome & ACT_REFUSED), "a normal coil cannot connect to heavy cable")
	TEST_ASSERT_EQUAL(R.reason, MSG(heavy_cable/needs_heavier), "the actual requirement names the needed heavier cable")
	TEST_ASSERT_EQUAL(W.amount, old_amount, "refusal spends no coil")
	TEST_ASSERT_EQUAL(C.d1, old_d1, "refusal preserves the first endpoint")
	TEST_ASSERT_EQUAL(C.d2, old_d2, "refusal preserves the second endpoint")

/datum/unit_test/dq_hc_struct/privacy_cooldown_click_refuses
/datum/unit_test/dq_hc_struct/privacy_cooldown_click_refuses/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/privacyswitch/S = allocate(/obj/structure/privacyswitch, tile(3, 2))
	S.set_use_cooldown(world.time + 5 MINUTES)
	var/area/here = get_area(S)
	var/old_flags = here.flags
	var/old_icon = S.icon_state
	var/datum/op_result/R = test_click(H, S)
	TEST_ASSERT(R && (R.outcome & ACT_REFUSED), "a cooling privacy switch refuses the public click")
	TEST_ASSERT_EQUAL(R.reason, MSG(privacy_switch/cooling_down), "the actual requirement returns the canonical cooldown reason")
	TEST_ASSERT_EQUAL(here.flags, old_flags, "refusal preserves the area's privacy")
	TEST_ASSERT_EQUAL(S.icon_state, old_icon, "refusal preserves the displayed state")
	TEST_ASSERT(!asked(H), "refusal opens no privacy question")

/datum/unit_test/dq_hc_struct/library_scanner_held_book_inserts
/datum/unit_test/dq_hc_struct/library_scanner_held_book_inserts/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/libraryscanner/S = mach(/obj/machinery/libraryscanner, tile(3, 2))
	var/obj/item/book/B = allocate(/obj/item/book, H.loc)
	TEST_ASSERT(H.put_in_active_hand(B), "the reader holds an actual book")
	var/datum/op_result/R = test_click(H, S, B)
	TEST_ASSERT_EQUAL(R?.key, "insert_book", "the held book selects insertion ahead of window opening")
	TEST_ASSERT_EQUAL(B.loc, S, "the actual book moves into the scanner")
	TEST_ASSERT(H.get_active_hand() != B, "the reader's actual hand releases the inserted book")

/datum/unit_test/dq_hc_struct/fire_alarm_held_item_triggers
/datum/unit_test/dq_hc_struct/fire_alarm_held_item_triggers/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/firealarm/F = mach(/obj/machinery/firealarm, tile(3, 2))
	var/obj/item/pen/P = allocate(/obj/item/pen, H.loc)
	TEST_ASSERT(H.put_in_active_hand(P), "the actor holds an ordinary non-tool item")
	TEST_ASSERT(!F.firewarn, "the real alarm starts quiet")
	var/datum/op_result/R = test_click(H, F, P)
	TEST_ASSERT_EQUAL(R?.key, "firealarm_trigger", "the held-item route precedes the empty-hand window route")
	TEST_ASSERT(F.firewarn, "the actual item touch raises the fire alarm")
	F.reset()

/datum/unit_test/dq_hc_struct/breaker_multitool_opens_tag_question
/datum/unit_test/dq_hc_struct/breaker_multitool_opens_tag_question/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/power/breakerbox/B = mach(/obj/machinery/power/breakerbox, tile(3, 2))
	var/obj/item/multitool/M = allocate(/obj/item/multitool, H.loc)
	TEST_ASSERT(H.put_in_active_hand(M), "the operator holds a real multitool")
	var/old_tag = B.RCon_tag
	var/old_on = B.on
	var/datum/op_result/R = test_click(H, B, M)
	TEST_ASSERT_EQUAL(R?.key, "breakerbox_use", "the multitool selects use rather than hand toggling")
	TEST_ASSERT(asked(H), "the actual use route opens the RCON naming question")
	test_answer(H, null, REQ_CANCELLED)
	TEST_ASSERT_EQUAL(B.RCon_tag, old_tag, "cancel keeps the tag")
	TEST_ASSERT_EQUAL(B.on, old_on, "the multitool never toggles power")
	TEST_ASSERT(!task_claiming(B), "it starts no hand reprogramming task")

/datum/unit_test/dq_hc_struct/single_item_menus_preserve_disabled_rows
/datum/unit_test/dq_hc_struct/single_item_menus_preserve_disabled_rows/run_gate()
	var/mob/living/carbon/human/H = person()
	var/list/cases = list(
		/obj/machinery/button = list("button_press_item", "needs an item"),
		/obj/machinery/button/doorbell = list("doorbell_rename", "needs an item"),
		/obj/machinery/power/breakerbox = list("breakerbox_use", "needs an item"),
		/obj/machinery/computer/aiupload = list("install_module", "needs an item"),
		/obj/machinery/computer/borgupload = list("install_module", "needs a AI module"),
		/obj/machinery/computer/teleporter = list("teleporter_computer_insert_card", "needs a data card"),
	)
	for(var/path in cases)
		var/list/expected = cases[path]
		var/obj/machinery/M = mach(path, tile(3, 2))
		var/list/found
		for(var/list/row as anything in op_menu(H, M, null))
			if(row["key"] == expected[1])
				found = row
		TEST_ASSERT_NOTNULL(found, "[path] retains its single-item menu row with an empty hand")
		TEST_ASSERT(!found?["enabled"], "that row is disabled without a held item")
		TEST_ASSERT_EQUAL(found?["reason"], expected[2], "the original refusal stays visible")
		qdel(M)

/datum/unit_test/dq_hc_struct/emag_menus_follow_integrator_policy
/datum/unit_test/dq_hc_struct/emag_menus_follow_integrator_policy/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/card/emag/card = allocate(/obj/item/card/emag, H.loc)
	card.uses = 0
	TEST_ASSERT(!card.can_emag(H), "the actual card is exhausted")
	var/list/types = list(/obj/machinery/computer/arcade/battle, /obj/machinery/computer/arcade/clawmachine, /obj/machinery/computer/arcade/orion_trail, /obj/machinery/computer/message_monitor, /obj/machinery/computer/prison_shuttle, /obj/machinery/computer/specops_shuttle, /obj/machinery/computer/supplycomp)
	for(var/path in types)
		var/obj/machinery/M = mach(path, tile(3, 2))
		for(var/obj/item/held as anything in list(null, card))
			if(held)
				TEST_ASSERT(H.put_in_active_hand(held), "the exhausted card is really held")
			var/list/found
			for(var/list/row as anything in op_menu(H, M, held))
				if(row["key"] == "emag.use")
					found = row
			if(held)
				TEST_ASSERT_NOTNULL(found, "the actual held sequencer reaches its item-bound op")
				TEST_ASSERT(!found?["enabled"], "an exhausted card cannot subvert the machine")
				TEST_ASSERT_EQUAL(found?["reason"], "That has no uses left.", "the real exhausted-card refusal is preserved")
			else
				TEST_ASSERT_NULL(found, "the integrator policy removes the legacy Emag row without a sequencer")
			if(held)
				H.drop_item()
		TEST_ASSERT(!M.emagged(), "menu inspection cannot subvert the machine")
		qdel(M)

/datum/unit_test/dq_hc_struct/robot_blocked_menu_preserves_physical_selection
/datum/unit_test/dq_hc_struct/robot_blocked_menu_preserves_physical_selection/run_gate()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, tile(2, 2))
	var/obj/machinery/button/B = mach(/obj/machinery/button, tile(3, 2))
	TEST_ASSERT(!R.is_remote_viewing(), "the actual keyless robot is not viewing through a camera")
	var/list/found
	for(var/list/row as anything in op_menu(R, B, null))
		if(row["key"] == "robot_remote_blocked")
			found = row
	TEST_ASSERT_NOTNULL(found, "the robot still sees the Blocked menu row")
	TEST_ASSERT(!found?["enabled"], "that row is disabled outside remote viewing")
	TEST_ASSERT_EQUAL(found?["reason"], "not possible right now", "the original disabled reason is preserved")
	var/datum/op_result/click = test_click(R, B)
	TEST_ASSERT(click?.key != "robot_remote_blocked", "offering the disabled menu row cannot swallow an ordinary physical click")
	var/mob/living/carbon/human/H = person()
	for(var/list/row as anything in op_menu(H, B, null))
		TEST_ASSERT(row["key"] != "robot_remote_blocked", "the robot-only row is never offered to a human")

/datum/unit_test/dq_hc_struct/cell_item_menu_preserves_disabled_row
/datum/unit_test/dq_hc_struct/cell_item_menu_preserves_disabled_row/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/item/cell/C = allocate(/obj/item/cell, tile(3, 2))
	var/list/found
	for(var/list/row as anything in op_menu(H, C, null))
		if(row["key"] == "inject_cell")
			found = row
	TEST_ASSERT_NOTNULL(found, "the single-item Use row remains visible with an empty hand")
	TEST_ASSERT(!found?["enabled"], "the item-use row cannot run without an item")
	TEST_ASSERT_EQUAL(found?["reason"], "needs an item", "the old item-use refusal is preserved")

/// Real machine operation and exact-refusal regressions for declarative requirements.
/datum/unit_test/dq_hc_struct/cablelayer_declarative_requirement
/datum/unit_test/dq_hc_struct/cablelayer_declarative_requirement/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/cablelayer/C = mach(/obj/machinery/cablelayer, tile(3, 2))
	var/obj/item/stack/cable_coil/original = rel_take(C, nameof(C.cable))
	own(original)
	C.set_on(FALSE)
	var/list/blocked = item_menu_row(H, C, null, "cablelayer_toggle")
	TEST_ASSERT(!blocked["enabled"], "empty, off layer refuses its actual toggle")
	TEST_ASSERT_EQUAL(blocked["reason"], "doesn't have any cable loaded", "the exact old refusal survives the disjunction")
	test_menu(H, C, "cablelayer_toggle")
	TEST_ASSERT(!C.on, "refused operation does not turn an empty layer on")
	C.set_on(TRUE)
	var/list/enabled = item_menu_row(H, C, null, "cablelayer_toggle")
	TEST_ASSERT(enabled["enabled"], "an empty running layer still offers turning off")
	test_menu(H, C, "cablelayer_toggle")
	TEST_ASSERT(!C.on, "actual operation turns the empty running layer off")
	rel_set(C, nameof(C.cable), original)
	test_menu(H, C, "cablelayer_toggle")
	TEST_ASSERT(C.on, "the owned cable object permits a real toggle on")

/datum/unit_test/dq_hc_struct/painter_declarative_requirement
/datum/unit_test/dq_hc_struct/painter_declarative_requirement/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/gear_painter/P = mach(/obj/machinery/gear_painter, tile(3, 2))
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(G), "actor holds the real offered garment")
	var/list/empty = item_menu_row(H, P, G, "gear_painter_insert")
	TEST_ASSERT(empty["enabled"], "working empty painter offers insertion")
	test_menu(H, P, "gear_painter_insert")
	TEST_ASSERT_EQUAL(P.inserted, G, "the real menu operation inserts the offered garment")
	var/obj/item/clothing/gloves/G2 = allocate(/obj/item/clothing/gloves, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(G2), "actor holds a second garment")
	var/list/loaded = item_menu_row(H, P, G2, "gear_painter_insert")
	TEST_ASSERT(!loaded["enabled"], "a loaded painter refuses the second garment")
	TEST_ASSERT_EQUAL(loaded["reason"], "the machine is already loaded", "the exact old loaded refusal is retained")
	test_menu(H, P, "gear_painter_insert")
	TEST_ASSERT_EQUAL(P.inserted, G, "refusal preserves the original insertion")
	TEST_ASSERT_EQUAL(H.get_active_hand(), G2, "refusal retains the offered garment in its actual hand")
	P.set_grid_power(FALSE)
	var/count = 0
	for(var/list/row as anything in op_menu(H, P, G2))
		if(row["key"] == "gear_painter_insert")
			count++
	TEST_ASSERT_EQUAL(count, 0, "unpowered painter selection falls through instead of displaying an enabled insert row")

/datum/unit_test/dq_hc_struct/bomb_tester_declarative_requirement
/datum/unit_test/dq_hc_struct/bomb_tester_declarative_requirement/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/bomb_tester/B = mach(/obj/machinery/bomb_tester, tile(3, 2))
	for(var/i in 1 to 2)
		var/obj/item/tank/oxygen/T = allocate(/obj/item/tank/oxygen, tile(2, 2))
		TEST_ASSERT(H.put_in_active_hand(T), "actor holds tank [i] for the actual input")
		var/list/row = item_menu_row(H, B, T, "load_tank")
		TEST_ASSERT(row["enabled"], "either empty declared tank relation permits selection [i]")
		test_menu(H, B, "load_tank")
		TEST_ASSERT_EQUAL(i == 1 ? B.tank1 : B.tank2, T, "the actual menu operation fills declared relation [i]")
	var/obj/item/tank/oxygen/third = allocate(/obj/item/tank/oxygen, tile(2, 2))
	TEST_ASSERT(H.put_in_active_hand(third), "actor offers a third tank")
	var/count = 0
	for(var/list/row as anything in op_menu(H, B, third))
		if(row["key"] == "load_tank")
			count++
	TEST_ASSERT_EQUAL(count, 0, "two full relations remove load selection rather than refusing a chosen load op")
	TEST_ASSERT_EQUAL(H.get_active_hand(), third, "menu selection never transfers the extra tank")
