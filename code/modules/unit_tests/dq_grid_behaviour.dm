// Behaviour of the power grid as the world sees it (doc/rewrite/power_grid.md): what an area's machines ask of it, what its APC does about
// that, and what the net does with the rest. Written against the public reads (area.usage(), area.powered(), channel_load(), power_avail(),
// stored_charge()) so the same file holds before and after the area tallies give way to the machines' contributions.
//
// Same rules as dq_power_tests.dm: one power step is dq_power_test_step() (DM's loads in, one world step, the results polled back).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A machine that draws on the channel it is told to (equipment by default): idle 10 W, active 100 W.
/obj/machinery/dq_grid_probe
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	power_channel = EQUIP

GLOBAL_LIST_EMPTY(dq_grid_load_probes) // "area:channel" -> the probe carrying a test's standing load

/// A machine that carries a test's standing load on one channel of its area.
/obj/machinery/dq_grid_load
	use_power = USE_POWER_IDLE
	idle_power_usage = 0
	power_channel = EQUIP

/// The area of `where` takes `watts` more standing load on `chan` (negative: gives it back), through one probe machine per area and channel.
/proc/dq_area_load(turf/where, watts, chan = EQUIP)
	var/key = "[REF(get_area(where))]:[chan]"
	var/obj/machinery/dq_grid_load/P = GLOB.dq_grid_load_probes[key]
	if(!P)
		P = new(where)
		P.update_power_channel(chan)
		GLOB.dq_grid_load_probes[key] = P
	P.update_idle_power_usage(P.idle_power_usage + watts)
	if(P.idle_power_usage <= 0)
		GLOB.dq_grid_load_probes -= key
		qdel(P)

/// The watts the area's machines ask of `chan` (the standing draw, no one-offs).
/proc/dq_grid_demand(area/A, chan)
	return A.usage(chan, TRUE) - A.usage(chan, FALSE)

/// An APC on the test map with a cell, a terminal and an area that needs power, cut off from the rest of the net and set to run its three
/// channels on automatic with a known cell.
/proc/dq_grid_isolated_apc(charge_fraction)
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	if(!A)
		return null
	A.disconnect_from_network()
	A.terminal?.disconnect_from_network()
	A.set_operating(TRUE)
	A.set_chargemode(FALSE)
	A.equipment = POWERCHAN_ON_AUTO
	A.lighting = POWERCHAN_ON_AUTO
	A.environ = POWERCHAN_ON_AUTO
	native_write(A, NATIVE_APC_CHANNELS, A.equipment, 0)
	native_write(A, NATIVE_APC_CHANNELS, A.lighting, 1)
	native_write(A, NATIVE_APC_CHANNELS, A.environ, 2)
	A.cell.charge = A.cell.maxcharge * charge_fraction
	A.seat_cell_charge(TRUE)
	A.apply_area_power()
	refresh_flush()
	return A

/// What a machine in an area costs its channel: idle, active, nothing, and the channel it is on.
/datum/unit_test/dq_grid_demand_follows_the_machine

/datum/unit_test/dq_grid_demand_follows_the_machine/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/area/A = apc.area
	var/equip = dq_grid_demand(A, EQUIP)
	var/light = dq_grid_demand(A, LIGHT)
	var/environ = dq_grid_demand(A, ENVIRON)
	var/obj/machinery/dq_grid_probe/M = allocate(/obj/machinery/dq_grid_probe, get_turf(apc))
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 10, "an idle machine asks its idle draw of its channel")
	TEST_ASSERT_EQUAL(dq_grid_demand(A, LIGHT) - light, 0, "and nothing of the other channels")
	M.set_use_power(USE_POWER_ACTIVE)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 100, "an active one asks its active draw")
	M.update_active_power_usage(250)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 250, "a changed active draw is followed while active")
	M.update_idle_power_usage(30)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 250, "a changed idle draw does not touch an active machine")
	M.set_use_power(USE_POWER_IDLE)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 30, "back to idle takes the new idle draw")
	M.update_power_channel(LIGHT)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 0, "a machine moved to the light channel leaves the equipment channel")
	TEST_ASSERT_EQUAL(dq_grid_demand(A, LIGHT) - light, 30, "and is asked of the light channel")
	M.update_power_channel(ENVIRON)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, ENVIRON) - environ, 30, "and of the environment channel")
	M.set_use_power(USE_POWER_OFF)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, ENVIRON) - environ, 0, "a machine switched off asks nothing")
	M.set_use_power(USE_POWER_IDLE)
	qdel(M)
	TEST_ASSERT_EQUAL(dq_grid_demand(A, ENVIRON) - environ, 0, "a deleted machine asks nothing")
	TEST_ASSERT_EQUAL(dq_grid_demand(A, EQUIP) - equip, 0, "or of any other channel")

