#define MODE_SINGLE 1
#define MODE_DOUBLE 2
#define MODE_CANISTER 3

/obj/machinery/bomb_tester
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "explosive effect simulator"
	desc = "A device that can calculate the potential explosive yield of provided gases."
	icon = 'icons/obj/machines/bomb_tester_vr.dmi'
	icon_state = "generic"
	anchored = TRUE
	density = TRUE
	idle_power_usage = 50
	active_power_usage = 1.5 KILOWATTS

	circuit = /obj/item/circuitboard/bomb_tester

	var/icon_name = "generic"

	var/obj/item/tank/tank1
	var/obj/item/tank/tank2
	var/test_canister_handle

	var/sim_mode = MODE_SINGLE
	var/sim_canister_output = 10*ONE_ATMOSPHERE

	var/simulating = 0
	EXPIRY_DECLARE(simulation_started)
	/// om_after() timer that ends the running simulation, or 0.
	var/tmp/simulation_timer = 0
	var/simulation_delay = 20 SECONDS

	var/simulation_results

	var/datum/gas_mixture/faketank
	var/faketank_integrity

/obj/machinery/bomb_tester/Initialize(mapload)
	. = ..()
	default_apply_parts()
	RefreshParts()
	faketank = new

/obj/machinery/bomb_tester/dismantle()
	if(tank1)
		tank1.forceMove(get_turf(src))
		tank1 = null
	if(tank2)
		tank2.forceMove(get_turf(src))
		tank2 = null
	simulation_finish(1)
	return ..()

/obj/machinery/bomb_tester/machine_step()
	..()
	if(test_canister() && !Adjacent(test_canister()))
		test_canister_handle = null

/obj/machinery/bomb_tester/update_icon()
	cut_overlays()
	if(tank1)
		add_overlay("[icon_name]-tank1")
	if(tank2)
		add_overlay("[icon_name]-tank2")
	if(has_stat(NOPOWER))
		icon_state = "[icon_name]-p"
	else
		icon_state = "[icon_name][simulating]"

/obj/machinery/bomb_tester/power_change()
	. = ..()
	update_icon()
	if(simulating && has_stat(NOPOWER))
		simulation_finish(1)

/obj/machinery/bomb_tester/RefreshParts()
	..()
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module)
	simulation_delay = 25 SECONDS - scan_rating SECONDS

/obj/machinery/bomb_tester/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/bomb_tester_load_tank,
		/datum/interaction/machine_hand/ungated/bomb_tester_open,
	)
	..()

/datum/interaction/machine_item/bomb_tester_load_tank
	id = "bomb_tester_load_tank"
	name = "Connect tank"
	held_type = /obj/item/tank
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/bomb_tester/proc/has_free_tank_slot, null))
	effect = /obj/machinery/bomb_tester/proc/interaction_load_tank

/obj/machinery/bomb_tester/proc/has_free_tank_slot(mob/actor, atom/target, obj/item/held)
	return !tank1 || !tank2

/obj/machinery/bomb_tester/proc/interaction_load_tank(mob/user, obj/item/I, datum/interaction/interaction)
	user.drop_item(I)
	I.forceMove(src)
	if(!tank1)
		tank1 = I
	else
		tank2 = I
	update_icon()
	SStgui.update_uis(src)
	to_chat(user, span_notice("You connect \the [I] to \the [src]'s [I==tank1 ? "primary" : "secondary"] slot."))
	return TRUE

/datum/interaction/machine_hand/ungated/bomb_tester_open
	id = "bomb_tester_open"
	name = "Use"
	effect = /obj/machinery/bomb_tester/proc/interaction_open

/obj/machinery/bomb_tester/proc/interaction_open(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/bomb_tester, "BombTester")

UI_DATA(/obj/machinery/bomb_tester, "simulating:num", "merge:ui_data_obj_machinery_bomb_tester{mode:unknown,tank1:unknown,tank1ref:text,tank2:unknown,tank2ref:text,canister:unknown,sim_canister_output:num}")

