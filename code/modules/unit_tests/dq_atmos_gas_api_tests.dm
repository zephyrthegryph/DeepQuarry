// The gas domain's machine API (code/domains/atmos/gas.dm): release, one-read samples, the room heater, body-gas heat exchange and the named
// observation fields.

/proc/gas_api_test_mix(volume, o2_moles, temperature = T20C)
	var/datum/gas_mixture/M = new
	M.set_volume(volume)
	heat_set(M, temperature, HEAT_SOURCE_OTHER)
	if(o2_moles)
		M.adjust_gas(/datum/gas/oxygen, o2_moles)
	heat_set(M, temperature, HEAT_SOURCE_OTHER)
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

/// A body and a gas meet in one conserved operation (heat_equalize(), the heat domain), and the gas's own Rust revision moves with no mark from
/// the caller or the heat procs (a gas watch reads that change tracking, dq_gas_watch_hears_heat_writes).
/datum/unit_test/dq_gas_api/body_heat_exchange
/datum/unit_test/dq_gas_api/body_heat_exchange/Run()
	var/datum/pipe_network/N = new
	rel_set(N, nameof(N.air), gas_api_test_mix(200, 50, 80))
	var/obj/item/body = new /obj/item(null)
	heat_set(body, BODYTEMP_NORMAL)
	var/list/r = heat_reservoir_of(body)
	var/body_capacity = vg_heat_reservoir_state(r[1], r[2])[2]
	var/gas_capacity = N.air.heat_capacity()
	var/energy = gas_capacity * 80 + body_capacity * BODYTEMP_NORMAL
	var/before = N.air.revision()
	heat_equalize(N.air, body)
	TEST_ASSERT(abs(body.get_temperature() - N.air.return_temperature()) < 0.01, "both end at one temperature")
	TEST_ASSERT(abs(gas_capacity * N.air.return_temperature() + body_capacity * body.get_temperature() - energy) < max(1, energy * 1e-5), "energy is conserved")
	TEST_ASSERT(N.air.revision() != before, "the gas's revision moves")
	qdel(body)
	qdel(N)

/datum/unit_test/dq_gas_api/observation_fields
/datum/unit_test/dq_gas_api/observation_fields/Run()
	var/list/record = list(7, 42, 3, 9, 101.3, 293.15, 2500, 21, 0.5, 0, 0, 0, 0, 0, 0, 103)
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_MIXTURE), 42, "the mixture id")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_PRESSURE), 101.3, "pressure")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_TEMPERATURE), 293.15, "temperature")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_OXYGEN), 21, "oxygen")
	TEST_ASSERT_EQUAL(GAS_OBSERVED(record, 2, GAS_OBS_TOTAL_MOLES), 103, "total moles")