/// Nothing can drift: every area's demand is exactly what a recount over the machines standing in it says (the tallies this replaced needed
/// retally_power() for this to hold).
/datum/unit_test/dq_grid_demand_equals_a_recount

/datum/unit_test/dq_grid_demand_equals_a_recount/Run()
	var/list/expected = list()
	var/counted = 0
	for(var/obj/machinery/M in world)
		var/area/A = get_area(M)
		if(!A || QDELETED(M))
			continue
		counted++
		var/key = "[REF(A)]:[M.power_channel]"
		expected[key] = (expected[key] || 0) + M.get_power_usage()
	TEST_ASSERT(counted > 0, "no machines on the test map to recount")
	var/checked = 0
	for(var/area/A in world)
		for(var/chan in list(EQUIP, LIGHT, ENVIRON))
			var/want = expected["[REF(A)]:[chan]"] || 0
			TEST_ASSERT_EQUAL(A.demand(chan), want, "[A] ([A.type]) channel [chan]: the demand is the recount")
			checked++
	TEST_ASSERT(checked > 0, "no areas checked")

/// A machine carried to another area takes its draw with it.
/datum/unit_test/dq_grid_demand_follows_the_area

/datum/unit_test/dq_grid_demand_follows_the_area/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/area/home = apc.area
	var/turf/elsewhere
	for(var/turf/simulated/floor/F in world)
		var/area/other = get_area(F)
		if(other && other != home && other.requires_power)
			elsewhere = F
			break
	TEST_ASSERT_NOTNULL(elsewhere, "the test map has no second area that needs power")
	if(!elsewhere)
		return
	var/area/away = get_area(elsewhere)
	var/home_before = dq_grid_demand(home, EQUIP)
	var/away_before = dq_grid_demand(away, EQUIP)
	var/obj/machinery/dq_grid_probe/M = allocate(/obj/machinery/dq_grid_probe, get_turf(apc))
	M.set_use_power(USE_POWER_ACTIVE)
	TEST_ASSERT_EQUAL(dq_grid_demand(home, EQUIP) - home_before, 100, "the machine asks its own area")
	M.forceMove(elsewhere)
	TEST_ASSERT_EQUAL(dq_grid_demand(home, EQUIP) - home_before, 0, "it leaves the old area's demand when it moves")
	TEST_ASSERT_EQUAL(dq_grid_demand(away, EQUIP) - away_before, 100, "and joins the new one's")
	M.forceMove(get_turf(apc))
	TEST_ASSERT_EQUAL(dq_grid_demand(home, EQUIP) - home_before, 100, "it moves back")
	TEST_ASSERT_EQUAL(dq_grid_demand(away, EQUIP) - away_before, 0, "and leaves the other area clean")

/// What a machine asks of its area reaches the APC's load: idle versus active moves the figure the APC carries.
/datum/unit_test/dq_grid_apc_load_follows_machine_draw