/// The computed part of /obj/machinery/bomb_tester's window data (declared on its UI_DATA row).
/obj/machinery/bomb_tester/proc/ui_data_obj_machinery_bomb_tester(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(!simulating)
		data["mode"] = sim_mode
		data["tank1"] = tank1
		data["tank1ref"] = REF(tank1)
		data["tank2"] = tank2
		data["tank2ref"] = REF(tank2)
		data["canister"] = test_canister()
		data["sim_canister_output"] = sim_canister_output

	return data

/// The loaded tanks, for the UI's remove_tank refs.
/obj/machinery/bomb_tester/proc/tank_slots()
	return list(tank1, tank2)

/obj/machinery/bomb_tester/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(simulating)
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/bomb_tester, "set_mode", ui_act_set_mode, UI_ARG_NUM("mode", MODE_SINGLE, MODE_CANISTER))
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_set_mode)
	sim_mode = params["mode"]
	var/text_mode
	switch(sim_mode)
		if(MODE_SINGLE)
			text_mode = "single gas tank detonation"
		if(MODE_DOUBLE)
			text_mode = "tank transfer valve detonation"
		if(MODE_CANISTER)
			text_mode = "canister-assisted single gas tank detonation"
	to_chat(ui.user, span_notice("[src] set to simulate a [text_mode]."))
	return TRUE

UI_ACT(/obj/machinery/bomb_tester, "add_tank", ui_act_add_tank, UI_ARG_NUM("slot"))
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_add_tank)
	if(istype(ui.user.get_active_hand(), /obj/item/tank))
		var/obj/item/tank/T = ui.user.get_active_hand()
		var/slot = params["slot"]
		if(slot == 1 && !tank1)
			tank1 = T
		else if(slot == 2 && !tank2)
			tank2 = T
		else
			to_chat(ui.user, span_warning("Slot [slot] is full."))
			return

		ui.user.drop_item(T)
		T.forceMove(src)
		return TRUE
	else
		to_chat(ui.user, span_warning("You must be wielding a tank to insert it!"))

UI_ACT(/obj/machinery/bomb_tester, "remove_tank", ui_act_remove_tank, UI_ARG_REF("ref", "proc:tank_slots", /obj/item/tank))
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_remove_tank)
	var/obj/item/tank/T = params["ref"]
	if(istype(T))
		if(T == tank1)
			tank1 = null
		if(T == tank2)
			tank2 = null
		T.forceMove(get_turf(src))
		update_icon()
	return TRUE

UI_ACT(/obj/machinery/bomb_tester, "canister_scan", ui_act_canister_scan)
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_canister_scan)
	for(var/obj/machinery/portable_atmospherics/canister/C in orange(1,src))
		if(C && C == test_canister())
			continue
		else if(C)
			test_canister_handle = om_handle(C)
			break
		else
			test_canister_handle = null
	return TRUE

UI_ACT(/obj/machinery/bomb_tester, "set_can_pressure", ui_act_set_can_pressure, UI_ARG_NUM("pressure"))
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_set_can_pressure)
	sim_canister_output = CLAMP(params["pressure"], ONE_ATMOSPHERE/10, ONE_ATMOSPHERE*10)
	return TRUE

UI_ACT(/obj/machinery/bomb_tester, "start_sim", ui_act_start_sim)
UI_ACT_PROC(/obj/machinery/bomb_tester, ui_act_start_sim)
	start_simulating()
	return TRUE

/obj/machinery/bomb_tester/proc/start_simulating()
	if(!tank1 || (sim_mode == MODE_DOUBLE && !tank2) || (sim_mode == MODE_CANISTER && !test_canister()))
		simulation_results = "Error"
		simulation_finish()
		return
	if((tank1?.air_contents.return_pressure() > TANK_RUPTURE_PRESSURE) || (tank2?.air_contents.return_pressure() > TANK_RUPTURE_PRESSURE))
		simulation_results = "Unstable"
		simulation_finish()
		return
	simulating = 1
	set_use_power(USE_POWER_ACTIVE)
	EXPIRY_STAMP(src, simulation_started, CLOCK_WORLD)
	simulation_timer = om_after(src, simulation_delay, PROC_REF(simulation_timer_fired))
	update_icon()
	switch(sim_mode)
		if(MODE_SINGLE)
			single_tank_sim()

		if(MODE_DOUBLE)
			ttv_sim()

		if(MODE_CANISTER)
			canister_sim()

