// Declaration pin for the gas reactions (doc/rewrite/proposals/transformations.md, wave 2): the id, the order, the gases and minimum moles, the temperature
// window and the hotspot flag of every reaction, read off the old /datum/gas_reaction types before they became /transformation/gas rules. The outcome of
// each reaction is pinned by dq_gas_reaction_energy_pins.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_gas_reaction_declaration_pin

/datum/unit_test/dq_gas_reaction_declaration_pin/Run()
	// id = list(list(gas type = minimum moles, ...), minimum K or null, maximum K or null, expands a hotspot), in the order the reactions run.
	var/static/list/legacy = list(
		"vapor" = list(list(/datum/gas/water_vapor = MOLES_GAS_VISIBLE), null, WATER_VAPOR_CONDENSATION_POINT, FALSE),
		"sterilization" = list(list(/datum/gas/miasma = MINIMUM_MOLE_COUNT), MIASTER_STERILIZATION_TEMP, null, FALSE),
		"plasmafire" = list(list(/datum/gas/plasma = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT), PLASMA_MINIMUM_BURN_TEMPERATURE, null, TRUE),
		"h2fire" = list(list(/datum/gas/hydrogen = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT), HYDROGEN_MINIMUM_BURN_TEMPERATURE, null, TRUE),
		"tritfire" = list(list(/datum/gas/tritium = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT), TRITIUM_MINIMUM_BURN_TEMPERATURE, null, TRUE),
		"freonfire" = list(list(/datum/gas/oxygen = MINIMUM_MOLE_COUNT, /datum/gas/freon = MINIMUM_MOLE_COUNT), FREON_TERMINAL_TEMPERATURE, FREON_MAXIMUM_BURN_TEMPERATURE, TRUE),
		"nitrousformation" = list(list(/datum/gas/oxygen = 10, /datum/gas/nitrogen = 20, /datum/gas/bz = 5), N2O_FORMATION_MIN_TEMPERATURE, N2O_FORMATION_MAX_TEMPERATURE, FALSE),
		"nitrous_decomp" = list(list(/datum/gas/nitrous_oxide = MINIMUM_MOLE_COUNT * 2), N2O_DECOMPOSITION_MIN_TEMPERATURE, N2O_DECOMPOSITION_MAX_TEMPERATURE, FALSE),
		"bzformation" = list(list(/datum/gas/nitrous_oxide = 10, /datum/gas/plasma = 10), null, BZ_FORMATION_MAX_TEMPERATURE, FALSE),
		"pluox_formation" = list(list(/datum/gas/carbon_dioxide = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT, /datum/gas/tritium = MINIMUM_MOLE_COUNT), PLUOXIUM_FORMATION_MIN_TEMP, PLUOXIUM_FORMATION_MAX_TEMP, FALSE),
		"nitrium_formation" = list(list(/datum/gas/tritium = 20, /datum/gas/nitrogen = 10, /datum/gas/bz = 5), NITRIUM_FORMATION_MIN_TEMP, null, FALSE),
		"nitrium_decomp" = list(list(/datum/gas/oxygen = MINIMUM_MOLE_COUNT, /datum/gas/nitrium = MINIMUM_MOLE_COUNT), null, NITRIUM_DECOMPOSITION_MAX_TEMP, FALSE),
		"freonformation" = list(list(/datum/gas/plasma = MINIMUM_MOLE_COUNT * 6, /datum/gas/carbon_dioxide = MINIMUM_MOLE_COUNT * 3, /datum/gas/bz = MINIMUM_MOLE_COUNT), FREON_FORMATION_MIN_TEMPERATURE, null, FALSE),
		"nobformation" = list(list(/datum/gas/nitrogen = 10, /datum/gas/tritium = 5), NOBLIUM_FORMATION_MIN_TEMP, NOBLIUM_FORMATION_MAX_TEMP, FALSE),
		"halon_o2removal" = list(list(/datum/gas/halon = MINIMUM_MOLE_COUNT, /datum/gas/oxygen = MINIMUM_MOLE_COUNT), HALON_COMBUSTION_MIN_TEMPERATURE, null, FALSE),
		"healium_formation" = list(list(/datum/gas/bz = MINIMUM_MOLE_COUNT, /datum/gas/freon = MINIMUM_MOLE_COUNT), HEALIUM_FORMATION_MIN_TEMP, HEALIUM_FORMATION_MAX_TEMP, FALSE),
		"zauker_formation" = list(list(/datum/gas/hypernoblium = MINIMUM_MOLE_COUNT, /datum/gas/nitrium = MINIMUM_MOLE_COUNT), ZAUKER_FORMATION_MIN_TEMPERATURE, ZAUKER_FORMATION_MAX_TEMPERATURE, FALSE),
		"zauker_decomp" = list(list(/datum/gas/nitrogen = MINIMUM_MOLE_COUNT, /datum/gas/zauker = MINIMUM_MOLE_COUNT), null, null, FALSE),
		"proto_nitrate_formation" = list(list(/datum/gas/pluoxium = MINIMUM_MOLE_COUNT, /datum/gas/hydrogen = MINIMUM_MOLE_COUNT), PN_FORMATION_MIN_TEMPERATURE, PN_FORMATION_MAX_TEMPERATURE, FALSE),
		"proto_nitrate_hydrogen_response" = list(list(/datum/gas/proto_nitrate = MINIMUM_MOLE_COUNT, /datum/gas/hydrogen = PN_HYDROGEN_CONVERSION_THRESHOLD), null, null, FALSE),
		"proto_nitrate_tritium_response" = list(list(/datum/gas/proto_nitrate = MINIMUM_MOLE_COUNT, /datum/gas/tritium = MINIMUM_MOLE_COUNT), PN_TRITIUM_CONVERSION_MIN_TEMP, PN_TRITIUM_CONVERSION_MAX_TEMP, FALSE),
		"proto_nitrate_bz_response" = list(list(/datum/gas/proto_nitrate = MINIMUM_MOLE_COUNT, /datum/gas/bz = MINIMUM_MOLE_COUNT), PN_BZASE_MIN_TEMP, PN_BZASE_MAX_TEMP, FALSE),
		"antinoblium_replication" = list(list(/datum/gas/antinoblium = MOLES_GAS_VISIBLE), REACTION_OPPRESSION_MIN_TEMP, null, FALSE)
	)
	var/list/rules = xform_rules_in(MEDIUM_GAS, REGIME_GAS)
	TEST_ASSERT_EQUAL(length(rules), length(legacy), "the number of gas reactions")
	var/at = 0
	var/list/hotspot_types = list()
	for(var/id in legacy)
		at++
		var/list/expected = legacy[id]
		var/datum/xform/rule = at <= length(rules) ? rules[at] : null
		TEST_ASSERT_NOTNULL(rule, "[id] has no rule at place [at]")
		if(!rule)
			continue
		TEST_ASSERT_EQUAL(rule.id, id, "the reaction at place [at]")
		var/list/takes = expected[1]
		TEST_ASSERT_EQUAL(length(rule.gas_takes), length(takes), "[id]: the number of gases it needs")
		for(var/gas_type in takes)
			TEST_ASSERT_EQUAL(rule.gas_takes[gas_type], takes[gas_type], "[id]: minimum moles of [gas_type]")
		TEST_ASSERT_EQUAL(rule.min_temp, expected[2], "[id]: minimum temperature")
		TEST_ASSERT_EQUAL(rule.max_temp, expected[3], "[id]: maximum temperature")
		TEST_ASSERT_EQUAL(rule.expands_hotspot, expected[4], "[id]: expands a hotspot")
		if(expected[4])
			hotspot_types += rule.rule_type
		var/transformation/gas/owner = rule.owner_of()
		TEST_ASSERT(istype(owner, rule.rule_type), "[id]: the owner instance is its type")
	TEST_ASSERT_EQUAL(length(SSair.hotspot_reactions), length(hotspot_types), "the number of reactions a hotspot reads")
	for(var/hotspot_type in hotspot_types)
		TEST_ASSERT(hotspot_type in SSair.hotspot_reactions, "[hotspot_type] is read by a hotspot")

#endif
