// The gas domain's machine API (code/domains/atmos/gas.dm): release, one-read samples, the room heater, body-gas heat exchange and the named
// observation fields.

/proc/gas_api_test_mix(volume, o2_moles, temperature = T20C)
	var/datum/gas_mixture/M = new
	M.set_volume(volume)
	M.set_temperature(temperature)
	if(o2_moles)
		M.adjust_gas(/datum/gas/oxygen, o2_moles)
	M.set_temperature(temperature)
	return M

/datum/unit_test/dq_gas_api/release_to_pressure_and_rate
/datum/unit_test/dq_gas_api/release_to_pressure_and_rate/Run()
	var/datum/gas_mixture/source = gas_api_test_mix(1000, 1000)
	var/datum/gas_mixture/tank = gas_api_test_mix(70, 0)
	var/moved = gas_release(source, tank, 500)
	TEST_ASSERT(moved > 0, "gas moved")
	TEST_ASSERT(abs(tank.return_pressure() - 500) < 1, "the sink is brought to the target: [tank.return_pressure()]")
	TEST_ASSERT_EQUAL(gas_release(source, tank, 400), 0, "a sink above the target takes nothing")
	var/datum/gas_mixture/big = gas_api_test_mix(10000, 0)
	var/total = source.total_moles()
	moved = gas_release(source, big, 10000, 100)
	TEST_ASSERT(abs(moved - total * 100 / 1000) < 0.01, "at most `rate` litres of the source: [moved]")
	var/datum/gas_mixture/empty = gas_api_test_mix(100, 0)
	TEST_ASSERT_EQUAL(gas_release(empty, big, 100, 50), 0, "an empty source releases nothing")
	qdel(source)
	qdel(tank)
	qdel(big)
	qdel(empty)

/datum/unit_test/dq_gas_api/sample_reads
/datum/unit_test/dq_gas_api/sample_reads/Run()
	var/datum/gas_mixture/M = gas_api_test_mix(100, 10)
	M.adjust_gas(/datum/gas/nitrogen, 30)
	var/datum/gas_sample/S = gas_sample(M)
	TEST_ASSERT(abs(S.pressure - M.return_pressure()) < 0.01, "pressure")
	TEST_ASSERT(abs(S.temperature - M.return_temperature()) < 0.01, "temperature")
	TEST_ASSERT(abs(S.moles(GAS_O2) - 10) < 0.001, "moles by id")
	TEST_ASSERT(abs(S.share(GAS_N2) - 0.75) < 0.001, "share")
	TEST_ASSERT(abs(S.partial_pressure(GAS_O2) - 10 * R_IDEAL_GAS_EQUATION * S.temperature / 100) < 0.01, "partial pressure")
	TEST_ASSERT((GAS_O2 in S.gas_ids()) && (GAS_N2 in S.gas_ids()) && !(GAS_CO2 in S.gas_ids()), "the gases present")
	TEST_ASSERT_EQUAL(gas_sample(null).pressure, 0, "no mixture reads empty")
	qdel(M)

/datum/unit_test/dq_gas_api/heater
/datum/unit_test/dq_gas_api/heater/Run()
	var/datum/gas_mixture/M = gas_api_test_mix(2500, 100, T20C - 10)
	var/datum/gas_heater/H = new
	var/before = M.heat_capacity() * M.return_temperature()
	TEST_ASSERT_EQUAL(H.regulate(M, T20C), GAS_HEATER_HEATING, "a cold room starts heating")
	TEST_ASSERT(abs(M.heat_capacity() * M.return_temperature() - before - 1000) < 1, "by its rated 1000 J")
	M.set_temperature(T20C + 0.4)
	TEST_ASSERT_EQUAL(H.regulate(M, T20C), GAS_HEATER_IDLE, "within half a degree it stops")
	M.set_temperature(T20C + 1.5)
	TEST_ASSERT_EQUAL(H.regulate(M, T20C), GAS_HEATER_IDLE, "and does not start inside its start gap")
	var/datum/gas_mixture/small = gas_api_test_mix(100, 2, T20C - 3)
	var/datum/gas_heater/S = new
	var/wanted = 0.25 * small.heat_capacity() * 3
	S.regulate(small, T20C)
	TEST_ASSERT(wanted < 1000 && abs(S.last_joules - wanted) < 0.5, "a small room closes a quarter of the gap: [S.last_joules] vs [wanted]")
	qdel(S)
	qdel(small)
	M.set_temperature(T20C - 100)
	H.state = GAS_HEATER_IDLE
	TEST_ASSERT_EQUAL(H.regulate(M, T20C, FALSE), GAS_HEATER_IDLE, "not allowed: it does nothing")
	M.set_temperature(T20C + 20)
	H.regulate(M, T20C)
	TEST_ASSERT_EQUAL(H.state, GAS_HEATER_COOLING, "a hot room starts cooling")
	TEST_ASSERT(abs(H.last_joules + 1000) < 1, "by its rated 1000 J")
	M.set_temperature(250)
	H.regulate(M, 200)
	TEST_ASSERT(abs(H.last_joules + 1000 * 250 / T20C) < 1, "cooling cold air pumps less into the hull: [H.last_joules]")
	var/datum/gas_mixture/vacuum = gas_api_test_mix(2500, 0.01, T20C - 30)
	var/datum/gas_heater/V = new
	TEST_ASSERT_EQUAL(V.regulate(vacuum, T20C), GAS_HEATER_IDLE, "a near vacuum is left alone")
	qdel(H)
	qdel(V)
	qdel(M)
	qdel(vacuum)

/datum/unit_test/dq_gas_api/body_heat_exchange
/datum/unit_test/dq_gas_api/body_heat_exchange/Run()
	var/datum/gas_mixture/M = gas_api_test_mix(200, 50, 80)
	var/gas_capacity = M.heat_capacity()
	var/energy = gas_capacity * 80 + HUMAN_HEAT_CAPACITY * BODYTEMP_NORMAL
	var/body = gas_body_heat_exchange(M, BODYTEMP_NORMAL, HUMAN_HEAT_CAPACITY)
	TEST_ASSERT(abs(body - M.return_temperature()) < 0.01, "share 1 settles both at one temperature")
	TEST_ASSERT(abs(gas_capacity * M.return_temperature() + HUMAN_HEAT_CAPACITY * body - energy) < 1, "energy is conserved")
	M.set_temperature(80)
	var/half = gas_body_heat_exchange(M, BODYTEMP_NORMAL, HUMAN_HEAT_CAPACITY, 0.5)
	TEST_ASSERT(half > body && half < BODYTEMP_NORMAL, "a half share goes half way: [half]")
	qdel(M)

/datum/unit_test/dq_gas_api/observation_fields
/datum/unit_test/dq_gas_api/observation_fields/Run()
	var/list/record = list(7, 42, 3, 9, 101.3, 293.15, 2500, 21, 0.5, 0, 0, 0, 0, 0, 0, 103)
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_MIXTURE), 42, "the mixture id")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_PRESSURE), 101.3, "pressure")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_TEMPERATURE), 293.15, "temperature")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_OXYGEN), 21, "oxygen")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_TOTAL_MOLES), 103, "total moles")