/obj/machinery/bomb_tester/proc/simulate_tank() //This is a heavily cut down version of check_status() from tanks.dm
	faketank.react()
	var/pressure = faketank.return_pressure()
	if(pressure > TANK_FRAGMENT_PRESSURE)
		if(faketank_integrity <= 7)
			faketank.react()
			faketank.react()
			faketank.react()
			pressure = faketank.return_pressure()

			var/strength = (pressure-TANK_FRAGMENT_PRESSURE)/TANK_FRAGMENT_SCALE
			var/mult = ((faketank.return_volume()/140)**(1/2)) * (faketank.total_moles()**(2/3))/((29*0.64) **(2/3)) //Don't ask me what this is, see tanks.dm

			var/dev = round((mult*strength)*0.15)
			var/heavy = round((mult*strength)*0.35)
			var/light = round((mult*strength)*0.80)
			simulation_results += "<hr>Final Result: Explosive tank rupture. [dev?"Extreme damage within [2*dev] meters. ":""][heavy?"Heavy damage within [2*heavy] meters. ":""][light?"Light damage within [2*light] meters. ":""]Hazardous shrapnel produced."
			return 1
		else
			faketank_integrity -= 7

	else if(pressure > TANK_RUPTURE_PRESSURE)
		faketank.react()
		if(faketank_integrity <= 0)
			simulation_results += "<hr>Final Result: Tank rupture, minimal concussive force. Hazardous shrapnel produced."
			return 1
		else
			faketank_integrity -= 5

	else if(pressure > TANK_LEAK_PRESSURE || faketank.return_temperature() - T0C > 173)
		faketank_integrity -= 1
	return 0

/obj/machinery/bomb_tester/proc/single_tank_sim()
	faketank.set_volume(tank1.volume)
	faketank.copy_from(tank1.air_contents)
	faketank_integrity = tank1.get_integrity() / 10 // The sim counts the seal in its old 20-point scale.

	simulation_results = "<center><h1><b>Single Tank Ignition Test</b></h1></center>"
	simulation_results += "<hr>"

	simulation_results += "<br>Initial gas tank status:<br>[format_gas_for_results(faketank)]"

	faketank.add_thermal_energy(15000)

	var/intervals = 0
	while(intervals < 10)
		intervals++
		simulation_results += "<hr>[intervals*2] seconds after ignition."
		if(simulate_tank())
			break
		simulation_results += "<br>Gas tank status:<br>[format_gas_for_results(faketank)]"

	if(intervals == 10)
		simulation_results += "<hr>Final Result: No detonation."

/obj/machinery/bomb_tester/proc/ttv_sim()
	faketank.set_volume(tank1.air_contents.return_volume() + tank2.air_contents.return_volume())
	faketank.copy_from(tank1.air_contents)
	faketank_integrity = tank1.get_integrity() / 10 // The sim counts the seal in its old 20-point scale.
	faketank.merge(tank2.air_contents)

	simulation_results = "<center><h1><b>Tank Transfer Valve Mixture Test</b></h1></center>"
	simulation_results += "<hr>"

	simulation_results += "<br>Initial gas tank status (primary slot):<br>[format_gas_for_results(tank1.air_contents)]"
	simulation_results += "<br>Initial gas tank status (secondary slot):<br>[format_gas_for_results(tank2.air_contents)]"
	simulation_results += "<br>Initial gas mixture status:<br>[format_gas_for_results(faketank)]"

	var/intervals = 0
	while(intervals < 10)
		intervals++
		simulation_results += "<hr>[intervals*2] seconds after combining."
		if(simulate_tank())
			break
		simulation_results += "<br>Gas mixture status:<br>[format_gas_for_results(faketank)]"

	if(intervals == 10)
		simulation_results += "<hr>Final Result: No detonation."

