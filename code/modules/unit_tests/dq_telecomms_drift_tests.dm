// Telecomms Central floors beside the minitest map's cryogenic rooms cool steadily as world time passes. These tests measure why: the map freezer's
// thermostat pumps for the world's whole life, and the pump's books must balance (heat taken in plus the work done equals the heat rejected).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The mean floor temperature of the Telecomms Central Compartment's turfs, K, and the coldest one: list(mean, min, count).
/proc/telecomms_drift_floors()
	var/total = 0
	var/count = 0
	var/coldest = 1e9
	for(var/turf/simulated/floor/F in get_area_turfs(/area/tcommsat/chamber))
		var/kelvin = F.get_temperature()
		total += kelvin
		count++
		coldest = min(coldest, kelvin)
	return list(count ? total / count : 0, coldest, count)

/datum/unit_test/dq_telecomms_drift_measure

/datum/unit_test/dq_telecomms_drift_measure/Run()
	restore_ambient_after() // the frames below advance world time: the map freezer pumps meanwhile
	var/list/freezers = list()
	for(var/obj/machinery/atmospherics/unary/freezer/Z in world)
		freezers += Z
	for(var/obj/machinery/atmospherics/unary/freezer/Z as anything in freezers)
		log_test("TELECOMMS DRIFT: freezer at ([Z.x],[Z.y],[Z.z]) use_power [Z.use_power] pumping [Z.pumping] set [Z.set_temperature] K power_rating [Z.power_rating] W")
	var/list/start = telecomms_drift_floors()
	log_test("TELECOMMS DRIFT: [start[3]] telecomms floors, step 0: mean [round(start[1], 0.1)] K, coldest [round(start[2], 0.1)] K")
	var/last_mean = start[1]
	var/last_gain = null
	for(var/step in 1 to 20)
		heat_test_world_seconds(1)
		var/list/now = telecomms_drift_floors()
		var/line = "TELECOMMS DRIFT: step [step]: mean [round(now[1], 0.1)] K, coldest [round(now[2], 0.1)] K"
		for(var/obj/machinery/atmospherics/unary/freezer/Z as anything in freezers)
			var/turf/T = get_turf(Z)
			line += "; freezer ([Z.x],[Z.y],[Z.z]) tile air [round(T.return_air().return_temperature(), 0.1)] K, tile floor [round(T.get_temperature(), 0.1)] K, loop gas [round(Z.air_contents.return_temperature(), 0.1)] K"
		log_test(line)
		// The cold rooms start far below the station (80 K) and warm toward it: the mean only rises, each step less than the one before, and stays under the ambient.
		var/gain = now[1] - last_mean
		TEST_ASSERT(gain >= -0.01, "the telecomms floors warm toward the station, they do not cool (step [step]: [round(gain, 0.01)] K)")
		if(!isnull(last_gain))
			TEST_ASSERT(gain <= last_gain + 0.05, "the warming settles: each step gains no more than the one before (step [step]: [round(gain, 0.01)] K after [round(last_gain, 0.01)] K)")
		TEST_ASSERT(now[1] < T20C, "the floors stay under the ambient temperature ([round(now[1], 0.1)] K)")
		last_gain = gain
		last_mean = now[1]

/// The map freezer's pump books balance in a sealed room: the heat the loop gas loses plus the work done is the heat the room gains (the rejected heat,
/// Q + W), and the work stays within what the machine can draw. The freezer is the Rust pump edge (core/src/thermo/transfer.rs) end to end.
/datum/unit_test/dq_heat_bt/freezer_books_balance

/datum/unit_test/dq_heat_bt/freezer_books_balance/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room for the freezer")
	var/turf/A = room[1]
	var/turf/B = room[2]
	var/direction = get_dir(A, B)
	var/obj/machinery/atmospherics/unary/freezer/F = allocate(/obj/machinery/atmospherics/unary/freezer, A)
	F.set_dir(direction)
	F.initialize_directions = direction
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, B)
	P.set_dir(direction | turn(direction, 180))
	P.initialize_directions = P.dir
	F.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(F, P))
	TEST_ASSERT_NOTNULL(F.node, "the freezer joined its pipe")
	F.air_contents.adjust_gas(/datum/gas/nitrogen, 50)
	heat_set(F.air_contents, T20C)
	F.set_set_temperature(200)
	F.set_power_level(100)
	F.set_grid_power(TRUE)
	F.set_broken_condition(FALSE)
	F.set_use_power(USE_POWER_ACTIVE)
	var/loop0 = F.air_contents.heat_capacity() * F.air_contents.return_temperature()
	var/room0 = heat_bt_air_energy(room)
	heat_bt_run(20)
	var/loop_lost = loop0 - F.air_contents.heat_capacity() * F.air_contents.return_temperature()
	var/room_gain = heat_bt_air_energy(room) - room0
	var/work = room_gain - loop_lost
	log_test("TELECOMMS DRIFT: freezer books: loop lost [round(loop_lost)] J, room gained [round(room_gain)] J, work [round(work)] J (rating [F.power_rating] W for 20 s)")
	TEST_ASSERT(loop_lost > 0, "the loop gave up heat ([loop_lost] J)")
	TEST_ASSERT(work > 0, "the room gains the heat plus the work, more than the loop lost ([work] J)")
	TEST_ASSERT(work <= F.power_rating * 20 * 1.01, "the work is within what the machine can draw in 20 s ([work] J)")

#endif