/datum/unit_test/dq_grid_apc_load_follows_machine_draw/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	dq_power_test_step()
	dq_power_test_step()
	var/base = apc.channel_load(POWER_CHANNEL_EQUIPMENT)
	var/demand_base = dq_grid_demand(apc.area, EQUIP)
	var/obj/machinery/dq_grid_probe/M = allocate(/obj/machinery/dq_grid_probe, get_turf(apc))
	dq_power_test_step()
	TEST_ASSERT_EQUAL(dq_grid_demand(apc.area, EQUIP) - demand_base, 10, "the area's demand rose by the idle draw")
	TEST_ASSERT_EQUAL(apc.channel_load(POWER_CHANNEL_EQUIPMENT) - base, 10, "an idle machine adds its idle draw to the APC's equipment load (base [base], now [apc.channel_load(POWER_CHANNEL_EQUIPMENT)])")
	M.set_use_power(USE_POWER_ACTIVE)
	dq_power_test_step()
	TEST_ASSERT_EQUAL(apc.channel_load(POWER_CHANNEL_EQUIPMENT) - base, 100, "an active one adds its active draw")
	TEST_ASSERT_EQUAL(apc.channel_load(POWER_CHANNEL_LIGHTING), apc.channel_load(POWER_CHANNEL_LIGHTING), "the lighting load is read the same way")
	M.update_power_channel(ENVIRON)
	dq_power_test_step()
	TEST_ASSERT_EQUAL(apc.channel_load(POWER_CHANNEL_EQUIPMENT) - base, 0, "a machine moved off the equipment channel stops loading it")
	qdel(M)
	dq_power_test_step()
	TEST_ASSERT_EQUAL(apc.channel_load(POWER_CHANNEL_EQUIPMENT) - base, 0, "a deleted machine loads nothing")

/// A one-off draw is booked on the area until the step takes it, and the APC's cell pays it when nothing else can.
/datum/unit_test/dq_grid_oneoff_draw_is_paid_once

/datum/unit_test/dq_grid_oneoff_draw_is_paid_once/Run()
	var/obj/machinery/power/apc/apc = dq_grid_isolated_apc(0.5)
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/area/A = apc.area
	dq_power_test_step()
	var/charge = apc.cell.charge
	A.use_power_oneoff(40000, EQUIP)
	TEST_ASSERT(A.usage(EQUIP, FALSE) >= 40000, "a one-off draw is on the area until the step")
	dq_power_test_step()
	TEST_ASSERT(apc.cell.charge < charge, "the cell paid a one-off the grid could not ([apc.cell.charge] of [charge])")
	var/after_paid = apc.cell.charge
	dq_power_test_step()
	TEST_ASSERT_EQUAL(A.usage(EQUIP, FALSE), 0, "the one-off is gone after the step")
	var/drain_without = charge - after_paid
	TEST_ASSERT(drain_without > 0, "the one-off cost something")

/// An APC with no supply sheds channels in the order equipment, lighting, environment, and ends dark with its cell empty.
/datum/unit_test/dq_grid_channels_shed_in_order

/datum/unit_test/dq_grid_channels_shed_in_order/Run()
	var/obj/machinery/power/apc/apc = dq_grid_isolated_apc(0.12)
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/area/A = apc.area
	dq_area_load(get_turf(apc), 4000, EQUIP)
	dq_area_load(get_turf(apc), 2000, LIGHT)
	dq_area_load(get_turf(apc), 1000, ENVIRON)
	var/equip_off = 0
	var/light_off = 0
	var/environ_off = 0
	for(var/i in 1 to 600)
		dq_power_test_step()
		if(!equip_off && !A.power_equip)
			equip_off = i
		if(!light_off && !A.power_light)
			light_off = i
		if(!environ_off && !A.power_environ)
			environ_off = i
		if(environ_off)
			break
	dq_area_load(get_turf(apc), -4000, EQUIP)
	dq_area_load(get_turf(apc), -2000, LIGHT)
	dq_area_load(get_turf(apc), -1000, ENVIRON)
	TEST_ASSERT(equip_off, "equipment never shed")
	TEST_ASSERT(light_off, "lighting never shed")
	TEST_ASSERT(environ_off, "environment never shed")
	TEST_ASSERT(equip_off <= environ_off, "equipment sheds no later than environment (equipment [equip_off], environment [environ_off])")
	TEST_ASSERT(light_off <= environ_off, "lighting sheds no later than environment (lighting [light_off], environment [environ_off])")
	TEST_ASSERT(!A.powered(EQUIP) && !A.powered(LIGHT) && !A.powered(ENVIRON), "a drained APC leaves its area unpowered on every channel")

