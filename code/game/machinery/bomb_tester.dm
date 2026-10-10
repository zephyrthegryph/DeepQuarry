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
	var/obj/machinery/portable_atmospherics/canister/test_canister

	var/sim_mode = BOMB_TESTER_MODE_SINGLE
	var/sim_canister_output = 10*ONE_ATMOSPHERE

	var/simulating = 0
	EXPIRY_DECLARE(simulation_started)
	/// after() timer that ends the running simulation, or 0.
	var/simulation_delay = 20 SECONDS

	var/simulation_results

	var/datum/gas_mixture/faketank
	var/faketank_integrity
TRACKED(/obj/machinery/bomb_tester, simulating)

CAPABILITIES(/obj/machinery/bomb_tester)
	default_parts()
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))
	owns_one(nameof(faketank), /datum/gas_mixture, starts = /datum/gas_mixture, starts_args = NO_LOC)
	interface("BombTester")
	op("set_mode", ui_act("set_mode", arg("mode", num(BOMB_TESTER_MODE_SINGLE, BOMB_TESTER_MODE_CANISTER))), then(PROC_REF(ui_act_set_mode)))
	op("add_tank", ui_act("add_tank", arg("slot", num())), then(PROC_REF(ui_act_add_tank)))
	op("remove_tank", ui_act("remove_tank", arg("ref")), then(PROC_REF(ui_act_remove_tank)))
	op("canister_scan", ui_act("canister_scan"), then(PROC_REF(ui_act_canister_scan)))
	op("set_can_pressure", ui_act("set_can_pressure", arg("pressure", num())), then(PROC_REF(ui_act_set_can_pressure)))
	op("start_sim", ui_act("start_sim"), then(PROC_REF(ui_act_start_sim)))
	extend(TAG_UI, needs(req(PROC_REF(not_simulating))))
	op("part_replacement", item(/obj/item/storage/part_replacer), priority(OP_PRIORITY_DEFAULT - 1), label("Replace parts"), then(TYPE_PROC_REF(/obj/machinery, op_part_replacement)))
	op("load_tank", item(/obj/item/tank), priority(OP_PRIORITY_DEFAULT - 1), label("Connect tank"), when(req(PROC_REF(tank_slot_available))), then(PROC_REF(interaction_load_tank)))
	op("open", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_open)))

/// Selection follows the two real occupied tank variables, including one empty slot.
/obj/machinery/bomb_tester/proc/tank_slot_available(datum/act/op/A)
	return !tank1 || !tank2 ? null : MSG(req_wrong_state)

MSG_DEF_SELF(bomb_tester/simulating, "The simulation is running.")

/// A simulation that is running takes no new settings.
/obj/machinery/bomb_tester/proc/not_simulating(datum/act/op/A)
	return (!simulating) ? null : MSG(bomb_tester/simulating)

/obj/machinery/bomb_tester/Initialize(mapload)
	. = ..()
	RefreshParts()

/obj/machinery/bomb_tester/dismantle()
	if(tank1)
		tank1.forceMove(get_turf(src))
		rel_take(src, nameof(tank1))
	if(tank2)
		tank2.forceMove(get_turf(src))
		rel_take(src, nameof(tank2))
	simulation_finish(1)
	return ..()

/obj/machinery/bomb_tester/proc/work_step(datum/act/timer/A)
	if(test_canister() && !Adjacent(test_canister()))
		rel_clear(src, nameof(test_canister))

/obj/machinery/bomb_tester/proc/appearance_suffix()
	return power_lost() ? "-p" : "[simulating]"

/obj/machinery/bomb_tester/proc/appearance_tank1()
	return tank1 ? 1 : 0

/obj/machinery/bomb_tester/proc/appearance_tank2()
	return tank2 ? 1 : 0

/// The look (the draw sweep: from its template and its layers).
/obj/machinery/bomb_tester/draw(datum/look/look)
	..()
	look.state("[icon_name][appearance_suffix()]")
	if(appearance_tank1() == 1)
		look.overlay("generic-tank1")
	if(appearance_tank2() == 1)
		look.overlay("generic-tank2")

/obj/machinery/bomb_tester/power_change()
	. = ..()
	if(simulating && power_lost())
		simulation_finish(1)

/obj/machinery/bomb_tester/RefreshParts()
	..()
	var/scan_rating = get_part_rating(/obj/item/stock_parts/scanning_module)
	simulation_delay = 25 SECONDS - scan_rating SECONDS

