// Chemistry gases: the atmos gases added for chemistry (chlorine, ammonia), a boiled-off reagent that is a real gas entering the air of its tile as that gas, and what
// breathing the new gases does (code/domains/world_model/reagents/vapour.dm, code/domains/body/breath_profile.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A floor with standard air that the test puts back, and no other gas on it.
/datum/unit_test/proc/dq_cg_floor()
	var/turf/open/T = test_floor()
	TEST_ASSERT_NOTNULL(T, "a floor to vent on")
	dq_atmos_test_snapshot_air(T)
	dq_atmos_test_fill_standard_air(T)
	return T

/// A bolted, powered hot plate on `T` with a large beaker of `units` of `reagent` on it, on the kernel test clock.
/datum/unit_test/proc/dq_cg_plate(turf/T, reagent, units)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/obj/machinery/chem_hot_plate/P = allocate(/obj/machinery/chem_hot_plate, T)
	P.set_anchored(TRUE)
	P.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker/large, T)
	B.reagents.add_reagent(reagent, units, safety = 1)
	move_into(P, nameof(P.held_container), B)
	return P

/// The new gases are in the registry with the heat capacity they declare, and the filter mask covers every gas.
/datum/unit_test/dq_chem_gases_register

/datum/unit_test/dq_chem_gases_register/Run()
	TEST_ASSERT_EQUAL(GAS_ID_COUNT, 24, "24 gases: the most a DM float mask holds exactly")
	TEST_ASSERT_EQUAL(RUST_ALL_GASES_MASK, 0xFFFFFF, "the all-gases mask has one bit per gas")
	TEST_ASSERT_EQUAL(RUST_ALL_GASES_MASK & (1 << (GAS_ID_COUNT - 1)), 1 << (GAS_ID_COUNT - 1), "the last gas has a bit DM can hold (DM bit operators hold 24 bits)")
	var/list/expected = list(/datum/gas/chlorine = 34, /datum/gas/ammonia = 36)
	for(var/gas_type in expected)
		var/list/info = GLOB.meta_gas_info[gas_type]
		TEST_ASSERT_NOTNULL(info, "[gas_type] has meta info")
		TEST_ASSERT_EQUAL(info[META_GAS_SPECIFIC_HEAT], expected[gas_type], "[gas_type] specific heat")
		TEST_ASSERT_EQUAL(GLOB.gas_path_by_idx[GAS_IDX(gas_type) + 1], gas_type, "[gas_type] is found by its index")
		var/datum/gas_mixture/mix = new(CELL_VOLUME)
		mix.adjust_gas(gas_type, 2)
		TEST_ASSERT(abs(mix.heat_capacity() - 2 * expected[gas_type]) < 0.01, "2 mol of [gas_type] has a heat capacity of [2 * expected[gas_type]] (got [mix.heat_capacity()])")
	TEST_ASSERT_EQUAL(GAS_IDX(GAS_CHLORINE), GAS_ID_CHLORINE, "the short id finds chlorine")
	TEST_ASSERT_EQUAL(GAS_IDX(GAS_AMMONIA), GAS_ID_AMMONIA, "the short id finds ammonia")

/// Every reagent mapped to a gas names a gas that exists.
/datum/unit_test/dq_chem_gas_mapping_is_real

/datum/unit_test/dq_chem_gas_mapping_is_real/Run()
	TEST_ASSERT(length(GLOB.reagent_vapour_gases) >= 8, "the mapping has rows")
	for(var/reagent in GLOB.reagent_vapour_gases)
		var/gas = GLOB.reagent_vapour_gases[reagent]
		TEST_ASSERT_NOTNULL(GLOB.gas_idx_by_key[gas], "[reagent] maps to [gas], which is not a registered gas")
		var/obj/item/reagent_containers/glass/beaker/B = allocate(/obj/item/reagent_containers/glass/beaker/large, test_floor())
		B.reagents.add_reagent(reagent, 1, safety = 1)
		TEST_ASSERT(B.reagents.get_reagent_amount(reagent) > 0, "[reagent] is a reagent")

/// Vapour let out on a tile enters its air as the gas of its reagent, in moles from units, carrying its heat.
/datum/unit_test/dq_chem_vent_makes_gas

/datum/unit_test/dq_chem_vent_makes_gas/Run()
	var/turf/open/T = dq_cg_floor()
	var/datum/gas_mixture/air = T.turf_air()
	var/before = air.get_moles(/datum/gas/chlorine)
	var/kelvin_before = air.return_temperature()
	var/units = vent_vapour_at(T, list(REAGENT_ID_CHLORINE = list(10, null, T0C + 300)), "test")
	TEST_ASSERT_EQUAL(units, 10, "the vapour went into the air")
	var/gained = air.get_moles(/datum/gas/chlorine) - before
	TEST_ASSERT(abs(gained - 10 * CHEM_GAS_MOLES_PER_UNIT) < 0.01, "10u of chlorine are [10 * CHEM_GAS_MOLES_PER_UNIT] mol (got [gained])")
	TEST_ASSERT(air.return_temperature() > kelvin_before, "300 C vapour warms the air ([kelvin_before] -> [air.return_temperature()] K)")
	// Not a gas the air has: not vented.
	var/other = vent_vapour_at(T, list(REAGENT_ID_SUGAR = list(10, null, T0C + 300)), "test")
	TEST_ASSERT_EQUAL(other, 0, "sugar vapour is not a gas")