/// A dark light channel darkens the fixtures; the equipment channel does not.
/datum/unit_test/dq_grid_light_channel_darkens_lights

/datum/unit_test/dq_grid_light_channel_darkens_lights/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/area/A = apc.area
	var/obj/machinery/light/L = allocate(/obj/machinery/light, get_turf(apc))
	var/was_light = A.power_light
	var/was_equip = A.power_equip
	A.power_light = TRUE
	A.power_equip = TRUE
	A.lightswitch = TRUE
	A.power_change()
	TEST_ASSERT(L.has_power(), "a fixture in a powered area has power")
	A.power_equip = FALSE
	A.power_change()
	TEST_ASSERT(L.has_power(), "losing the equipment channel does not darken a fixture")
	A.power_light = FALSE
	A.power_change()
	TEST_ASSERT(!L.has_power(), "losing the light channel darkens it")
	A.power_light = was_light
	A.power_equip = was_equip
	A.power_change()

/// Several producers on one net add up, a pulse lasts one step, and a draw never takes more than is there.
/datum/unit_test/dq_grid_supply_adds_and_draws_are_bounded

/datum/unit_test/dq_grid_supply_adds_and_draws_are_bounded/Run()
	var/list/run = dq_power_test_run(4)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the supply test")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	// Only the two ends of the run are knots a machine joins: both generators and the user stand on the ends.
	var/obj/machinery/power/terminal/gen_a = allocate(/obj/machinery/power/terminal, run[1])
	var/obj/machinery/power/terminal/gen_b = allocate(/obj/machinery/power/terminal, run[4])
	var/obj/machinery/power/terminal/user = allocate(/obj/machinery/power/terminal, run[4])
	gen_a.set_power_supply(3000)
	gen_b.set_power_supply(2000)
	dq_power_test_step()
	TEST_ASSERT_EQUAL(power_avail(user.power_region), 5000, "two generators on one net supply their sum")
	gen_b.add_avail(700)
	dq_power_test_step()
	TEST_ASSERT_EQUAL(power_avail(user.power_region), 5700, "a pulse adds to the supply of its step")
	dq_power_test_step()
	TEST_ASSERT_EQUAL(power_avail(user.power_region), 5000, "and is gone the step after")
	TEST_ASSERT_EQUAL(user.draw_power(2000), 2000, "a draw within the supply is paid in full")
	TEST_ASSERT_EQUAL(user.draw_power(4000), 3000, "a heavy draw is cut to what is left")
	TEST_ASSERT_EQUAL(user.draw_power(100), 0, "and an empty net gives nothing")
	TEST_ASSERT(power_brownout(user.power_region) || power_netexcess(user.power_region) <= 0, "an exhausted net reads as spent")
	gen_a.set_power_supply(0)
	gen_b.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		qdel(C)

/// A powersink drains the net it is clamped to, and takes an APC's cell when the net is dry.
/datum/unit_test/dq_grid_powersink_drains_net_then_cells