/obj/machinery/bomb_tester/proc/canister_sim()
	test_canister().anchored = TRUE
	faketank.set_volume(tank1.air_contents.return_volume())
	faketank.copy_from(tank1.air_contents)
	faketank_integrity = tank1.get_integrity() / 10 // The sim counts the seal in its old 20-point scale.

	var/datum/gas_mixture/fakecanister = new
	fakecanister.set_volume(test_canister().air_contents.return_volume())
	fakecanister.copy_from(test_canister().air_contents)
	var/fakecanister_RFL = test_canister().release_flow_rate

	simulation_results = "<center><h1><b>Canister-Assisted Single Tank Ignition Test</b></h1></center>"
	simulation_results += "<hr>"

	simulation_results += "<br>Initial gas tank status:<br>[format_gas_for_results(faketank)]"

	var/intervals = 0
	while(intervals < 10)
		intervals++
		simulation_results += "<hr>[intervals*2] seconds after combining."
		var/pressure_delta = sim_canister_output - faketank.return_pressure()
		if(pressure_delta > 0)
			var/transfer_moles = calculate_transfer_moles(fakecanister, faketank, pressure_delta)
			transfer_moles = min(transfer_moles, (fakecanister_RFL/fakecanister.return_volume())*fakecanister.total_moles())
			pump_gas_passive(src, fakecanister, faketank, transfer_moles)
		if(simulate_tank())
			break
		simulation_results += "<br>Gas tank status:<br>[format_gas_for_results(faketank)]"

	if(intervals == 10)
		simulation_results += "<hr>Final Result: No detonation."

/// om_after() callback: the simulation's run time is up.
/obj/machinery/bomb_tester/proc/simulation_timer_fired()
	simulation_timer = 0
	if(simulating)
		simulation_finish()

/obj/machinery/bomb_tester/proc/simulation_finish(cancelled = 0)
	if(simulation_timer)
		om_cancel_timer(src, simulation_timer)
		simulation_timer = 0
	simulating = 0
	set_use_power(USE_POWER_IDLE)
	update_icon()
	if(test_canister() && test_canister().anchored && !test_canister().connected_port())
		test_canister().anchored = FALSE
	if(cancelled)
		return
	if(simulation_results == "Error")
		play_sfx(src, SFX_MACHINES_BUZZ_SIGH)
		state("Invalid parameters.")
	else if(simulation_results == "Unstable")
		play_sfx(src, SFX_MACHINES_BUZZ_TWO)
		state("Tank instability detected. Please step away from the device.")
	else
		ping("Simulation complete!")
		playsound(src, "sound/machines/printer.ogg", 50, 1)
		var/obj/item/paper/P = new(get_turf(src))
		P.name = "Explosive Simulator printout"
		P.info = simulation_results

/obj/machinery/bomb_tester/proc/format_gas_for_results(datum/gas_mixture/G)
	// G.update_values() removed; no-op under LINDA.
	var/results = ""
	var/pressure = G.return_pressure()

	results += "Pressure: [round(pressure,0.1)] kPa"
	if(G.total_moles())
		results += "<br>Temperature: [round(G.return_temperature()-T0C)]&deg;C"
		// was iterating XGM `G.gas`; under LINDA use gas_ids().
		for(var/mix in G.gas_ids())
			results += "<br>[GLOB.gas_data.name[mix]]: [round((LINDA_GAS_AMT(G, mix) / G.total_moles()) * 100)]%"

	return results

#undef MODE_SINGLE
#undef MODE_DOUBLE
#undef MODE_CANISTER

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/bomb_tester/step_start_condition()
	return simulating

DECLARE_REF(/obj/machinery/bomb_tester, "tank1", HELD, null)
DECLARE_REF(/obj/machinery/bomb_tester, "tank2", HELD, null)
DECLARE_REF(/obj/machinery/bomb_tester, "faketank", OWNED, null)

/// LC-refs: test canister -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/bomb_tester/proc/test_canister() as /obj/machinery/portable_atmospherics/canister
	return om_resolve(test_canister_handle)