/// A beaker of a mapped reagent boiling on a plate with no condenser raises that gas on the plate's tile.
/datum/unit_test/dq_chem_boil_without_condenser_raises_gas

/datum/unit_test/dq_chem_boil_without_condenser_raises_gas/Run()
	var/turf/open/T = dq_cg_floor()
	var/datum/gas_mixture/air = T.turf_air()
	var/obj/machinery/chem_hot_plate/P = dq_cg_plate(T, REAGENT_ID_AMMONIA, 30)
	var/obj/item/reagent_containers/glass/beaker/B = P.held_container
	TEST_ASSERT_EQUAL(air.get_moles(/datum/gas/ammonia), 0, "no ammonia in the air to begin with")
	P.set_dial(T0C + 120)
	P.switch_element(null, TRUE)
	test_time(60 SECONDS)
	var/boiled = 30 - B.reagents.get_reagent_amount(REAGENT_ID_AMMONIA)
	TEST_ASSERT(boiled > 1, "the ammonia boiled ([boiled]u)")
	var/moles = air.get_moles(/datum/gas/ammonia)
	TEST_ASSERT(abs(moles - boiled * CHEM_GAS_MOLES_PER_UNIT) < 0.05 * max(boiled, 1), "the air holds the boiled ammonia as gas: [moles] mol for [boiled]u")

/// A condenser next to the plate still catches the vapour first: nothing reaches the air.
/datum/unit_test/dq_chem_condenser_catches_vapour_first

/datum/unit_test/dq_chem_condenser_catches_vapour_first/Run()
	var/turf/open/T = dq_cg_floor()
	var/datum/gas_mixture/air = T.turf_air()
	var/obj/machinery/chem_hot_plate/P = dq_cg_plate(T, REAGENT_ID_AMMONIA, 30)
	var/obj/machinery/chem_condenser/C = allocate(/obj/machinery/chem_condenser, T)
	C.set_anchored(TRUE)
	C.set_powered(TRUE)
	var/obj/item/reagent_containers/glass/beaker/catch = allocate(/obj/item/reagent_containers/glass/beaker/large, T)
	move_into(C, nameof(C.held_container), catch)
	P.set_dial(T0C + 120)
	P.switch_element(null, TRUE)
	test_time(60 SECONDS)
	TEST_ASSERT(catch.reagents.get_reagent_amount(REAGENT_ID_AMMONIA) > 1, "the condenser collected the vapour")
	TEST_ASSERT_EQUAL(air.get_moles(/datum/gas/ammonia), 0, "none of it reached the air")

/// Chlorine in a breath burns the lungs; ammonia irritates. Clean air does neither.
/datum/unit_test/dq_chem_gas_breath_harms

/datum/unit_test/dq_chem_gas_breath_harms/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.species, "the test human has a species")
	var/datum/gas_mixture/clean = dq_cg_breath(null, 0)
	var/thermal = H.injury_load(INJURY_CATEGORY_THERMAL)
	H.life_breathing_exchange(clean)
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_THERMAL), thermal, "clean air burns nothing")
	var/datum/gas_mixture/gassy = dq_cg_breath(/datum/gas/chlorine, 8)
	H.life_breathing_exchange(gassy)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_THERMAL) > thermal, "chlorine burns the lungs ([thermal] -> [H.injury_load(INJURY_CATEGORY_THERMAL)])")
	var/mob/living/carbon/human/G = allocate(/mob/living/carbon/human)
	var/toxic = G.injury_load(INJURY_CATEGORY_TOXIC)
	G.life_breathing_exchange(dq_cg_breath(/datum/gas/ammonia, 8))
	TEST_ASSERT(G.injury_load(INJURY_CATEGORY_TOXIC) > toxic, "ammonia irritates ([toxic] -> [G.injury_load(INJURY_CATEGORY_TOXIC)])")

/// Chlorine filling the room burns a breather with no internals, woken by the chlorine watch (the live Life sequence, not the breath proc).
/datum/unit_test/life_seq/breath_hazard/chlorine

/datum/unit_test/life_seq/breath_hazard/chlorine/proc/burnt()
	return H.injury_load(INJURY_CATEGORY_THERMAL) > 0

/datum/unit_test/life_seq/breath_hazard/chlorine/run_life()
	if(!setup_breather())
		return
	release(/datum/gas/chlorine, 2)
	assert_acts(PROC_REF(burnt), "a human standing in chlorine was not burnt")

/// A breath of standard air with `moles` of `gas` (null: none) mixed in.
/datum/unit_test/proc/dq_cg_breath(gas, moles)
	var/datum/gas_mixture/breath = new(BREATH_VOLUME)
	breath.adjust_gas(/datum/gas/oxygen, MOLES_O2STANDARD * 0.5)
	breath.adjust_gas(/datum/gas/nitrogen, MOLES_N2STANDARD * 0.5)
	if(gas)
		breath.adjust_gas(gas, moles)
	heat_set(breath, T20C, HEAT_SOURCE_OTHER)
	return breath

#endif
