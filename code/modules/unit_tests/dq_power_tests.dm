// M3 power tests (doc/rewrite/simulation.md §6): the Rust cable network and
// ledger as DM sees them. Rust-side conservation and ledger tests live in
// verdigris/domains/power/src/tests.rs.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A straight east-west run of `count` floor turfs with no cable or power
/// machine on it or beside it, so test cables join nothing else.
/proc/dq_power_test_run(count)
	for(var/turf/simulated/floor/start in world)
		var/list/run = list()
		var/turf/cur = start
		for(var/i in 1 to count)
			if(!istype(cur, /turf/simulated/floor) || !dq_power_test_clear(cur))
				break
			run += cur
			cur = get_step(cur, EAST)
		if(length(run) != count)
			continue
		var/ok = TRUE
		for(var/turf/T as anything in run + list(get_step(start, WEST), cur))
			for(var/direction in list(0, NORTH, SOUTH))
				var/turf/near = direction ? get_step(T, direction) : T
				if(near && !dq_power_test_clear(near))
					ok = FALSE
		if(ok)
			return run
	return null

/proc/dq_power_test_clear(turf/T)
	if(!T)
		return TRUE
	if(locate(/obj/structure/cable) in T)
		return FALSE
	if(locate(/obj/machinery/power) in T)
		return FALSE
	return TRUE

/proc/dq_power_test_cable(turf/T, d1, d2)
	var/obj/structure/cable/C = new(T)
	C.d1 = d1
	C.d2 = d2
	C.power_register()
	return C

/// Knot - wire - ... - wire - knot along `run`.
/proc/dq_power_test_line(list/run)
	var/list/cables = list()
	var/last = length(run)
	for(var/i in 1 to last)
		var/turf/T = run[i]
		if(i == 1)
			cables += dq_power_test_cable(T, 0, EAST)
		else if(i == last)
			cables += dq_power_test_cable(T, 0, WEST)
		else
			cables += dq_power_test_cable(T, EAST, WEST)
	return cables

/// Cutting a cable splits the network; repairing it merges them again.
/datum/unit_test/dq_power_cut_splits_and_repair_merges

/datum/unit_test/dq_power_cut_splits_and_repair_merges/Run()
	var/list/run = dq_power_test_run(5)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the cable test")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	var/obj/machinery/power/terminal/left = allocate(/obj/machinery/power/terminal, run[1])
	var/obj/machinery/power/terminal/right = allocate(/obj/machinery/power/terminal, run[5])
	SSmachines.process_power()
	TEST_ASSERT_NOTNULL(left.powernet, "the left machine is not on the cable")
	TEST_ASSERT(left.powernet == right.powernet, "one cable run is two networks")
	var/datum/powernet/before = left.powernet

	qdel(cables[3])
	SSmachines.process_power()
	TEST_ASSERT_NOTNULL(left.powernet, "the left side lost its network")
	TEST_ASSERT_NOTNULL(right.powernet, "the right side lost its network")
	TEST_ASSERT(left.powernet != right.powernet, "a cut cable still joins the two sides")
	TEST_ASSERT(left.powernet == before || right.powernet == before, "neither side kept the network's identity")

	right.set_power_supply(1000)
	SSmachines.process_power()
	TEST_ASSERT_EQUAL(left.powernet.avail, 0, "supply crossed the cut")
	TEST_ASSERT_EQUAL(left.draw_power(100), 0, "a draw crossed the cut")

	cables[3] = dq_power_test_cable(run[3], EAST, WEST)
	SSmachines.process_power()
	TEST_ASSERT(left.powernet == right.powernet, "a repaired cable did not merge the networks")
	TEST_ASSERT_EQUAL(left.powernet.avail, 1000, "the merged network does not carry the supply")
	TEST_ASSERT_EQUAL(left.draw_power(600), 600, "a draw on the merged network failed")
	TEST_ASSERT_EQUAL(left.draw_power(600), 400, "a draw exceeded the supply left")
	right.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		qdel(C)

/datum/unit_test/dq_power_apc_cycle
	var/lost_signals = 0
	var/restored_signals = 0

/datum/unit_test/dq_power_apc_cycle/proc/on_lost(datum/source)
	SIGNAL_HANDLER
	lost_signals++

/datum/unit_test/dq_power_apc_cycle/proc/on_restored(datum/source)
	SIGNAL_HANDLER
	restored_signals++

