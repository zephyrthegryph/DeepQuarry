// Station power as a player meets it: a power storage unit of the real mapped types (not the p2_test stand-ins) opens its window on a click through the
// input inbox, draws its charge and flow lamps, feeds the network its terminal is on and takes charge from a network with surplus; and on the whole of
// Southern Cross (run with --full-map) the solar arrays that start with the round generate more than the idle station asks.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A buildable unit set up as the map's "precharged" ones are (2 MJ, input on; that map subtype is not in the test-map build), recording who its
/// window was opened for (a test mob has no client to open it for).
/obj/machinery/power/smes/buildable/dq_sp_probe
	initial_charge = 2e6
	input_attempt = TRUE
	var/list/sp_opened

/obj/machinery/power/smes/buildable/dq_sp_probe/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	LAZYADD(sp_opened, user)
	return ..()

/// One line of what the unit is now, for the failure messages and the log.
/datum/unit_test/dq_p2_smes/proc/sp_describe(obj/machinery/power/smes/S)
	return "[S.type] unwired=[S.unwired] working=[S.working] broken=[S.broken_now()] region=[S.power_region] entity=[!!S.vg_entity] charge=[S.stored_charge()]/[S.capacity] in=[S.input_attempt]@[S.input_level] out=[S.output_attempt]@[S.output_level] inputting=[S.inputting] outputting=[S.outputting] terminals=[LAZYLEN(S.terminals)]"

/// A click through the inbox, as a player's, and the window it opened.
/datum/unit_test/dq_p2_smes/proc/sp_click(mob/living/carbon/human/H, obj/machinery/power/smes/buildable/dq_sp_probe/S)
	hci_click(H, S, null)
	p2_settle()
	return (H in S.sp_opened)

/datum/unit_test/dq_p2_smes/sp_precharged_click_opens_window

/datum/unit_test/dq_p2_smes/sp_precharged_click_opens_window/run_gate()
	var/obj/machinery/power/smes/buildable/dq_sp_probe/S = p2_smes(/obj/machinery/power/smes/buildable/dq_sp_probe)
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(sp_click(H, S), "a click opens the precharged unit's window: [sp_describe(S)]")

/// An admin-spawned unit has no terminal anywhere near it: it still opens its window.
/datum/unit_test/dq_p2_smes/sp_spawned_bare_click_opens_window

/datum/unit_test/dq_p2_smes/sp_spawned_bare_click_opens_window/run_gate()
	var/obj/machinery/power/smes/buildable/dq_sp_probe/S = p2_bare_smes(/obj/machinery/power/smes/buildable/dq_sp_probe)
	var/mob/living/carbon/human/H = p2_actor()
	TEST_ASSERT(sp_click(H, S), "a click opens a spawned unit's window: [sp_describe(S)]")

/// The look: output lamp, input lamp and the charge gauge are drawn from what the unit is doing, and the draw is current after the state changed.
/datum/unit_test/dq_p2_smes/sp_precharged_draws_charge_and_flow

/datum/unit_test/dq_p2_smes/sp_precharged_draws_charge_and_flow/run_gate()
	var/obj/machinery/power/smes/S = p2_network(/obj/machinery/power/smes/buildable/dq_sp_probe, supply_watts = 500000)
	p2_steps(5)
	refresh_flush()
	draw_flush()
	var/list/keys = p2_smes_overlay_keys(S)
	TEST_ASSERT(keys[1] != "", "the output lamp is drawn: [sp_describe(S)]")
	TEST_ASSERT(keys[2] != "", "the input lamp is drawn: [sp_describe(S)]")
	TEST_ASSERT(text2num(keys[3]) > 0, "the charge gauge is drawn: [sp_describe(S)]")
	TEST_ASSERT(draw_is_current(S), "what the unit shows is what a draw of it makes")
	TEST_ASSERT_EQUAL(S.inputting, 2, "charging from the supply: [sp_describe(S)]")

/// Output on: the network its terminal's neighbours are on has power, and an APC on it is carried.
/datum/unit_test/dq_p2_smes/sp_precharged_feeds_an_apc

/datum/unit_test/dq_p2_smes/sp_precharged_feeds_an_apc/run_gate()
	var/obj/machinery/power/smes/S = p2_network(/obj/machinery/power/smes/buildable/dq_sp_probe, supply_watts = 0)
	var/area/load_area = get_area(p2_load_spot())
	capture_ambient()
	keep_area_power(load_area)
	var/requires = load_area.requires_power
	load_area.set_requires_power(TRUE)
	load_area.power_change()
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, p2_load_spot())
	A.connect_to_network()
	p2_apc_load(A, 20000)
	p2_apc_resync(A)
	var/before = p2_smes_charge(S)
	for(var/i in 1 to 20)
		p2_smes_power_step()
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "the unit's network has power: [sp_describe(S)]")
	TEST_ASSERT(p2_smes_charge(S) < before - 100, "the load draws the unit down ([before] to [p2_smes_charge(S)]): [sp_describe(S)]")
	TEST_ASSERT_EQUAL(A.main_status, APC_EXTERNAL_POWER_GOOD, "the APC is on the unit's power: [sp_describe(S)]")
	p2_apc_load(A, -20000)
	load_area.set_requires_power(requires)
	load_area.power_change()
	qdel(A)

