// Behaviour pins for the machines that move heat (doc/rewrite/temperature.md §6): written against the legacy DM heat maths first (green there), then
// kept green after each machine moved onto the heat network's declared edges (code/domains/heat/). Where a number changed on purpose -- the old
// code created or deleted energy, or depended on how often it stepped -- doc/rewrite/intended_changes.md ("Heat network") records the before and
// after. Every test logs what it measured, so the record can be checked against a run.
//
// Rules: the machine is driven through its own controls and time (test_time); temperatures and energies are read through the gas API; a pin
// states a direction and a bound, not a legacy constant.

/// An isolated two-tile room of standard air at `kelvin`: list(machine tile, other tile), or null.
/proc/heat_bt_room(kelvin)
	var/list/pair = dq_atmos_test_find_clear_pipe_run(2)
	if(!pair)
		return null
	dq_atmos_test_isolate_pair(pair[1], pair[2])
	for(var/turf/open/T as anything in pair)
		T.air.clear()
		T.air.set_moles(/datum/gas/oxygen, MOLES_O2STANDARD)
		T.air.set_moles(/datum/gas/nitrogen, MOLES_N2STANDARD)
		heat_set(T.air, kelvin)
	SSair.run_gas_frames(1)
	return pair

/// `seconds` of game time: the kernel's machines and the heat network's edges (the test clock advances both).
/proc/heat_bt_run(seconds)
	for(var/i in 1 to seconds)
		test_time(1 SECOND)

/// Thermal energy of the air of some turfs, J.
/proc/heat_bt_air_energy(list/turfs)
	. = 0
	for(var/turf/T as anything in turfs)
		var/datum/gas_mixture/air = T.return_air()
		. += air.heat_capacity() * air.return_temperature()

/datum/unit_test/dq_heat_bt
	abstract_type = /datum/unit_test/dq_heat_bt

/datum/unit_test/dq_heat_bt/Run()
	test_driver_begin()
	test_rng(1)
	run_bt()
	test_driver_end()
	dq_atmos_test_restore_walls()

/datum/unit_test/dq_heat_bt/proc/run_bt()
	return

/// A space heater warms a cold room toward its thermostat, and the heat the air gains is the energy its cell gave (resistive heating).
/datum/unit_test/dq_heat_bt/space_heater_heats

/datum/unit_test/dq_heat_bt/space_heater_heats/run_bt()
	var/list/room = heat_bt_room(283)
	TEST_ASSERT_NOTNULL(room, "no room for the space heater")
	var/obj/machinery/space_heater/heater = allocate(/obj/machinery/space_heater, room[1])
	heater.set_temperature = 303
	heater.set_state(1)
	work_start(heater)
	var/charge0 = heater.cell.charge
	var/e0 = heat_bt_air_energy(room)
	heat_bt_run(20)
	var/turf/here = room[1]
	var/datum/gas_mixture/air = here.return_air()
	var/gained = heat_bt_air_energy(room) - e0
	var/drawn = (charge0 - heater.cell.charge) / CELLRATE
	log_test("space heater heating: [round(air.return_temperature(), 0.01)] K after 20 s from 283 K; air gained [round(gained)] J, cell gave [round(drawn)] J")
	TEST_ASSERT(air.return_temperature() > 283.5, "the room warmed ([air.return_temperature()] K)")
	TEST_ASSERT(drawn > 0, "the cell paid for it")
	// Resistive: every joule of cell becomes heat; the room's walls take a share of what the air got.
	TEST_ASSERT(gained <= drawn + 500 && gained >= 0.85 * drawn, "resistive heating: the air gained what the cell gave, less the walls' share ([gained] J vs [drawn] J)")

/// A space heater cools a warm room toward its thermostat, drawing on its cell.
/datum/unit_test/dq_heat_bt/space_heater_cools

/datum/unit_test/dq_heat_bt/space_heater_cools/run_bt()
	var/list/room = heat_bt_room(313)
	TEST_ASSERT_NOTNULL(room, "no room for the space heater")
	var/obj/machinery/space_heater/heater = allocate(/obj/machinery/space_heater, room[1])
	heater.set_temperature = 293
	heater.set_state(1)
	work_start(heater)
	var/charge0 = heater.cell.charge
	var/e0 = heat_bt_air_energy(room)
	heat_bt_run(20)
	var/turf/here = room[1]
	var/datum/gas_mixture/air = here.return_air()
	var/lost = e0 - heat_bt_air_energy(room)
	var/drawn = (charge0 - heater.cell.charge) / CELLRATE
	log_test("space heater cooling: [round(air.return_temperature(), 0.01)] K after 20 s from 313 K; air lost [round(lost)] J, cell gave [round(drawn)] J")
	TEST_ASSERT(air.return_temperature() < 312.5, "the room cooled ([air.return_temperature()] K)")
	TEST_ASSERT(lost > drawn, "a heat pump moves more heat than the work it draws ([lost] J vs [drawn] J)")

/// A gas cooling system cools its pipe gas toward its thermostat and rejects the heat, plus its work, into the room.
/datum/unit_test/dq_heat_bt/freezer_cools_its_loop

