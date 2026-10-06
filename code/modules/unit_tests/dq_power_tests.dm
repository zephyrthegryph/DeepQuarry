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
	if(locate_on(T, /obj/structure/cable))
		return FALSE
	if(locate_on(T, /obj/machinery/power))
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
	TEST_ASSERT(left.power_region, "the left machine is not on the cable")
	TEST_ASSERT(left.power_region == right.power_region, "one cable run is two networks")
	var/before = left.power_region

	qdel(cables[3])
	SSmachines.process_power()
	TEST_ASSERT(left.power_region, "the left side lost its network")
	TEST_ASSERT(right.power_region, "the right side lost its network")
	TEST_ASSERT(left.power_region != right.power_region, "a cut cable still joins the two sides")
	TEST_ASSERT(left.power_region == before || right.power_region == before, "neither side kept the network's identity")

	right.set_power_supply(1000)
	SSmachines.process_power()
	TEST_ASSERT_EQUAL(power_avail(left.power_region), 0, "supply crossed the cut")
	TEST_ASSERT_EQUAL(left.draw_power(100), 0, "a draw crossed the cut")

	cables[3] = dq_power_test_cable(run[3], EAST, WEST)
	SSmachines.process_power()
	TEST_ASSERT(left.power_region == right.power_region, "a repaired cable did not merge the networks")
	// `avail` is a per-step law result (ProducerCredit et al, verdigris/domains/power/src/laws.rs),
	// not pushed on every write. One blocking world step settles the merged
	// region's ledger before SSmachines.process_power() re-polls it (a paced
	// vg_frame() does not step while the previous worker frame runs).
	vg_world_run_steps(1)
	SSmachines.process_power()
	TEST_ASSERT_EQUAL(power_avail(left.power_region), 1000, "the merged network does not carry the supply")
	TEST_ASSERT_EQUAL(left.draw_power(600), 600, "a draw on the merged network failed")
	TEST_ASSERT_EQUAL(left.draw_power(600), 400, "a draw exceeded the supply left")
	right.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		qdel(C)

/datum/unit_test/dq_power_apc_cycle
	var/lost_signals = 0
	var/restored_signals = 0