/// A network with surplus charges a unit whose input is on, and the unit's flow readings say so.
/datum/unit_test/dq_p2_smes/sp_precharged_charges_from_surplus

/datum/unit_test/dq_p2_smes/sp_precharged_charges_from_surplus/run_gate()
	var/obj/machinery/power/smes/S = p2_network(/obj/machinery/power/smes/buildable/dq_sp_probe, supply_watts = 500000)
	TEST_ASSERT(S.input_attempt, "a precharged unit starts with its input on")
	var/before = p2_smes_charge(S)
	p2_steps(5)
	TEST_ASSERT(p2_smes_charge(S) > before + 100, "the charge rose ([before] to [p2_smes_charge(S)]): [sp_describe(S)]")

// ---------------------------------------------------------------------------------------------------------------------
// The station
// ---------------------------------------------------------------------------------------------------------------------

/// Round start power on Southern Cross: what every storage unit and solar array is as the map loads it, the arrays set going the way the round start does
/// it, and generation against what the idle station asks. Needs --full-map (a test map has no arrays and the test passes empty).
/datum/unit_test/dq_station_power_budget

/datum/unit_test/dq_station_power_budget/Run()
	var/list/controls = REGISTRY_COPY(REGISTRY_SOLAR_CONTROLS)
	if(length(controls) < 3)
		return // not the station
	// The storage units as the map loads them.
	var/units = 0
	for(var/obj/machinery/power/smes/S as anything in REGISTRY_COPY(REGISTRY_SMES))
		units++
		log_world("SP_CENSUS: [S] ([S.x],[S.y],[S.z]) [S.type] unwired=[S.unwired] working=[S.working] region=[S.power_region] entity=[!!S.vg_entity] charge=[S.stored_charge()]/[S.capacity] in=[S.input_attempt]@[S.input_level] out=[S.output_attempt]@[S.output_level] terminals=[LAZYLEN(S.terminals)]")
		TEST_ASSERT(!S.unwired, "[S] at ([S.x],[S.y],[S.z]) has its terminal")
		TEST_ASSERT(S.working, "[S] at ([S.x],[S.y],[S.z]) works")
		TEST_ASSERT(S.power_region, "[S] at ([S.x],[S.y],[S.z]) is on a network")
	TEST_ASSERT(units >= 8, "the station's storage units are in the registry ([units])")
	// Round start, as the ticker does it.
	for(var/obj/machinery/power/solar_control/SC as anything in controls)
		SC.auto_start()
	SSsolars.update_solars(0) // the system's own pass over the arrays (it runs every minute)
	for(var/i in 1 to 30)
		dq_power_test_step()
	var/started = 0
	var/generation = 0
	var/delivered = 0 // what the storage unit behind each running array can put on the station's network
	for(var/obj/machinery/power/solar_control/SC as anything in controls)
		var/panels = length(SC.get_connected_panels())
		log_world("SP_ARRAY: [SC.name] id=[SC.id] track=[SC.track] tracker=[!!SC.connected_tracker()] panels=[panels] cdir=[SC.cdir] power=[SC.connected_power] supply=[SC.power_supply_rate] region=[SC.power_region]")
		if(SC.track == 2 && panels && SC.connected_power > 0)
			started++
			generation += SC.connected_power
			for(var/obj/machinery/power/smes/S as anything in REGISTRY_COPY(REGISTRY_SMES))
				for(var/obj/machinery/power/terminal/term as anything in S.terminals)
					if(term.power_region == SC.power_region)
						delivered += min(S.output_level, SC.connected_power)
						log_world("SP_ARRAY: [SC.name] charges [S] (in [S.input_level] W, out [S.output_level] W)")
	// What the idle station asks of its supply.
	var/demand = 0
	for(var/area/A in world)
		if(!A.apc || !A.requires_power || !(A.z in using_map.station_levels))
			continue
		var/area_demand = A.demand(EQUIP) + A.demand(LIGHT) + A.demand(ENVIRON)
		demand += area_demand
		if(area_demand >= 5000)
			log_world("SP_DEMAND: [A] [area_demand] W (equipment [A.demand(EQUIP)], lighting [A.demand(LIGHT)], environment [A.demand(ENVIRON)])")
	log_world("SP_BUDGET: round-start solar generation [generation] W (deliverable through the arrays' storage units [delivered] W) against idle station demand [demand] W")
	TEST_ASSERT(started >= 3, "three of the four arrays run at the start of the round ([started])")
	TEST_ASSERT(delivered >= demand, "the arrays' storage units can put out the idle demand ([delivered] W against [demand] W)")
	TEST_ASSERT(generation >= demand, "round-start solar generation ([generation] W) covers the idle station's demand ([demand] W)")

#endif
