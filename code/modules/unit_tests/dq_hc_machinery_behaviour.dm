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
	P.stat_add(NOPOWER)
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
		"/obj/machinery/doppler_array" = "",
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
		M.stat_remove(NOPOWER | BROKEN)
		TEST_ASSERT_EQUAL(hcs_window_keys(M, H), expected[type], "[type] sends the window data it always did")