/datum/unit_test/dq_power_apc_cycle/proc/on_lost(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	lost_signals++

/datum/unit_test/dq_power_apc_cycle/proc/on_restored(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	restored_signals++

/// One power step as the game runs it: DM's loads and topology in, one
/// world step (Rust's laws; SSvg paces it in play), the results polled back.
/proc/dq_power_test_step()
	SSmachines.process_power()
	vg_world_run_steps(1)
	SSmachines.process_power()

/proc/dq_power_test_apc()
	for(var/obj/machinery/power/apc/candidate as anything in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(candidate.terminal && candidate.cell && candidate.area?.requires_power && !(candidate.broken_now() || candidate.under_maintenance()) && isturf(candidate.loc))
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
	observe(M, /datum/notice/machinery_power_lost, src, then(PROC_REF(on_lost)))
	observe(M, /datum/notice/machinery_power_restored, src, then(PROC_REF(on_restored)))
	M.power_change()

	// Cut off, nearly empty, with a load.
	A.disconnect_from_network()
	dq_area_load(get_turf(A), 2000, EQUIP)
	A.set_operating(TRUE)
	A.set_chargemode(TRUE)
	A.equipment = POWERCHAN_ON_AUTO
	A.lighting = POWERCHAN_ON_AUTO
	A.environ = POWERCHAN_ON_AUTO
	A.cell.charge = A.cell.maxcharge * 0.001
	A.seat_cell_charge(TRUE) // the seated cell's charge becomes Rust's again
	native_write(A, NATIVE_APC_CHANNELS, A.equipment, 0)
	native_write(A, NATIVE_APC_CHANNELS, A.lighting, 1)
	native_write(A, NATIVE_APC_CHANNELS, A.environ, 2)
	A.apply_area_power()
	refresh_flush()
	var/drained = FALSE
	for(var/i in 1 to 20)
		dq_power_test_step()
		if(!A.area.power_equip)
			drained = TRUE
			break
	TEST_ASSERT(drained, "an empty isolated APC kept its area powered")
	TEST_ASSERT(M.power_lost(), "a machine in the dark area still has power")
	TEST_ASSERT(lost_signals, "the machine never heard machinery_power_lost")
	TEST_ASSERT(A.charging == 0, "an isolated APC claims to charge")
	var/low = A.cell.charge

	// Supply returns.
	A.connect_to_network()
	T.set_power_supply(1000000)
	var/restored = FALSE
	for(var/i in 1 to 80)
		dq_power_test_step()
		if(A.area.power_equip && A.charging)
			restored = TRUE
			break
	TEST_ASSERT(restored, "the APC did not restore and charge once supply returned")
	TEST_ASSERT(!M.power_lost(), "the machine did not get its power back")
	TEST_ASSERT(restored_signals, "the machine never heard machinery_power_restored")
	dq_power_test_step()
	TEST_ASSERT(A.cell.charge > low, "the cell did not charge ([A.cell.charge] after [low])")
	TEST_ASSERT(!machine_stepping(A), "the APC polled during the cycle")

	T.set_power_supply(0)
	dq_area_load(get_turf(A), -2000, EQUIP)
	A.cell.charge = old_charge
	A.seat_cell_charge(TRUE) // the seated cell's charge becomes Rust's again
	A.apply_area_power()
	refresh_flush()
	unobserve(M, /datum/notice/machinery_power_lost, src)
	unobserve(M, /datum/notice/machinery_power_restored, src)
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
	// A known working state, not whatever the map or an earlier test left: this
	// test used to pass only when dq_power_apc_cycle had run just before it
	// (which leaves the APC like this); alone, or in another order under
	// sharding, the APC never settled.
	A.connect_to_network()
	A.set_operating(TRUE)
	A.set_chargemode(TRUE)
	A.equipment = POWERCHAN_ON_AUTO
	A.lighting = POWERCHAN_ON_AUTO
	A.environ = POWERCHAN_ON_AUTO
	native_write(A, NATIVE_APC_CHANNELS, A.equipment, 0)
	native_write(A, NATIVE_APC_CHANNELS, A.lighting, 1)
	native_write(A, NATIVE_APC_CHANNELS, A.environ, 2)
	A.cell.charge = A.cell.maxcharge
	A.seat_cell_charge(TRUE) // the seated cell's charge becomes Rust's again
	A.apply_area_power()
	refresh_flush()
	var/obj/machinery/power/smes/S
	for(var/obj/machinery/power/smes/candidate as anything in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(!candidate.broken_now())
			S = candidate
			break
	var/old_smes = S ? list(S.stored_charge(), S.input_attempt, S.output_attempt) : null
	if(S)
		S.set_stored_charge(S.capacity)
		S.set_input_attempt(FALSE)
		S.set_output_attempt(FALSE)
		refresh_flush()
	// The monitor view settles geometrically; the APC reaches full charge.
	for(var/i in 1 to 80)
		dq_power_test_step()
	var/apc_events = A.power_event_count
	var/smes_events = S?.power_event_count
	for(var/i in 1 to 10)
		dq_power_test_step()
	TEST_ASSERT_EQUAL(A.power_event_count, apc_events, "a settled APC kept hearing power events")
	TEST_ASSERT(!machine_stepping(A), "a settled APC is polling")
	if(S)
		TEST_ASSERT_EQUAL(S.power_event_count, smes_events, "an idle SMES kept hearing power events")
		TEST_ASSERT(!machine_stepping(S), "an idle SMES is polling")
		S.set_stored_charge(old_smes[1])
		S.set_input_attempt(old_smes[2])
		S.set_output_attempt(old_smes[3])
		refresh_flush()
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
	dq_power_test_step()
	dq_power_test_step()
	TEST_ASSERT(sensor.power_region, "the sensor is not on the network")
	TEST_ASSERT_EQUAL(power_avail(sensor.power_region), 5000, "the network does not show its supply")
	var/list/data = sensor.return_reading_data()
	TEST_ASSERT_EQUAL(data["total_avail"], sensor.reading_to_text(5000), "the monitor reads the wrong supply")
	TEST_ASSERT_NULL(data["error"], "the monitor reports no network")
	// The grid keeps no eased copy (a monitor eases what it shows): a draw is booked on the ledger at once.
	sensor.draw_power(1200)
	TEST_ASSERT(power_load(sensor.power_region) > 0, "the ledger did not book a draw (load [power_load(sensor.power_region)] avail [power_avail(sensor.power_region)])")
	dq_power_test_step()
	qdel(cables[2])
	dq_power_test_step()
	TEST_ASSERT(!sensor.power_region || power_avail(sensor.power_region) == 0, "a cut sensor still reads the supply")
	source.set_power_supply(0)
	for(var/obj/structure/cable/C as anything in cables)
		if(!QDELETED(C))
			qdel(C)

#endif

/// Power's wakes reach their subscribers: an area's power change raises its
/// OM channel.
/datum/unit_test/dq_power_area_key_wakes_subscriber

/datum/unit_test/dq_power_area_key_wakes_subscriber/Run()
	var/obj/machinery/power/apc/A = dq_power_test_apc()
	TEST_ASSERT_NOTNULL(A, "the test map has no working APC")
	if(!A)
		return
	// Area power is an OM channel (CHANGE_AREA_POWER); whatever watches it (lights,
	// machines asleep on sleep_until_keys()) is woken by the raise. Count the raise.
	var/area/area = A.area
	var/datum/om/rec/rec = om_rec_of(area)
	var/datum/om/scheduler/sched = rec.sched
	var/old_listen = area.om_listen
	area.om_listen |= CHANGE_AREA_POWER
	sched.test_raises = list()
	area.power_change()
	var/raised = 0
	for(var/list/raise as anything in sched.test_raises)
		if(raise[1] == area && (raise[2] & CHANGE_AREA_POWER))
			raised++
	sched.test_raises = null
	area.om_listen = old_listen
	TEST_ASSERT(raised >= 1, "the area's power change did not raise CHANGE_AREA_POWER")