/obj/machinery/bomb_tester/proc/interaction_load_tank(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/adopted = tank1 ? move_into(src, nameof(src.tank2), I, user) : move_into(src, nameof(src.tank1), I, user)
	if(!adopted)
		return TRUE
	SStgui.update_uis(src)
	to_chat(user, span_notice("You connect \the [I] to \the [src]'s [I==tank1 ? "primary" : "secondary"] slot."))
	return TRUE

/obj/machinery/bomb_tester/proc/interaction_open(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/obj/machinery/bomb_tester/ui_data(datum/act/eval/A)
	var/list/data = list()

	if(!simulating)
		data["mode"] = sim_mode
		data["tank1"] = tank1
		data["tank1ref"] = REF(tank1)
		data["tank2"] = tank2
		data["tank2ref"] = REF(tank2)
		data["canister"] = test_canister()
		data["sim_canister_output"] = sim_canister_output

	data["simulating"] = simulating
	return data

/// The loaded tanks, for the UI's remove_tank refs.
/obj/machinery/bomb_tester/proc/tank_slots()
	return list(tank1, tank2)

/obj/machinery/bomb_tester/proc/ui_act_set_mode(datum/act/op/A, mode)
	var/mob/user = A.actor
	sim_mode = mode
	var/text_mode
	switch(sim_mode)
		if(BOMB_TESTER_MODE_SINGLE)
			text_mode = "single gas tank detonation"
		if(BOMB_TESTER_MODE_DOUBLE)
			text_mode = "tank transfer valve detonation"
		if(BOMB_TESTER_MODE_CANISTER)
			text_mode = "canister-assisted single gas tank detonation"
	to_chat(user, span_notice("[src] set to simulate a [text_mode]."))
	return TRUE

/obj/machinery/bomb_tester/proc/ui_act_add_tank(datum/act/op/A, raw_slot)
	var/mob/user = A.actor
	if(istype(user.get_active_hand(), /obj/item/tank))
		var/obj/item/tank/T = user.get_active_hand()
		var/slot = raw_slot
		var/slot_var
		if(slot == 1 && !tank1)
			slot_var = "tank1"
		else if(slot == 2 && !tank2)
			slot_var = "tank2"
		else
			to_chat(user, span_warning("Slot [slot] is full."))
			return

		move_into(src, slot_var, T, user)
		return TRUE
	else
		to_chat(user, span_warning("You must be wielding a tank to insert it!"))

/obj/machinery/bomb_tester/proc/ui_act_remove_tank(datum/act/op/A, raw_ref)
	var/obj/item/tank/T = ui_ref(raw_ref, tank_slots(), /obj/item/tank)
	if(istype(T))
		if(T == tank1)
			rel_take(src, nameof(/obj/machinery/bomb_tester::tank1))
		if(T == tank2)
			rel_take(src, nameof(/obj/machinery/bomb_tester::tank2))
		T.forceMove(get_turf(src))
	return TRUE

/obj/machinery/bomb_tester/proc/ui_act_canister_scan(datum/act/op/A)
	for(var/obj/machinery/portable_atmospherics/canister/C in orange(1,src))
		if(C && C == test_canister())
			continue
		else if(C)
			rel_set(src, nameof(/obj/machinery/bomb_tester::test_canister), C)
			break
		else
			rel_clear(src, nameof(/obj/machinery/bomb_tester::test_canister))
	return TRUE

/obj/machinery/bomb_tester/proc/ui_act_set_can_pressure(datum/act/op/A, pressure)
	sim_canister_output = CLAMP(pressure, ONE_ATMOSPHERE/10, ONE_ATMOSPHERE*10)
	return TRUE

/obj/machinery/bomb_tester/proc/ui_act_start_sim(datum/act/op/A)
	start_simulating()
	return TRUE

/obj/machinery/bomb_tester/proc/start_simulating()
	if(!tank1 || (sim_mode == BOMB_TESTER_MODE_DOUBLE && !tank2) || (sim_mode == BOMB_TESTER_MODE_CANISTER && !test_canister()))
		simulation_results = "Error"
		simulation_finish()
		return
	if((tank1?.air_contents.return_pressure() > TANK_RUPTURE_PRESSURE) || (tank2?.air_contents.return_pressure() > TANK_RUPTURE_PRESSURE))
		simulation_results = "Unstable"
		simulation_finish()
		return
	set_simulating(1)
	set_use_power(USE_POWER_ACTIVE)
	EXPIRY_STAMP(src, simulation_started, CLOCK_WORLD)
	after(src, simulation_delay, PROC_REF(simulation_timer_fired), key = "simulation")
	switch(sim_mode)
		if(BOMB_TESTER_MODE_SINGLE)
			single_tank_sim()

		if(BOMB_TESTER_MODE_DOUBLE)
			ttv_sim()

		if(BOMB_TESTER_MODE_CANISTER)
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

	heat_add(faketank, 15000, HEAT_SOURCE_OTHER)

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

/// The keyed timer: the simulation's run time is up.
/obj/machinery/bomb_tester/proc/simulation_timer_fired()
	if(simulating)
		simulation_finish()

/obj/machinery/bomb_tester/proc/simulation_finish(cancelled = 0)
	cancel_after(src, "simulation")
	set_simulating(0)
	set_use_power(USE_POWER_IDLE)
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
		P.set_info(simulation_results)

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

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/bomb_tester/step_start_condition()
	return simulating

/obj/machinery/bomb_tester/ownership()
	. = ..()
	. += owns(nameof(tank1), policy = OWN_CONTAINED)
	. += owns(nameof(tank2), policy = OWN_CONTAINED)

/// test canister (a relation view: it reads null once the target is deleted).
/obj/machinery/bomb_tester/proc/test_canister() as /obj/machinery/portable_atmospherics/canister
	return test_canister