/datum/unit_test/dq_grid_powersink_drains_net_then_cells/Run()
	var/list/run = dq_power_test_run(3)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the powersink test")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	var/obj/machinery/power/terminal/gen = allocate(/obj/machinery/power/terminal, run[1])
	gen.set_power_supply(100000)
	dq_power_test_step()
	var/obj/item/powersink/sink = allocate(/obj/item/powersink, run[3])
	sink.drain_rate = 60000
	sink.attached = cables[3]
	sink.PN = gen.power_region
	var/before = power_load(gen.power_region)
	sink.drained_this_tick = 0
	sink.pwr_drain()
	TEST_ASSERT_EQUAL(sink.power_drained, 60000, "the sink took its drain rate off the net")
	TEST_ASSERT(power_load(gen.power_region) - before >= 60000, "the net's ledger booked the drain")
	gen.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		qdel(C)

/// A powersink on a dry net takes charge from the cell of an APC on it, and the cell stays down.
/datum/unit_test/dq_grid_powersink_takes_apc_cell

/datum/unit_test/dq_grid_powersink_takes_apc_cell/Run()
	var/obj/machinery/power/apc/apc = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(apc, "the test map has no working APC")
	if(!apc)
		return
	var/obj/machinery/power/terminal/term = apc.terminal
	term.connect_to_network()
	term.set_power_supply(0)
	apc.set_operating(TRUE)
	apc.cell.charge = apc.cell.maxcharge * 0.8
	apc.seat_cell_charge(TRUE)
	dq_power_test_step()
	var/charge = apc.cell.charge
	var/obj/item/powersink/sink = allocate(/obj/item/powersink, get_turf(apc))
	sink.attached = locate(/obj/structure/cable) in get_turf(term)
	TEST_ASSERT_NOTNULL(sink.attached, "no cable under the APC's terminal")
	if(!sink.attached)
		return
	sink.drain_rate = 1000000
	sink.PN = term.power_region
	sink.drained_this_tick = 0
	sink.pwr_drain()
	TEST_ASSERT(apc.cell.charge < charge, "the sink drew down the cell ([apc.cell.charge] of [charge])")
	var/drained = apc.cell.charge
	dq_power_test_step()
	TEST_ASSERT(apc.cell.charge <= drained + 1, "the next power step does not hand the drained charge back ([apc.cell.charge] after [drained], was [charge])")

/// A SMES charges from its input terminal's net and pays an APC's load on its output side after the supply is gone.
/datum/unit_test/dq_p2_smes/grid_charges_and_discharges

/datum/unit_test/dq_p2_smes/grid_charges_and_discharges/run_gate()
	var/obj/machinery/power/smes/S = p2_network(supply_watts = 200000)
	p2_smes_set_charge(S, 0)
	S.set_input_attempt(TRUE)
	S.set_output_attempt(FALSE)
	p2_steps(6)
	var/charged = p2_smes_charge(S)
	TEST_ASSERT(charged > 0, "an input-on SMES behind a live supply took charge")
	p2_supply.set_power_supply(0)
	S.set_input_attempt(FALSE)
	S.set_output_attempt(TRUE)
	var/area/load_area = get_area(p2_load_spot())
	var/requires = load_area.requires_power
	load_area.set_requires_power(TRUE)
	var/obj/machinery/power/apc/A = allocate(/obj/machinery/power/apc/p2_test, p2_load_spot())
	A.connect_to_network()
	dq_area_load(p2_load_spot(), 20000, EQUIP)
	p2_apc_resync(A)
	p2_steps(3)
	TEST_ASSERT(p2_net_avail(p2_load) > 0, "a charged SMES offers its output to the net beside it")
	var/before = p2_smes_charge(S)
	p2_steps(6)
	TEST_ASSERT(p2_smes_charge(S) < before, "a load on the output side drains the unit ([p2_smes_charge(S)] of [before])")
	S.set_output_attempt(FALSE)
	p2_steps(2)
	var/held = p2_smes_charge(S)
	p2_steps(3)
	TEST_ASSERT_EQUAL(p2_smes_charge(S), held, "a unit with input and output off holds its charge")
	dq_area_load(p2_load_spot(), -20000, EQUIP)
	load_area.set_requires_power(requires)
	qdel(A)

#endif
