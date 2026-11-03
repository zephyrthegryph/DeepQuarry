// A mapped space-facing airlock cycled the way a player does it, on the real map (--full-map): the player stands in the chamber and presses
// "cycle_ext" on the controller's window; the chamber pumps down and the outer door opens, twice over. When each player starts suffocating
// is logged (information only: breathing's timing is tested in its own lane). The test waits on the wall clock: the injected test clock never runs the live
// items the map's controllers, vents and the player's Life armed at boot (doc/testing.md "The kernel clock").

/// Time a cycle may take before the test gives up on it.
#define DQ_CYCLE_E2E_LIMIT (150 SECONDS)
/// Chamber pressure (kPa) below which the air is unbreathable: oxygen far under the 16 kPa a human needs.
#define DQ_CYCLE_E2E_UNBREATHABLE_KPA 20

/// The mapped vent an airlock program pumps the chamber with.
/proc/dq_cycle_e2e_vent(datum/embedded_program/airlock/P)
	for(var/obj/machinery/atmospherics/unary/vent_pump/V in world)
		if(V.id_tag && V.id_tag == P.tag_airpump)
			return V

/// One line of what the cycle is doing: the program's state, the chamber and the vent pumping it.
/proc/dq_cycle_e2e_trace(datum/embedded_program/airlock/P, turf/chamber)
	var/obj/machinery/atmospherics/unary/vent_pump/V = dq_cycle_e2e_vent(P)
	var/obj/machinery/embedded_controller/C = P.master
	. = "state [P.state] -> [P.target_state], heard chamber [round(P.memory["chamber_sensor_pressure"], 0.1)] kPa target [round(P.memory["target_pressure"], 0.1)] \
		pump [P.memory["pump_status"]] purge [P.memory["purge"]]; chamber air [round(chamber?.return_air()?.return_pressure(), 0.1)] kPa; controller step [C?.processing_shown ? "on" : "off"] work [work_started(C) ? "started" : "stopped"]"
	if(V)
		. += "; vent [V.id_tag] power [V.use_power] direction [V.pump_direction] checks [V.pressure_checks] external [V.external_pressure_bound] internal [V.internal_pressure_bound] operable [V.operable()] pipe [round(V.air_contents?.return_pressure(), 0.1)] kPa"
	else
		. += "; no vent tagged [P.tag_airpump]"

/datum/unit_test/dq_airlock_cycle_end_to_end
	timeout = 300
	/// The player in the chamber.
	var/mob/living/carbon/human/player

/// The mapped space-facing airlocks: a plain cycling airlock controller whose chamber holds air and whose outside reads vacuum.
/datum/unit_test/dq_airlock_cycle_end_to_end/proc/space_airlocks()
	. = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C in world)
		if(istype(C, /obj/machinery/embedded_controller/radio/airlock/docking_port) || istype(C, /obj/machinery/embedded_controller/radio/airlock/docking_port_multi))
			continue
		var/datum/embedded_program/airlock/P = C.program
		if(!istype(P) || !C.operable())
			continue
		if(P.memory["external_sensor_pressure"] > 5 || P.memory["chamber_sensor_pressure"] < 80)
			continue
		if(!dq_cycle_e2e_vent(P) || !dq_cycle_e2e_door(P.tag_exterior_door) || !dq_cycle_e2e_chamber(P))
			continue
		. += C

/// The mapped door tagged `tag`.
/datum/unit_test/dq_airlock_cycle_end_to_end/proc/dq_cycle_e2e_door(tag)
	for(var/obj/machinery/door/airlock/D in world)
		if(D.id_tag && D.id_tag == tag)
			return D

/// The chamber floor: the turf of the program's chamber sensor.
/datum/unit_test/dq_airlock_cycle_end_to_end/proc/dq_cycle_e2e_chamber(datum/embedded_program/airlock/P)
	for(var/obj/machinery/airlock_sensor/S in world)
		if(S.id_tag == P.tag_chamber_sensor)
			return get_turf(S)

/datum/unit_test/dq_airlock_cycle_end_to_end/Run()
	capture_ambient() // before any time passes
	if(baseline?["solids"])
		defer_cleanup(null, GLOBAL_PROC_REF(unit_test_solid_restore), baseline["solids"])
	// The rooms' air alarms switch their vents on and off as minutes of world time drift the rooms (the telecomms rooms cool by themselves): put them back.
	for(var/obj/machinery/atmospherics/unary/vent_pump/V in world)
		defer_cleanup(V, TYPE_PROC_REF(/obj/machinery/atmospherics/unary/vent_pump, set_use_power), V.use_power)
	var/list/airlocks = space_airlocks()
	log_test("[length(airlocks)] space-facing mapped airlocks")
	if(!length(airlocks))
		log_test("this map has no space-facing airlock controller")
		return
	// Every one at once, a player in each chamber: one cycle is half a minute of world time.
	var/list/players = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
		var/datum/embedded_program/airlock/P = C.program
		var/turf/chamber = dq_cycle_e2e_chamber(P)
		for(var/turf/simulated/T in range(2, chamber))
			dq_atmos_test_snapshot_air(T) // the chamber and its doors' turfs: put back when the test ends
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, chamber)
		var/obj/item/card/id/I = allocate(/obj/item/card/id, chamber)
		I.set_access(SSaccess.get_all_accesses())
		H.equip_to_slot_or_del(I, SLOT_ID_ID)
		players[C] = H
		var/list/others = list()
		for(var/obj/machinery/atmospherics/unary/U in range(2, chamber))
			var/obj/machinery/atmospherics/unary/vent_pump/V = U
			if(istype(V) && V.id_tag == P.tag_airpump)
				continue
			others += "[U.type] [("id_tag" in U.vars) ? U.vars["id_tag"] : ""] at [U.x],[U.y] power [U.use_power][istype(V) ? " direction [V.pump_direction] external [V.external_pressure_bound] checks [V.pressure_checks]" : ""]"
		log_test("[P.id_tag] chamber [chamber.x],[chamber.y],[chamber.z] ([get_area(chamber)]): other atmos devices near it: [length(others) ? jointext(others, "; ") : "none"]")
	cycle_out(airlocks, players, 1)
	cycle_in(airlocks, players)