/datum/unit_test/dq_heat_bt/freezer_cools_its_loop/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room for the freezer")
	var/turf/A = room[1]
	var/turf/B = room[2]
	var/direction = get_dir(A, B)
	var/obj/machinery/atmospherics/unary/freezer/F = allocate(/obj/machinery/atmospherics/unary/freezer, A)
	F.set_dir(direction)
	F.initialize_directions = direction
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, B)
	P.dir = direction | turn(direction, 180)
	P.initialize_directions = P.dir
	F.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(F, P))
	TEST_ASSERT_NOTNULL(F.node, "the freezer joined its pipe")
	F.air_contents.adjust_gas(/datum/gas/nitrogen, 50)
	heat_set(F.air_contents, T20C)
	F.set_set_temperature(200)
	F.set_power_level(100)
	F.stat_remove(NOPOWER | BROKEN)
	F.set_use_power(USE_POWER_ACTIVE)
	var/room0 = heat_bt_air_energy(room)
	heat_bt_run(20)
	var/loop_t = F.air_contents.return_temperature()
	var/room_gain = heat_bt_air_energy(room) - room0
	log_test("freezer: loop [round(loop_t, 0.01)] K after 20 s from [T20C] K toward 200 K; room gained [round(room_gain)] J")
	TEST_ASSERT(loop_t < T20C - 1, "the loop cooled ([loop_t] K)")
	TEST_ASSERT(room_gain > 0, "the room took the rejected heat ([room_gain] J)")

/// A gas heating system heats its pipe gas toward its thermostat.
/datum/unit_test/dq_heat_bt/heater_heats_its_loop

/datum/unit_test/dq_heat_bt/heater_heats_its_loop/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room for the heater")
	var/turf/A = room[1]
	var/turf/B = room[2]
	var/direction = get_dir(A, B)
	var/obj/machinery/atmospherics/unary/heater/H = allocate(/obj/machinery/atmospherics/unary/heater, A)
	H.set_dir(direction)
	H.initialize_directions = direction
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple, B)
	P.dir = direction | turn(direction, 180)
	P.initialize_directions = P.dir
	H.atmos_init()
	P.atmos_init()
	dq_atmos_test_publish_rust_pipenets(list(H, P))
	TEST_ASSERT_NOTNULL(H.node, "the heater joined its pipe")
	H.air_contents.adjust_gas(/datum/gas/nitrogen, 50)
	heat_set(H.air_contents, T20C)
	H.set_set_temperature(400)
	H.set_power_level(100)
	H.stat_remove(NOPOWER | BROKEN)
	H.set_use_power(USE_POWER_ACTIVE)
	heat_bt_run(20)
	var/loop_t = H.air_contents.return_temperature()
	log_test("heater: loop [round(loop_t, 0.01)] K after 20 s from [T20C] K toward 400 K")
	TEST_ASSERT(loop_t > T20C + 1, "the loop warmed ([loop_t] K)")
	TEST_ASSERT(loop_t <= 400.5, "and not past its thermostat ([loop_t] K)")

/// An exosuit's cabin air is brought back toward 20 °C while its temperature control runs.
/datum/unit_test/dq_heat_bt/mecha_cabin_normalizes

/datum/unit_test/dq_heat_bt/mecha_cabin_normalizes/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room for the exosuit")
	var/obj/mecha/working/ripley/M = allocate(/obj/mecha/working/ripley, room[1])
	heat_set(M.cabin_air, T20C + 40)
	for(var/i in 1 to 4)
		M.process_preserve_temp()
		heat_bt_run(2)
	var/cabin_t = M.cabin_air.return_temperature()
	log_test("exosuit cabin: [round(cabin_t, 0.01)] K after four regulations from [T20C + 40] K")
	TEST_ASSERT(cabin_t < T20C + 39, "the cabin cooled toward 20 C ([cabin_t] K)")
	TEST_ASSERT(cabin_t >= T20C - 0.5, "and not below it ([cabin_t] K)")

/// A burning step on a tile turns its oxygen into carbon dioxide and puts the fire's heat in the air.
/datum/unit_test/dq_heat_bt/burning_heats_the_tile

/datum/unit_test/dq_heat_bt/burning_heats_the_tile/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room to burn in")
	var/turf/T = room[1]
	var/e0 = heat_bt_air_energy(list(T))
	TEST_ASSERT(burn_gas_step(T, 100000), "the tile has oxygen to burn")
	var/gained = heat_bt_air_energy(list(T)) - e0
	log_test("burning: the tile's air gained [round(gained)] J of 100000 J")
	TEST_ASSERT(abs(gained - 100000) < 1000, "the air took the fire's heat ([gained] J)")

/// A pipe tank spawns at its declared temperature.
/datum/unit_test/dq_heat_bt/pipe_tank_spawns_at_its_temperature

/datum/unit_test/dq_heat_bt/pipe_tank_spawns_at_its_temperature/run_bt()
	var/list/room = heat_bt_room(T20C)
	TEST_ASSERT_NOTNULL(room, "no room for a tank")
	var/obj/machinery/atmospherics/pipe/tank/air/tank = allocate(/obj/machinery/atmospherics/pipe/tank/air, room[1])
	var/datum/gas_mixture/air = tank.return_air()
	log_test("pipe tank: [air.return_temperature()] K")
	TEST_ASSERT(abs(air.return_temperature() - T20C) < 0.5, "an air tank starts at 20 C ([air.return_temperature()] K)")
