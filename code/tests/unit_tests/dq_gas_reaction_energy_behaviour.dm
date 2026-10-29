// Behaviour of gas reaction energy (doc/rewrite/temperature.md §5): every gas reaction, run once on a standard mixture that meets its requirements,
// leaves a physical mixture (positive temperature and moles) and the fires heat it. The energy itself is computed in Rust and booked as a reaction
// source; each run logs what it measured.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A mixture that meets `reaction`'s requirements: each gas it needs at four times its minimum (at least 100 mol), at a temperature inside its
/// window (the middle of a closed one).
/proc/gas_reaction_test_mixture(datum/xform/reaction)
	var/datum/gas_mixture/air = new(CELL_VOLUME)
	var/low = reaction.min_temp
	var/high = reaction.max_temp
	var/kelvin = T20C
	if(low && high)
		kelvin = (low + high) / 2
	else if(low)
		kelvin = max(low * 1.5, low + 200)
	else if(high)
		kelvin = high * 0.8
	for(var/req in reaction.gas_takes)
		air.adjust_moles(req, max(reaction.gas_takes[req] * 4, 100))
	heat_set(air, kelvin, HEAT_SOURCE_OTHER)
	return air

/// Every reaction's outcome on its test mixture: list(id = list(result, temperature K, total moles, starting temperature K, starting moles)).
/proc/gas_reaction_test_outcomes()
	. = list()
	for(var/datum/xform/reaction as anything in SSair.gas_rules)
		if(!length(reaction.gas_takes) || reaction.id == "vapor")
			continue
		var/datum/gas_mixture/air = gas_reaction_test_mixture(reaction)
		air.reaction_results = list()
		var/start_temperature = air.return_temperature()
		var/start_moles = air.total_moles()
		var/transformation/gas/owner = reaction.owner_of()
		var/result = owner.react(air, null)
		.[reaction.id] = list(result, air.return_temperature(), air.total_moles(), start_temperature, start_moles)
		qdel(air)

/datum/unit_test/dq_gas_reaction_energy_pins

/datum/unit_test/dq_gas_reaction_energy_pins/Run()
	var/list/outcomes = gas_reaction_test_outcomes()
	TEST_ASSERT(length(outcomes) > 15, "the gas reactions ran: [length(outcomes)]")
	var/list/lines = list()
	for(var/id in outcomes)
		var/list/o = outcomes[id]
		lines += "\"[id]\" = list([o[2]], [o[3]]), started [o[4]] K, [o[5]] mol"
		TEST_ASSERT(o[2] > 0 && o[2] < INFINITY, "[id] ended at [o[2]] K, which is not a temperature")
		TEST_ASSERT(o[3] > 0 && o[3] < INFINITY, "[id] ended with [o[3]] mol, which is not an amount of gas")
		// antinoblium replication only copies its gas onto a mixture that already holds the amount it needs: it leaves temperature and moles as they were
		if(id != "antinoblium_replication")
			TEST_ASSERT(o[2] != o[4] || o[3] != o[5], "[id] changed neither the temperature nor the moles of its mixture")
	log_test("gas reaction outcomes:\n[jointext(lines, "\n")]")
	for(var/id in list("plasmafire", "h2fire", "tritfire"))
		var/list/o = outcomes[id]
		TEST_ASSERT_NOTNULL(o, "[id] did not run")
		if(o)
			TEST_ASSERT(o[2] > o[4], "[id] is a fire and left its mixture at [o[2]] K, no hotter than the [o[4]] K it started at")
			TEST_ASSERT(o[3] < o[5], "[id] burns its fuel and left [o[3]] mol of the [o[5]] it started with")

#endif