/// Every airlock cycled to the outside at once, its player in the chamber; asserts the outer doors open.
/datum/unit_test/dq_airlock_cycle_end_to_end/proc/cycle_out(list/airlocks, list/players, round)
	var/list/unbreathable_at = list()
	var/list/suffocating_at = list()
	var/list/opened_at = list()
	// The players breathe freely again before the round (the last round's oxygen alert is gone), or the logged timing would read the old alert.
	for(var/i in 1 to 30)
		var/gasping = 0
		for(var/C in players)
			var/mob/living/carbon/human/H = players[C]
			if(H.alerts?["oxy"])
				gasping++
		if(!gasping)
			break
		sleep(1 SECOND)
	for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
		var/datum/embedded_program/airlock/P = C.program
		var/mob/living/carbon/human/H = players[C]
		H.forceMove(dq_cycle_e2e_chamber(P))
		hc_ui(H, C, "cycle_ext")
	var/list/last_kpa = list()
	var/waited = 0
	while(waited < DQ_CYCLE_E2E_LIMIT && length(opened_at) < length(airlocks))
		sleep(1 SECOND)
		waited += 1 SECOND
		for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
			var/datum/embedded_program/airlock/P = C.program
			var/turf/chamber = dq_cycle_e2e_chamber(P)
			var/mob/living/carbon/human/H = players[C]
			var/kpa = chamber.return_air()?.return_pressure()
			if(!isnull(last_kpa[C]) && kpa - last_kpa[C] > 0.5 && P.state == 2)
				log_test("RISE [waited / (1 SECOND)] s [P.id_tag]: [round(last_kpa[C], 0.1)] -> [round(kpa, 0.1)] kPa while depressurizing; [dq_cycle_e2e_trace(P, chamber)]")
			last_kpa[C] = kpa
			if(isnull(unbreathable_at[C]) && kpa < DQ_CYCLE_E2E_UNBREATHABLE_KPA)
				unbreathable_at[C] = waited
			if(isnull(suffocating_at[C]) && H.alerts?["oxy"])
				suffocating_at[C] = waited
			if(isnull(opened_at[C]) && !dq_cycle_e2e_door(P.tag_exterior_door).density)
				opened_at[C] = waited
		if(waited % (10 SECONDS) == 0)
			for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
				if(isnull(opened_at[C]))
					var/datum/embedded_program/airlock/P = C.program
					log_test("[waited / (1 SECOND)] s [P.id_tag]: [dq_cycle_e2e_trace(P, dq_cycle_e2e_chamber(P))]")
	var/list/stuck = list()
	var/list/late_breath = list()
	for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
		var/datum/embedded_program/airlock/P = C.program
		var/u = unbreathable_at[C]
		var/s = suffocating_at[C]
		log_test("round [round] [P.id_tag] ([C.type]) at [C.x],[C.y],[C.z]: outer door [isnull(opened_at[C]) ? "never opened" : "open at [opened_at[C] / (1 SECOND)] s"], unbreathable at [isnull(u) ? "never" : "[u / (1 SECOND)] s"], suffocating at [isnull(s) ? "never" : "[s / (1 SECOND)] s"]")
		if(isnull(opened_at[C]))
			stuck += "[P.id_tag] ([dq_cycle_e2e_trace(P, dq_cycle_e2e_chamber(P))])"
		if(!isnull(u) && (isnull(s) || s - u > LIFE_CYCLE + 1 SECOND)) // the next breath comes within one Life cycle; the test looks once a second
			late_breath += "[P.id_tag] (unbreathable at [u / (1 SECOND)] s, suffocating at [isnull(s) ? "never" : "[s / (1 SECOND)] s"])"
	TEST_ASSERT(!length(stuck), "round [round]: [length(stuck)] of [length(airlocks)] airlocks never opened their outer door in [DQ_CYCLE_E2E_LIMIT / (1 SECOND)] s: [jointext(stuck, "; ")]")
	if(length(late_breath)) // breathing's timing is another lane's (event-driven breaths); logged here as information only
		log_test("round [round]: [length(late_breath)] players started suffocating more than one Life cycle after their chamber's air went unbreathable: [jointext(late_breath, "; ")]")

/// Every airlock cycled back in (the chambers hold air again), its player at the controller.
/datum/unit_test/dq_airlock_cycle_end_to_end/proc/cycle_in(list/airlocks, list/players)
	for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
		var/mob/living/carbon/human/H = players[C]
		H.forceMove(get_turf(C))
		var/datum/embedded_program/airlock/P = C.program
		P.receive_user_command("abort")
		hc_ui(H, C, "cycle_int")
	var/waited = 0
	while(waited < DQ_CYCLE_E2E_LIMIT)
		var/busy = 0
		for(var/obj/machinery/embedded_controller/radio/airlock/C as anything in airlocks)
			var/datum/embedded_program/airlock/P = C.program
			if(!P.done_cycling())
				busy++
		if(!busy)
			break
		sleep(1 SECOND)
		waited += 1 SECOND
	log_test("cycled back in after [waited / (1 SECOND)] s")

#undef DQ_CYCLE_E2E_LIMIT
#undef DQ_CYCLE_E2E_UNBREATHABLE_KPA
