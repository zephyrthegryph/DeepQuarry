// H1 (doc/rewrite/temperature.md §2.1): one temperature API and generated
// thermal constants. The readers that replaced the ad-hoc return_temperature()
// procs must give what those procs gave, and every define generated from
// verdigris/domains/heat/src/consts.rs must equal what the DLL reports.

/// Absolute tolerance for comparing an f32 from Rust with a DM number.
#define HEAT_API_EPSILON(value) (max(abs(value), 1) * 1e-5)

/// The generated defines equal the values the loaded DLL was built with, so a
/// stale DLL or a hand-edited define shows up here.
/datum/unit_test/dq_heat_constants_match_rust

/datum/unit_test/dq_heat_constants_match_rust/Run()
	var/list/rust = vg_heat_constants()
	TEST_ASSERT(islist(rust) && length(rust) >= 11, "vg_heat_constants() returned [json_encode(rust)]")
	var/list/expected = list(
		"TCMB" = TCMB,
		"T0C" = T0C,
		"T20C" = T20C,
		"SPACE_SKY_TEMPERATURE" = T20C,
		"STEFAN_BOLTZMANN_CONSTANT" = STEFAN_BOLTZMANN_CONSTANT,
		"THERMAL_EMISSIVITY_DEFAULT" = THERMAL_EMISSIVITY_DEFAULT,
		"HEAT_DT" = 1,
		"BODYTEMP_NORMAL" = BODYTEMP_NORMAL,
		"HUMAN_HEAT_CAPACITY" = HUMAN_HEAT_CAPACITY,
		"FIRE_MINIMUM_TEMPERATURE_TO_EXIST" = FIRE_MINIMUM_TEMPERATURE_TO_EXIST,
		"HEAT_CAPACITY_VACUUM" = HEAT_CAPACITY_VACUUM,
	)
	var/i = 0
	for(var/name in expected)
		i++
		var/dm_value = expected[name]
		var/rust_value = rust[i]
		if(name == "STEFAN_BOLTZMANN_CONSTANT")
			TEST_ASSERT(abs(rust_value - dm_value) < dm_value * 1e-5, "[name]: DM [dm_value], Rust [rust_value]")
			continue
		TEST_ASSERT(abs(rust_value - dm_value) <= HEAT_API_EPSILON(dm_value), "[name]: DM [dm_value], Rust [rust_value]")

/// The unified constants hold their physical values, and the duplicates that
/// used to disagree now read the one define.
/datum/unit_test/dq_heat_constants_unified

/datum/unit_test/dq_heat_constants_unified/Run()
	TEST_ASSERT(abs((BODYTEMP_NORMAL - T0C) - 37) < 0.001, "BODYTEMP_NORMAL is [BODYTEMP_NORMAL], not 37 °C")
	TEST_ASSERT(abs(FIRE_MINIMUM_TEMPERATURE_TO_EXIST - (T0C + 100)) < 0.001, "the ignition point is [FIRE_MINIMUM_TEMPERATURE_TO_EXIST], not 100 °C")
	TEST_ASSERT_EQUAL(PLASMA_MINIMUM_BURN_TEMPERATURE, FIRE_MINIMUM_TEMPERATURE_TO_EXIST, "phoron has two ignition points")
	var/mob/living/probe = /mob/living
	TEST_ASSERT_EQUAL(initial(probe.bodytemperature), BODYTEMP_NORMAL, "mobs start at [initial(probe.bodytemperature)] K")
	var/datum/species/human = /datum/species
	TEST_ASSERT_EQUAL(initial(human.body_temperature), BODYTEMP_NORMAL, "species stabilise at [initial(human.body_temperature)] K")

/// A turf's get_temperature() is its solid's temperature (what the deleted
/// /turf/proc/return_temperature() returned), and get_interior_temperature()
/// is its air's.
/datum/unit_test/dq_heat_turf_readers_parity

/datum/unit_test/dq_heat_turf_readers_parity/Run()
	var/turf/T = heat_test_turf()
	TEST_ASSERT_NOTNULL(T, "no floor with air")
	heat_test_solid(T, 10000, 0.05, 350)
	var/solid = vg_heat_turf_temperature(T)
	var/read = T.get_temperature()
	var/interior = T.get_interior_temperature()
	var/datum/gas_mixture/air = T.return_air()
	var/air_temperature = air.return_temperature()
	heat_test_restore(T)
	vg_heat_debug_run_frames(1)
	TEST_ASSERT(abs(solid - 350) < 0.01, "the solid cell reads [solid] K")
	TEST_ASSERT_EQUAL(read, solid, "get_temperature() is not the solid's temperature")
	TEST_ASSERT_EQUAL(interior, air_temperature, "get_interior_temperature() is not the turf air's temperature")

/// A tank's and a canister's interior temperature is their gas's (what the
/// deleted tank and canister return_temperature() procs returned).
/datum/unit_test/dq_heat_gas_container_readers_parity

/datum/unit_test/dq_heat_gas_container_readers_parity/Run()
	var/turf/T = test_floor()
	var/obj/item/tank/oxygen/tank = allocate(/obj/item/tank/oxygen, T)
	tank.air_contents.set_temperature(250)
	TEST_ASSERT_EQUAL(tank.get_interior_temperature(), tank.air_contents.return_temperature(), "tank interior")
	TEST_ASSERT(abs(tank.get_interior_temperature() - 250) < 0.01, "tank reads [tank.get_interior_temperature()] K")

	var/obj/machinery/portable_atmospherics/canister/air/canister = allocate(/obj/machinery/portable_atmospherics/canister/air, T)
	canister.air_contents.set_temperature(400)
	TEST_ASSERT_EQUAL(canister.get_interior_temperature(), canister.air_contents.return_temperature(), "canister interior")
	TEST_ASSERT(abs(canister.get_interior_temperature() - 400) < 0.01, "canister reads [canister.get_interior_temperature()] K")

/// A mech's interior temperature is its turf air's when it breathes outside air
/// (the deleted /obj/mecha/proc/return_temperature()).
/datum/unit_test/dq_heat_mecha_reader_parity

/datum/unit_test/dq_heat_mecha_reader_parity/Run()
	var/turf/T = heat_test_turf()
	TEST_ASSERT_NOTNULL(T, "no floor with air")
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	mech.use_internal_tank = FALSE
	var/datum/gas_mixture/air = T.return_air()
	TEST_ASSERT_EQUAL(mech.get_interior_temperature(), air.return_temperature(), "mech interior on outside air")

#undef HEAT_API_EPSILON
