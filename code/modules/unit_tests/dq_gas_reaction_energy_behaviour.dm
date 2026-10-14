// Behaviour pins for gas reaction energy (doc/rewrite/temperature.md §5): every gas reaction, run once on a standard mixture that meets its
// requirements, ends at the temperature and with the moles it did when DM computed the reaction's energy (green there first), now that Rust
// computes it and books it as a reaction source. The golden values below were measured on the DM model; each run logs what it measured.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A mixture that meets `reaction`'s requirements: each gas it needs at four times its minimum (at least 100 mol), at a temperature inside its
/// window (the middle of a closed one).
/proc/gas_reaction_test_mixture(datum/gas_reaction/reaction)
	var/datum/gas_mixture/air = new(CELL_VOLUME)
	var/low = reaction.requirements["MIN_TEMP"]
	var/high = reaction.requirements["MAX_TEMP"]
	var/kelvin = T20C
	if(low && high)
		kelvin = (low + high) / 2
	else if(low)
		kelvin = max(low * 1.5, low + 200)
	else if(high)
		kelvin = high * 0.8
	for(var/req in reaction.requirements)
		if(ispath(req, /datum/gas))
			air.adjust_moles(req, max(reaction.requirements[req] * 4, 100))
	heat_set(air, kelvin, HEAT_SOURCE_OTHER)
	return air

/// Every reaction's outcome on its test mixture: list(id = list(result, temperature K, total moles)).
/proc/gas_reaction_test_outcomes()
	. = list()
	for(var/datum/gas_reaction/reaction as anything in SSair.gas_reactions)
		if(!length(reaction.requirements) || reaction.id == "vapor")
			continue
		var/datum/gas_mixture/air = gas_reaction_test_mixture(reaction)
		air.reaction_results = list()
		var/result = reaction.react(air, null)
		.[reaction.id] = list(result, air.return_temperature(), air.total_moles())
		qdel(air)

/datum/unit_test/dq_gas_reaction_energy_pins

/datum/unit_test/dq_gas_reaction_energy_pins/Run()
	// id = list(temperature K, total moles) after one reaction on the DM model.
	var/static/list/golden = list(
		"sterilization" = list(664.787, 100),
		"plasmafire" = list(597.926, 199.783),
		"h2fire" = list(4477.21, 197.5),
		"tritfire" = list(5070.79, 197.5),
		"freonfire" = list(147.197, 198.875),
		"nitrousformation" = list(335.714, 250),
		"nitrous_decomp" = list(60797.7, 124.995),
		"bzformation" = list(251.266, 199.97),
		"pluox_formation" = list(156.558, 297.5),
		"nitrium_formation" = list(2242.02, 299.209),
		"nitrium_decomp" = list(275.229, 200.092),
		"freonformation" = list(628.123, 300),
		"nobformation" = list(6157.93, 172),
		"halon_o2removal" = list(544.656, 197.307),
		"healium_formation" = list(3575.78, 200),
		"zauker_formation" = list(62485.4, 199.997),
		"zauker_decomp" = list(357.097, 200),
		"proto_nitrate_formation" = list(6953.6, 200),
		"proto_nitrate_hydrogen_response" = list(292.108, 697.5),
		"proto_nitrate_tritium_response" = list(379.555, 199.345),
		"proto_nitrate_bz_response" = list(283.538, 210.848),
		"antinoblium_replication" = list(220, 100)
	)
	var/list/outcomes = gas_reaction_test_outcomes()
	var/list/lines = list()
	for(var/id in outcomes)
		var/list/o = outcomes[id]
		lines += "\"[id]\" = list([o[2]], [o[3]]),"
	log_test("gas reaction outcomes:\n[jointext(lines, "\n")]")
	for(var/id in golden)
		var/list/expected = golden[id]
		var/list/o = outcomes[id]
		TEST_ASSERT_NOTNULL(o, "[id] did not run")
		if(!o)
			continue
		TEST_ASSERT(abs(o[2] - expected[1]) <= max(0.01, abs(expected[1]) * 0.0005), "[id] ended at [o[2]] K, was [expected[1]] K")
		TEST_ASSERT(abs(o[3] - expected[2]) <= max(0.001, abs(expected[2]) * 0.0005), "[id] ended with [o[3]] mol, was [expected[2]] mol")

#endif