/proc/dq_power_test_apc()
	for(var/obj/machinery/power/apc/candidate as anything in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(candidate.terminal && candidate.cell && candidate.area?.requires_power && !(candidate.stat & (BROKEN | MAINT)) && isturf(candidate.loc))
			return candidate
	return null

/// An APC drains its cell, browns its area out (the machinery power-lost
/// signal), restores when supply returns (power-restored) and charges.
/datum/unit_test/dq_power_apc_cycle/Run()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	if(!A)
		return
	var/obj/machinery/power/terminal/T = A.terminal
	var/old_charge = A.cell.charge
	var/obj/machinery/M = allocate(/obj/machinery, get_turf(A))
	RegisterSignal(M, COMSIG_MACHINERY_POWER_LOST, PROC_REF(on_lost))
	RegisterSignal(M, COMSIG_MACHINERY_POWER_RESTORED, PROC_REF(on_restored))
	M.power_change()

	// Cut off, nearly empty, with a load.
	T.disconnect_from_network()
	A.area.use_power_static(2000, EQUIP)
	A.operating = TRUE
	A.chargemode = TRUE
	A.equipment = POWERCHAN_ON_AUTO
	A.lighting = POWERCHAN_ON_AUTO
	A.environ = POWERCHAN_ON_AUTO
	A.cell.charge = A.cell.maxcharge * 0.001
	A.update()
	var/drained = FALSE
	for(var/i in 1 to 20)
		SSmachines.process_power()
		if(!A.area.power_equip)
			drained = TRUE
			break
	TEST_ASSERT(drained, "an empty isolated APC kept its area powered")
	TEST_ASSERT(M.stat & NOPOWER, "a machine in the dark area still has power")
	TEST_ASSERT(lost_signals, "the machine never heard COMSIG_MACHINERY_POWER_LOST")
	TEST_ASSERT(A.charging == 0, "an isolated APC claims to charge")
	var/low = A.cell.charge

	// Supply returns.
	T.connect_to_network()
	T.set_power_supply(1000000)
	var/restored = FALSE
	for(var/i in 1 to 80)
		SSmachines.process_power()
		if(A.area.power_equip && A.charging)
			restored = TRUE
			break
	TEST_ASSERT(restored, "the APC did not restore and charge once supply returned")
	TEST_ASSERT(!(M.stat & NOPOWER), "the machine did not get its power back")
	TEST_ASSERT(restored_signals, "the machine never heard COMSIG_MACHINERY_POWER_RESTORED")
	SSmachines.process_power()
	TEST_ASSERT(A.cell.charge > low, "the cell did not charge ([A.cell.charge] after [low])")
	TEST_ASSERT(!(A in SSmachines.processing_machines), "the APC polled during the cycle")

	T.set_power_supply(0)
	A.area.use_power_static(-2000, EQUIP)
	A.cell.charge = old_charge
	A.update()
	UnregisterSignal(M, list(COMSIG_MACHINERY_POWER_LOST, COMSIG_MACHINERY_POWER_RESTORED))
	SSmachines.process_power()

/// A settled APC and an idle SMES neither poll nor hear from Rust.
/datum/unit_test/dq_power_idle_apc_and_smes_sleep

/datum/unit_test/dq_power_idle_apc_and_smes_sleep/Run()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	if(!A)
		return
	var/obj/machinery/power/terminal/T = A.terminal
	T.connect_to_network()
	T.set_power_supply(1000000)
	A.cell.charge = A.cell.maxcharge
	A.update()
	var/obj/machinery/power/smes/S
	for(var/obj/machinery/power/smes/candidate as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!(candidate.stat & BROKEN))
			S = candidate
			break
	var/old_smes = S ? list(S.charge, S.input_attempt, S.output_attempt) : null
	if(S)
		S.charge = S.capacity
		S.input_attempt = FALSE
		S.output_attempt = FALSE
		S.power_sync()
	// The monitor view settles geometrically; the APC reaches full charge.
	for(var/i in 1 to 80)
		SSmachines.process_power()
	var/apc_events = A.power_event_count
	var/smes_events = S?.power_event_count
	for(var/i in 1 to 10)
		SSmachines.process_power()
	TEST_ASSERT_EQUAL(A.power_event_count, apc_events, "a settled APC kept hearing power events")
	TEST_ASSERT(!(A in SSmachines.processing_machines), "a settled APC is polling")
	if(S)
		TEST_ASSERT_EQUAL(S.power_event_count, smes_events, "an idle SMES kept hearing power events")
		TEST_ASSERT(!(S in SSmachines.processing_machines), "an idle SMES is polling")
		S.charge = old_smes[1]
		S.input_attempt = old_smes[2]
		S.output_attempt = old_smes[3]
		S.power_sync()
	else
		TEST_NOTICE(src, "no SMES on the test map; checked the APC only")
	T.set_power_supply(0)
	SSmachines.process_power()

/// A power sensor reads its network's numbers from the Rust ledger.
/datum/unit_test/dq_power_monitor_reading

/datum/unit_test/dq_power_monitor_reading/Run()
	var/list/run = dq_power_test_run(3)
	TEST_ASSERT_NOTNULL(run, "no clear floor run for the monitor test")
	if(!run)
		return
	var/list/cables = dq_power_test_line(run)
	var/obj/machinery/power/sensor/sensor = allocate(/obj/machinery/power/sensor, run[1])
	var/obj/machinery/power/terminal/source = allocate(/obj/machinery/power/terminal, run[3])
	source.set_power_supply(5000)
	SSmachines.process_power()
	SSmachines.process_power()
	TEST_ASSERT_NOTNULL(sensor.powernet, "the sensor is not on the network")
	TEST_ASSERT_EQUAL(sensor.powernet.avail, 5000, "the network does not show its supply")
	var/list/data = sensor.return_reading_data()
	TEST_ASSERT_EQUAL(data["total_avail"], sensor.reading_to_text(5000), "the monitor reads the wrong supply")
	TEST_ASSERT_NULL(data["error"], "the monitor reports no network")
	sensor.draw_power(1200)
	SSmachines.process_power()
	TEST_ASSERT(sensor.powernet.viewload > 0, "the monitor's smoothed load ignores a draw")
	qdel(cables[2])
	SSmachines.process_power()
	TEST_ASSERT(!sensor.powernet || sensor.powernet.avail == 0, "a cut sensor still reads the supply")
	source.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		if(!QDELETED(C))
			qdel(C)

#endif
