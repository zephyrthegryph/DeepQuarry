//Most other defines used in reactions are in code/__defines/atmospherics_linda/reactions.dm
#define SET_REACTION_RESULTS(amount) air.reaction_results[type] = amount

// Gas reactions as transformations (doc/rewrite/proposals/transformations.md, wave 2). A reaction is a type under /transformation/gas with a
// transformation(...) entry: the gases and the minimum moles it needs (takes), and its temperature window (holds = temperature_in(lo, hi)).
// /datum/gas_mixture/proc/react() walks xform_rules_in(MEDIUM_GAS, REGIME_GAS) in declaration order (every reaction shares one priority, so the order
// of the compile decides, as the old subtypesof() list did) and runs the react() of each rule whose window and minimum moles hold; react() decides the
// extent and the deltas, gas_react() books the heat. The type is the key of air.reaction_results (SET_REACTION_RESULTS), which a hotspot reads for the
// reactions that declare hotspot = TRUE (SSair.hotspot_reactions).

/transformation/gas

CAPABILITIES(/transformation/gas)
	transformation(medium = MEDIUM_GAS, regime = REGIME_GAS)

/// What the reaction does to `air` this tick: NO_REACTION, or REACTING / VOLATILE_REACTION / STOP_REACTIONS flags. `location` is the turf (or holder) the mixture is on.
/transformation/gas/proc/react(datum/gas_mixture/air, atom/location)
	return NO_REACTION

/// Documentation of the factors that shape the reaction, for the atmos handbook: gas type or heading => text (reaction_factors.dm).
/transformation/gas/proc/factors()
	return list()

/**
 * Steam Condensation/Deposition:
 *
 * Makes turfs slippery.
 * Can frost things if the gas is cold enough.
 */
/transformation/gas/water_vapor
CAPABILITIES(/transformation/gas/water_vapor)
	configure(transformation(name = "Water Vapor Condensation",
		id = "vapor",
		desc = "Water vapor condensation that can make things slippery.",
		takes = list(gas(/datum/gas/water_vapor, MOLES_GAS_VISIBLE)),
		holds = temperature_in(null, WATER_VAPOR_CONDENSATION_POINT)))

/transformation/gas/water_vapor/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	if(!isturf(holder))
		return

	var/turf/open/location = holder
	var/consumed = 0
	switch(air.return_temperature())
		if(-INFINITY to WATER_VAPOR_DEPOSITION_POINT)
			if(location?.freeze_turf())
				consumed = MOLES_GAS_VISIBLE
			// /tg/'s /datum/component/wet_floor + TURF_WET_PERMAFROST
			// flagged this reaction as VOLATILE so its overlay refresh could be
			// skipped on permafrosted turfs. CHOMP has no wet_floor component
			// (its wetness lives directly on /turf/simulated.wet). The flag was
			// a perf optimisation, not a behavioural requirement, so the missing
			// branch only costs a redundant overlay tick. Branch removed.
		if(WATER_VAPOR_DEPOSITION_POINT to WATER_VAPOR_CONDENSATION_POINT)
			if(!isgroundlessturf(location) && !isnoslipturf(location))
				location.water_vapor_gas_act()
			consumed = MOLES_GAS_VISIBLE

	if(consumed)
		air.adjust_moles(/datum/gas/water_vapor, -consumed)
		SET_REACTION_RESULTS(consumed)
		. |= REACTING


/**
 * Dry Heat Sterilization:
 *
 * Clears out pathogens in the air.
 */
/transformation/gas/miaster
CAPABILITIES(/transformation/gas/miaster)
	configure(transformation(name = "Dry Heat Sterilization",
		id = "sterilization",
		desc = "Pathogens cannot survive in a hot environment. Miasma decomposes on high temperature.",
		takes = list(gas(/datum/gas/miasma, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(MIASTER_STERILIZATION_TEMP, null)))

/transformation/gas/miaster/react(datum/gas_mixture/air, datum/holder)
	var/water_vapor = air.get_moles(/datum/gas/water_vapor)
	var/miasma = air.get_moles(/datum/gas/miasma)
	// As the name says it, it needs to be dry
	if(water_vapor && water_vapor / air.total_moles() > MIASTER_STERILIZATION_MAX_HUMIDITY)
		return NO_REACTION

	//Replace miasma with oxygen
	var/cleaned_air = min(miasma, MIASTER_STERILIZATION_RATE_BASE + (air.return_temperature() - MIASTER_STERILIZATION_TEMP) / MIASTER_STERILIZATION_RATE_SCALE)
	//Possibly burning a bit of organic matter through maillard reaction, so a *tiny* bit more heat would be understandable
	gas_react(air, GAS_REACTION_STERILIZATION, cleaned_air, list(/datum/gas/miasma = -cleaned_air, /datum/gas/oxygen = cleaned_air))
	SET_REACTION_RESULTS(cleaned_air)

	return REACTING


// Fire:

/**
 * Plasma combustion:
 *
 * Combustion of oxygen and plasma (mostly treated as hydrocarbons).
 * The reaction rate is dependent on the temperature of the gasmix.
 * May produce either tritium or carbon dioxide and water vapor depending on the fuel/oxydizer ratio of the gasmix.
 */
/transformation/gas/plasmafire
CAPABILITIES(/transformation/gas/plasmafire)
	configure(transformation(name = "Plasma Combustion",
		id = "plasmafire",
		desc = "Combustion of oxygen and plasma. Able to produce tritium or carbon dioxide and water vapor.",
		takes = list(gas(/datum/gas/plasma, MINIMUM_MOLE_COUNT), gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(PLASMA_MINIMUM_BURN_TEMPERATURE, null),
		hotspot = TRUE))

/transformation/gas/plasmafire/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	// This reaction should proceed faster at higher temperatures.
	var/temperature = air.return_temperature()
	var/temperature_scale = 0
	if(temperature > PLASMA_UPPER_TEMPERATURE)
		temperature_scale = 1
	else
		temperature_scale = (temperature - PLASMA_MINIMUM_BURN_TEMPERATURE) / (PLASMA_UPPER_TEMPERATURE-PLASMA_MINIMUM_BURN_TEMPERATURE)
		if(temperature_scale <= 0)
			return

	var/oxygen_burn_ratio = OXYGEN_BURN_RATIO_BASE - temperature_scale
	var/plasma_burn_rate = 0
	var/super_saturation = FALSE // Whether we should make tritium.
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/plasma = air.get_moles(/datum/gas/plasma)
	switch(oxygen / plasma)
		if(SUPER_SATURATION_THRESHOLD to INFINITY)
			plasma_burn_rate = (plasma / PLASMA_BURN_RATE_DELTA) * temperature_scale
			super_saturation = TRUE // Begin to form tritium
		if(PLASMA_OXYGEN_FULLBURN to SUPER_SATURATION_THRESHOLD)
			plasma_burn_rate = (plasma / PLASMA_BURN_RATE_DELTA) * temperature_scale
		else
			plasma_burn_rate = ((oxygen / PLASMA_OXYGEN_FULLBURN) / PLASMA_BURN_RATE_DELTA) * temperature_scale

	if(plasma_burn_rate < MINIMUM_HEAT_CAPACITY)
		return

	plasma_burn_rate = min(plasma_burn_rate, plasma, oxygen *  INVERSE(oxygen_burn_ratio)) //Ensures matter is conserved properly
	var/list/deltas = list(
		/datum/gas/plasma = QUANTIZE(plasma - plasma_burn_rate) - plasma,
		/datum/gas/oxygen = QUANTIZE(oxygen - (plasma_burn_rate * oxygen_burn_ratio)) - oxygen,
	)
	if(super_saturation)
		deltas[/datum/gas/tritium] = plasma_burn_rate
	else
		deltas[/datum/gas/carbon_dioxide] = plasma_burn_rate * 0.75
		deltas[/datum/gas/water_vapor] = plasma_burn_rate * 0.25
	gas_react(air, GAS_REACTION_PLASMA_FIRE, plasma_burn_rate, deltas)

	SET_REACTION_RESULTS((plasma_burn_rate) * (1 + oxygen_burn_ratio))

	// Let the floor know a fire is happening
	var/turf/open/location = holder
	if(istype(location))
		temperature = air.return_temperature()
		if(temperature > FIRE_MINIMUM_TEMPERATURE_TO_EXIST)
			location.hotspot_expose(temperature, CELL_VOLUME)

	. |= REACTING | VOLATILE_REACTION


/**
 * Hydrogen combustion:
 *
 * Combustion of oxygen and hydrogen.
 * Highly exothermic.
 * Creates hotspots.
 */
/transformation/gas/h2fire
CAPABILITIES(/transformation/gas/h2fire)
	configure(transformation(name = "Hydrogen Combustion",
		id = "h2fire",
		desc = "Combustion of hydrogen with oxygen. Can be extremely fast and energetic if a few conditions are fulfilled.",
		takes = list(gas(/datum/gas/hydrogen, MINIMUM_MOLE_COUNT), gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(HYDROGEN_MINIMUM_BURN_TEMPERATURE, null),
		hotspot = TRUE))

/transformation/gas/h2fire/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/hydrogen = air.get_moles(/datum/gas/hydrogen)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/temperature

	var/burned_fuel = min(hydrogen / FIRE_HYDROGEN_BURN_RATE_DELTA, oxygen / (FIRE_HYDROGEN_BURN_RATE_DELTA * HYDROGEN_OXYGEN_FULLBURN), hydrogen, oxygen * INVERSE(0.5))
	if(burned_fuel <= 0 || hydrogen - burned_fuel < 0 || oxygen - burned_fuel * 0.5 < 0) //Shouldn't produce gas from nothing.
		return

	gas_react(air, GAS_REACTION_HYDROGEN_FIRE, burned_fuel, list(/datum/gas/hydrogen = -burned_fuel, /datum/gas/oxygen = -(burned_fuel * 0.5), /datum/gas/water_vapor = burned_fuel))

	SET_REACTION_RESULTS(burned_fuel)

	//let the floor know a fire is happening
	var/turf/open/location = holder
	if(istype(location))
		temperature = air.return_temperature()
		if(temperature > FIRE_MINIMUM_TEMPERATURE_TO_EXIST)
			location.hotspot_expose(temperature, CELL_VOLUME)

	. |= REACTING | VOLATILE_REACTION


/**
 * Tritium combustion:
 *
 * Combustion of oxygen and tritium (treated as hydrogen).
 * Highly exothermic.
 * Creates hotspots.
 * Creates radiation.
 */
/transformation/gas/tritfire
CAPABILITIES(/transformation/gas/tritfire)
	configure(transformation(name = "Tritium Combustion",
		id = "tritfire",
		desc = "Combustion of tritium with oxygen. Can be extremely fast and energetic if a few conditions are fulfilled.",
		takes = list(gas(/datum/gas/tritium, MINIMUM_MOLE_COUNT), gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(TRITIUM_MINIMUM_BURN_TEMPERATURE, null),
		hotspot = TRUE))

/transformation/gas/tritfire/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/tritium = air.get_moles(/datum/gas/tritium)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/temperature

	var/burned_fuel = min(tritium / FIRE_TRITIUM_BURN_RATE_DELTA, oxygen / (FIRE_TRITIUM_BURN_RATE_DELTA * TRITIUM_OXYGEN_FULLBURN), tritium, oxygen * INVERSE(0.5))
	if(burned_fuel <= 0 || tritium - burned_fuel < 0 || oxygen - burned_fuel * 0.5 < 0) //Shouldn't produce gas from nothing.
		return

	var/energy_released = gas_react(air, GAS_REACTION_TRITIUM_FIRE, burned_fuel, list(/datum/gas/tritium = -burned_fuel, /datum/gas/oxygen = -(burned_fuel * 0.5), /datum/gas/water_vapor = burned_fuel))

	SET_REACTION_RESULTS(burned_fuel)

	var/turf/open/location
	if(istype(holder, /datum/pipeline)) //Find the tile the reaction is occurring on, or a random part of the network if it's a pipenet.
		var/datum/pipeline/pipenet = holder
		location = pick(pipenet.members)
	else if(isatom(holder))
		location = holder

	if(location && burned_fuel > TRITIUM_RADIATION_MINIMUM_MOLES && energy_released > TRITIUM_RADIATION_RELEASE_THRESHOLD * (air.return_volume() / CELL_VOLUME) ** ATMOS_RADIATION_VOLUME_EXP && prob(10))
		radiation_pulse(location, max_range = min(sqrt(burned_fuel) / TRITIUM_RADIATION_RANGE_DIVISOR, GAS_REACTION_MAXIMUM_RADIATION_PULSE_RANGE), threshold = TRITIUM_RADIATION_THRESHOLD)

	//let the floor know a fire is happening
	if(istype(location))
		temperature = air.return_temperature()
		if(temperature > FIRE_MINIMUM_TEMPERATURE_TO_EXIST)
			location.hotspot_expose(temperature, CELL_VOLUME)

	. |= REACTING | VOLATILE_REACTION



/**
 * Freon combustion:
 *
 * Combustion of oxygen and freon.
 * Endothermic.
 */
/transformation/gas/freonfire
CAPABILITIES(/transformation/gas/freonfire)
	configure(transformation(name = "Freon Combustion",
		id = "freonfire",
		desc = "Reaction between oxygen and freon that consumes a huge amount of energy and can cool things significantly. Also able to produce hot ice.",
		takes = list(gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT), gas(/datum/gas/freon, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(FREON_TERMINAL_TEMPERATURE, FREON_MAXIMUM_BURN_TEMPERATURE),
		hotspot = TRUE))

/transformation/gas/freonfire/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/temperature = air.return_temperature()
	var/temperature_scale
	if(temperature < FREON_TERMINAL_TEMPERATURE) //stop the reaction when too cold
		temperature_scale = 0
	else if(temperature < FREON_LOWER_TEMPERATURE)
		temperature_scale = 0.5
	else
		temperature_scale = (FREON_MAXIMUM_BURN_TEMPERATURE - temperature) / (FREON_MAXIMUM_BURN_TEMPERATURE - FREON_TERMINAL_TEMPERATURE) //calculate the scale based on the temperature
	if (temperature_scale <= 0)
		return

	var/oxygen_burn_ratio = OXYGEN_BURN_RATIO_BASE - temperature_scale
	var/freon_burn_rate
	var/freon = air.get_moles(/datum/gas/freon)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	if(oxygen < freon * FREON_OXYGEN_FULLBURN)
		freon_burn_rate = ((oxygen / FREON_OXYGEN_FULLBURN) / FREON_BURN_RATE_DELTA) * temperature_scale
	else
		freon_burn_rate = (freon / FREON_BURN_RATE_DELTA) * temperature_scale

	if (freon_burn_rate < MINIMUM_HEAT_CAPACITY)
		return

	freon_burn_rate = min(freon_burn_rate, freon, oxygen * INVERSE(oxygen_burn_ratio)) //Ensures matter is conserved properly
	gas_react(air, GAS_REACTION_FREON_FIRE, freon_burn_rate, list(
		/datum/gas/freon = QUANTIZE(freon - freon_burn_rate) - freon,
		/datum/gas/oxygen = QUANTIZE(oxygen - (freon_burn_rate * oxygen_burn_ratio)) - oxygen,
		/datum/gas/carbon_dioxide = freon_burn_rate,
	))

	if(temperature < HOT_ICE_FORMATION_MAXIMUM_TEMPERATURE && temperature > HOT_ICE_FORMATION_MINIMUM_TEMPERATURE && prob(HOT_ICE_FORMATION_PROB) && isturf(holder))
		new /obj/item/stack/sheet/hot_ice(holder)

	SET_REACTION_RESULTS(freon_burn_rate * (1 + oxygen_burn_ratio))

	var/turf/open/location = holder
	if(istype(location))
		temperature = air.return_temperature()
		if(temperature < FREON_MAXIMUM_BURN_TEMPERATURE)
			location.hotspot_expose(temperature, CELL_VOLUME)

	. |= REACTING | VOLATILE_REACTION


// N2O

/**
 * Nitrous oxide Formation:
 *
 * Formation of N2O.
 * Endothermic.
 * Requires BZ as a catalyst.
 */
/transformation/gas/nitrousformation //formation of n2o, exothermic, requires bz as catalyst
CAPABILITIES(/transformation/gas/nitrousformation)
	configure(transformation(name = "Nitrous Oxide Formation",
		id = "nitrousformation",
		desc = "Production of nitrous oxide with BZ as a catalyst.",
		takes = list(gas(/datum/gas/oxygen, 10), gas(/datum/gas/nitrogen, 20), gas(/datum/gas/bz, 5)),
		holds = temperature_in(N2O_FORMATION_MIN_TEMPERATURE, N2O_FORMATION_MAX_TEMPERATURE)))

/transformation/gas/nitrousformation/react(datum/gas_mixture/air)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/nitrogen = air.get_moles(/datum/gas/nitrogen)
	var/heat_efficiency = min(oxygen * INVERSE(0.5), nitrogen)
	if ((oxygen - heat_efficiency * 0.5 < 0 ) || (nitrogen - heat_efficiency < 0))
		return NO_REACTION // Shouldn't produce gas from nothing.

	gas_react(air, GAS_REACTION_N2O_FORMATION, heat_efficiency, list(/datum/gas/oxygen = -(heat_efficiency * 0.5), /datum/gas/nitrogen = -heat_efficiency, /datum/gas/nitrous_oxide = heat_efficiency))

	SET_REACTION_RESULTS(heat_efficiency)
	return REACTING


/**
 * Nitrous Oxide Decomposition
 *
 * Decomposition of N2O.
 * Exothermic.
 */
/transformation/gas/nitrous_decomp
CAPABILITIES(/transformation/gas/nitrous_decomp)
	configure(transformation(name = "Nitrous Oxide Decomposition",
		id = "nitrous_decomp",
		desc = "Decomposition of nitrous oxide under high temperature.",
		takes = list(gas(/datum/gas/nitrous_oxide, MINIMUM_MOLE_COUNT * 2)),
		holds = temperature_in(N2O_DECOMPOSITION_MIN_TEMPERATURE, N2O_DECOMPOSITION_MAX_TEMPERATURE)))

/transformation/gas/nitrous_decomp/react(datum/gas_mixture/air, datum/holder)
	var/nitrous_oxide = air.get_moles(/datum/gas/nitrous_oxide)
	var/temperature = air.return_temperature()
	var/burned_fuel = (nitrous_oxide / N2O_DECOMPOSITION_RATE_DIVISOR) * ((temperature - N2O_DECOMPOSITION_MIN_SCALE_TEMP) * (temperature - N2O_DECOMPOSITION_MAX_SCALE_TEMP) / (N2O_DECOMPOSITION_SCALE_DIVISOR))
	if(burned_fuel <= 0 || nitrous_oxide - burned_fuel < 0)
		return NO_REACTION

	gas_react(air, GAS_REACTION_N2O_DECOMPOSITION, burned_fuel, list(/datum/gas/nitrous_oxide = -burned_fuel, /datum/gas/nitrogen = burned_fuel, /datum/gas/oxygen = burned_fuel / 2))

	SET_REACTION_RESULTS(burned_fuel)
	. |= REACTING


// BZ

/**
 * BZ Formation
 *
 * Formation of BZ by combining plasma and nitrous oxide at low pressures.
 * Exothermic.
 */
/transformation/gas/bzformation
CAPABILITIES(/transformation/gas/bzformation)
	configure(transformation(name = "BZ Gas Formation",
		id = "bzformation",
		desc = "Production of BZ using plasma and nitrous oxide.",
		takes = list(gas(/datum/gas/nitrous_oxide, 10), gas(/datum/gas/plasma, 10)),
		holds = temperature_in(null, BZ_FORMATION_MAX_TEMPERATURE)))

/transformation/gas/bzformation/react(datum/gas_mixture/air)
	var/nitrous_oxide = air.get_moles(/datum/gas/nitrous_oxide)
	var/plasma = air.get_moles(/datum/gas/plasma)
	var/pressure = air.return_pressure()
	var/volume = air.return_volume()
	var/environment_effciency = volume/pressure		//More volume and less pressure gives better rates
	var/ratio_efficency = min(nitrous_oxide/plasma, 1)  //Less n2o than plasma give lower rates
	var/nitrous_oxide_decomposed_factor = max(4 * (plasma / (nitrous_oxide + plasma) - 0.75), 0) // Nitrous oxide decomposes when there are more than 3 parts plasma per n2o.
	var/bz_formed = min(0.01 * ratio_efficency * environment_effciency, nitrous_oxide * INVERSE(0.4), plasma * INVERSE(0.8 * (1 - nitrous_oxide_decomposed_factor)))

	if (nitrous_oxide - bz_formed * 0.4 < 0  || plasma - 0.8 * bz_formed * (1 - nitrous_oxide_decomposed_factor) < 0 || bz_formed <= 0)
		return NO_REACTION

	/**
	*If n2o-plasma ratio is less than 1:3 start decomposing n2o.
	*Rate of decomposition vs BZ production increases as n2o concentration gets lower
	*Plasma acts as a catalyst on decomposition, so it doesn't get consumed in the process.
	*N2O decomposes with its normal decomposition energy
	*/
	var/list/deltas = list()
	if (nitrous_oxide_decomposed_factor>0)
		var/amount_decomposed = 0.4 * bz_formed * nitrous_oxide_decomposed_factor
		deltas[/datum/gas/nitrogen] = amount_decomposed
		deltas[/datum/gas/oxygen] = 0.5 * amount_decomposed
	deltas[/datum/gas/bz] = bz_formed * (1-nitrous_oxide_decomposed_factor)
	deltas[/datum/gas/nitrous_oxide] = -(0.4 * bz_formed)
	deltas[/datum/gas/plasma] = -(0.8 * bz_formed * (1-nitrous_oxide_decomposed_factor))
	gas_react(air, GAS_REACTION_BZ_FORMATION, bz_formed, deltas, nitrous_oxide_decomposed_factor)

	SET_REACTION_RESULTS(bz_formed)
	return REACTING


// Pluoxium

/**
 * Pluoxium Formation:
 *
 * Consumes a tiny amount of tritium to convert CO2 and oxygen to pluoxium.
 * Exothermic.
 */
/transformation/gas/pluox_formation
CAPABILITIES(/transformation/gas/pluox_formation)
	configure(transformation(name = "Pluoxium Formation",
		id = "pluox_formation",
		desc = "Alternate production for pluoxium which uses tritium.",
		takes = list(gas(/datum/gas/carbon_dioxide, MINIMUM_MOLE_COUNT), gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT), gas(/datum/gas/tritium, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(PLUOXIUM_FORMATION_MIN_TEMP, PLUOXIUM_FORMATION_MAX_TEMP)))

/transformation/gas/pluox_formation/react(datum/gas_mixture/air, datum/holder)
	var/carbon_dioxide = air.get_moles(/datum/gas/carbon_dioxide)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/tritium = air.get_moles(/datum/gas/tritium)
	var/produced_amount = min(PLUOXIUM_FORMATION_MAX_RATE, carbon_dioxide, oxygen * INVERSE(0.5), tritium * INVERSE(0.01))
	if (produced_amount <= 0 || carbon_dioxide - produced_amount < 0 || oxygen - produced_amount * 0.5 < 0 || tritium - produced_amount * 0.01 < 0)
		return NO_REACTION

	gas_react(air, GAS_REACTION_PLUOXIUM_FORMATION, produced_amount, list(
		/datum/gas/carbon_dioxide = -produced_amount,
		/datum/gas/oxygen = -(produced_amount * 0.5),
		/datum/gas/tritium = -(produced_amount * 0.01),
		/datum/gas/pluoxium = produced_amount,
		/datum/gas/hydrogen = produced_amount * 0.01,
	))

	SET_REACTION_RESULTS(produced_amount)
	return REACTING


// Nitrium

/**
 * Nitrium Formation:
 *
 * The formation of nitrium.
 * Endothermic.
 * Requires BZ.
 */
/transformation/gas/nitrium_formation
CAPABILITIES(/transformation/gas/nitrium_formation)
	configure(transformation(name = "Nitrium Formation",
		id = "nitrium_formation",
		desc = "Production of nitrium from BZ, tritium, and nitrogen.",
		takes = list(gas(/datum/gas/tritium, 20), gas(/datum/gas/nitrogen, 10), gas(/datum/gas/bz, 5)),
		holds = temperature_in(NITRIUM_FORMATION_MIN_TEMP, null)))

/transformation/gas/nitrium_formation/react(datum/gas_mixture/air)
	var/tritium = air.get_moles(/datum/gas/tritium)
	var/nitrogen = air.get_moles(/datum/gas/nitrogen)
	var/bz = air.get_moles(/datum/gas/bz)
	var/temperature = air.return_temperature()
	var/heat_efficiency = min(temperature / NITRIUM_FORMATION_TEMP_DIVISOR, tritium, nitrogen, bz * INVERSE(0.05))

	if( heat_efficiency <= 0 || (tritium - heat_efficiency < 0 ) || (nitrogen - heat_efficiency < 0) || (bz - heat_efficiency * 0.05 < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	//bz gets consumed to balance the nitrium production and not make it too common and/or easy; the air cools down when reacting
	gas_react(air, GAS_REACTION_NITRIUM_FORMATION, heat_efficiency, list(/datum/gas/tritium = -heat_efficiency, /datum/gas/nitrogen = -heat_efficiency, /datum/gas/bz = -(heat_efficiency * 0.05), /datum/gas/nitrium = heat_efficiency))

	SET_REACTION_RESULTS(heat_efficiency)
	return REACTING


/**
 * Nitrium Decomposition:
 *
 * The decomposition of nitrium.
 * Exothermic.
 * Requires oxygen as catalyst.
 */
/transformation/gas/nitrium_decomposition
CAPABILITIES(/transformation/gas/nitrium_decomposition)
	configure(transformation(name = "Nitrium Decomposition",
		id = "nitrium_decomp",
		desc = "Decomposition of nitrium when exposed to oxygen under normal temperatures.",
		takes = list(gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT), gas(/datum/gas/nitrium, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(null, NITRIUM_DECOMPOSITION_MAX_TEMP)))

/transformation/gas/nitrium_decomposition/react(datum/gas_mixture/air)
	var/nitrium = air.get_moles(/datum/gas/nitrium)
	var/temperature = air.return_temperature()

	//This reaction is aggressively slow. like, a tenth of a mole per fire slow. Keep that in mind
	var/heat_efficiency = min(temperature / NITRIUM_DECOMPOSITION_TEMP_DIVISOR, nitrium)

	if (heat_efficiency <= 0 || (nitrium - heat_efficiency < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	gas_react(air, GAS_REACTION_NITRIUM_DECOMPOSITION, heat_efficiency, list(/datum/gas/nitrium = -heat_efficiency, /datum/gas/hydrogen = heat_efficiency, /datum/gas/nitrogen = heat_efficiency)) //the air heats up when reacting

	SET_REACTION_RESULTS(heat_efficiency)
	return REACTING


/**
 * Freon formation:
 *
 * The formation of freon.
 * Endothermic.
 */
/transformation/gas/freonformation
CAPABILITIES(/transformation/gas/freonformation)
	configure(transformation(name = "Freon Formation",
		id = "freonformation",
		desc = "Production of freon using plasma, carbon dioxide, and BZ under high temperature.",
		takes = list(gas(/datum/gas/plasma, MINIMUM_MOLE_COUNT * 6), gas(/datum/gas/carbon_dioxide, MINIMUM_MOLE_COUNT * 3), gas(/datum/gas/bz, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(FREON_FORMATION_MIN_TEMPERATURE, null)))

/transformation/gas/freonformation/react(datum/gas_mixture/air)
	var/plasma = air.get_moles(/datum/gas/plasma)
	var/carbon_dioxide = air.get_moles(/datum/gas/carbon_dioxide)
	var/bz = air.get_moles(/datum/gas/bz)
	var/temperature = air.return_temperature()
	var/minimal_mole_factor = min(plasma *  INVERSE(0.6), bz *  INVERSE(0.1), carbon_dioxide *  INVERSE(0.3))

	var/equation_first_part = NUM_E ** (-(((temperature - 800) / 200) ** 2))
	var/equation_second_part = 3 / (1 + NUM_E ** (-0.001 * (temperature - 6000)))
	var/heat_factor = equation_first_part + equation_second_part

	var/freon_formed = min(heat_factor * minimal_mole_factor * 0.05, plasma * INVERSE(0.6), carbon_dioxide * INVERSE(0.3), bz * INVERSE(0.1))
	if (freon_formed <= 0 || (plasma - freon_formed * 0.6 < 0 ) || (carbon_dioxide - freon_formed * 0.3 < 0) || (bz - freon_formed * 0.1 < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	gas_react(air, GAS_REACTION_FREON_FORMATION, freon_formed, list(/datum/gas/plasma = -(freon_formed * 0.6), /datum/gas/carbon_dioxide = -(freon_formed * 0.3), /datum/gas/bz = -(freon_formed * 0.1), /datum/gas/freon = freon_formed))

	SET_REACTION_RESULTS(freon_formed)
	return REACTING


/**
 * Hyper-Noblium Formation:
 *
 * Extremely exothermic.
 * Requires very low temperatures.
 * Due to its high mass, hyper-noblium uses large amounts of nitrogen and tritium.
 * BZ can be used as a catalyst to make it less exothermic.
 */
/transformation/gas/nobliumformation
CAPABILITIES(/transformation/gas/nobliumformation)
	configure(transformation(name = "Hyper-Noblium Condensation",
		id = "nobformation",
		desc = "Production of hyper-noblium from nitrogen and tritium under very low temperatures. Extremely energetic.",
		takes = list(gas(/datum/gas/nitrogen, 10), gas(/datum/gas/tritium, 5)),
		holds = temperature_in(NOBLIUM_FORMATION_MIN_TEMP, NOBLIUM_FORMATION_MAX_TEMP)))

/transformation/gas/nobliumformation/react(datum/gas_mixture/air)
	. = NO_REACTION
	var/nitrogen = air.get_moles(/datum/gas/nitrogen)
	var/tritium = air.get_moles(/datum/gas/tritium)
	var/bz = air.get_moles(/datum/gas/bz)
	var/reduction_factor = clamp(tritium / (tritium + bz), 0.001 , 1) //reduces trit consumption in presence of bz upward to 0.1% reduction
	var/nob_formed = min((nitrogen + tritium) * 0.01, tritium * INVERSE(5 * reduction_factor), nitrogen * INVERSE(10))

	//calling QUANTIZE on results to round very small floating point values.
	if (QUANTIZE(nob_formed) <= 0 || (QUANTIZE(tritium - 5 * nob_formed * reduction_factor) < 0) || (QUANTIZE(nitrogen - 10 * nob_formed) < 0))
		return

	// I'm not going to nitpick, but N20H10 feels like it should be an explosive more than anything. BZ makes it less exothermic.
	gas_react(air, GAS_REACTION_NOBLIUM_FORMATION, nob_formed, list(/datum/gas/tritium = -(5 * nob_formed * reduction_factor), /datum/gas/nitrogen = -(10 * nob_formed), /datum/gas/hypernoblium = nob_formed), bz)

	SET_REACTION_RESULTS(nob_formed)
	. |= REACTING | VOLATILE_REACTION


// Halon

/**
 * Halon Combustion:
 *
 * Consumes a large amount of oxygen relative to the amount of halon consumed.
 * Produces carbon dioxide.
 * Endothermic.
 */
/transformation/gas/halon_o2removal
CAPABILITIES(/transformation/gas/halon_o2removal)
	configure(transformation(name = "Halon Oxygen Absorption",
		id = "halon_o2removal",
		desc = "Halon interaction with oxygen that can be used to snuff fires out.",
		takes = list(gas(/datum/gas/halon, MINIMUM_MOLE_COUNT), gas(/datum/gas/oxygen, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(HALON_COMBUSTION_MIN_TEMPERATURE, null)))

/transformation/gas/halon_o2removal/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/halon = air.get_moles(/datum/gas/halon)
	var/oxygen = air.get_moles(/datum/gas/oxygen)
	var/temperature = air.return_temperature()

	var/heat_efficiency = min(temperature / HALON_COMBUSTION_TEMPERATURE_SCALE, halon, oxygen * INVERSE(20))
	if (heat_efficiency <= 0 || (halon - heat_efficiency < 0 ) || (oxygen - heat_efficiency * 20 < 0)) //Shouldn't produce gas from nothing.
		return

	gas_react(air, GAS_REACTION_HALON_COMBUSTION, heat_efficiency, list(/datum/gas/halon = -heat_efficiency, /datum/gas/oxygen = -(heat_efficiency * 20), /datum/gas/pluoxium = heat_efficiency * 2.5))

	SET_REACTION_RESULTS(heat_efficiency * 5)

	// Resin foam effects.
	var/turf/open/location = holder
	// /tg/'s foam type is /obj/effect/particle_effect/fluid/foam; CHOMP
	// has /obj/effect/effect/foam. Use CHOMP's path so the locate() resolves.
	var/obj/effect/effect/foam/foam = locate_within(location, /obj/effect/effect/foam)
	var/obj/structure/foamedmetal/resin = locate_within(location, /obj/structure/foamedmetal)
	if(heat_efficiency > HALON_COMBUSTION_MINIMUM_RESIN_MOLES && isopenturf(location) && !foam && !resin) // Don't resin if there is aleady resin or we are not in an open turf.
		do_foam(amount = HALON_COMBUSTION_RESIN_VOLUME, holder = holder, location = location, foam_type = /datum/effect_system/fluid_spread/foam/metal/resin/halon)
		. |= VOLATILE_REACTION

	. |= REACTING


// Healium

/**
 * Healium Formation:
 *
 * Exothermic
 */
/transformation/gas/healium_formation
CAPABILITIES(/transformation/gas/healium_formation)
	configure(transformation(name = "Healium Formation",
		id = "healium_formation",
		desc = "Production of healium using BZ and freon.",
		takes = list(gas(/datum/gas/bz, MINIMUM_MOLE_COUNT), gas(/datum/gas/freon, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(HEALIUM_FORMATION_MIN_TEMP, HEALIUM_FORMATION_MAX_TEMP)))

/transformation/gas/healium_formation/react(datum/gas_mixture/air, datum/holder)
	var/bz = air.get_moles(/datum/gas/bz)
	var/freon = air.get_moles(/datum/gas/freon)
	var/temperature = air.return_temperature()
	var/heat_efficiency = min(temperature * 0.3, freon * INVERSE(2.75), bz * INVERSE(0.25))
	if (heat_efficiency <= 0 || (freon - heat_efficiency * 2.75 < 0 ) || (bz - heat_efficiency * 0.25 < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	gas_react(air, GAS_REACTION_HEALIUM_FORMATION, heat_efficiency, list(/datum/gas/freon = -(heat_efficiency * 2.75), /datum/gas/bz = -(heat_efficiency * 0.25), /datum/gas/healium = heat_efficiency * 3))

	SET_REACTION_RESULTS(heat_efficiency * 3)
	return REACTING

/**
 * Zauker Formation:
 *
 * Exothermic.
 * Requires Hypernoblium.
 */
/transformation/gas/zauker_formation
CAPABILITIES(/transformation/gas/zauker_formation)
	configure(transformation(name = "Zauker Formation",
		id = "zauker_formation",
		desc = "Production of zauker using hyper-noblium and nitrium under very high temperatures.",
		takes = list(gas(/datum/gas/hypernoblium, MINIMUM_MOLE_COUNT), gas(/datum/gas/nitrium, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(ZAUKER_FORMATION_MIN_TEMPERATURE, ZAUKER_FORMATION_MAX_TEMPERATURE)))

/transformation/gas/zauker_formation/react(datum/gas_mixture/air, datum/holder)
	var/hypernoblium = air.get_moles(/datum/gas/hypernoblium)
	var/nitrium = air.get_moles(/datum/gas/nitrium)
	var/temperature = air.return_temperature()

	var/heat_efficiency = min(temperature * ZAUKER_FORMATION_TEMPERATURE_SCALE, hypernoblium * INVERSE(0.01), nitrium * INVERSE(0.5))
	if (heat_efficiency <= 0 || (hypernoblium - heat_efficiency * 0.01 < 0 ) || (nitrium - heat_efficiency * 0.5 < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	gas_react(air, GAS_REACTION_ZAUKER_FORMATION, heat_efficiency, list(/datum/gas/hypernoblium = -(heat_efficiency * 0.01), /datum/gas/nitrium = -(heat_efficiency * 0.5), /datum/gas/zauker = heat_efficiency * 0.5))

	SET_REACTION_RESULTS(heat_efficiency * 0.5)
	return REACTING


/**
 * Zauker Decomposition:
 *
 * Occurs in the presence of nitrogen to prevent zauker floods.
 * Exothermic.
 */
/transformation/gas/zauker_decomp
CAPABILITIES(/transformation/gas/zauker_decomp)
	configure(transformation(name = "Zauker Decomposition",
		id = "zauker_decomp",
		desc = "Decomposition of zauker when exposed to nitrogen.",
		takes = list(gas(/datum/gas/nitrogen, MINIMUM_MOLE_COUNT), gas(/datum/gas/zauker, MINIMUM_MOLE_COUNT))))

/transformation/gas/zauker_decomp/react(datum/gas_mixture/air, datum/holder)
	var/nitrogen = air.get_moles(/datum/gas/nitrogen)
	var/zauker = air.get_moles(/datum/gas/zauker)
	var/burned_fuel = min(ZAUKER_DECOMPOSITION_MAX_RATE, nitrogen, zauker)
	if (burned_fuel <= 0 || zauker - burned_fuel < 0)
		return NO_REACTION

	gas_react(air, GAS_REACTION_ZAUKER_DECOMPOSITION, burned_fuel, list(/datum/gas/zauker = -burned_fuel, /datum/gas/oxygen = burned_fuel * 0.3, /datum/gas/nitrogen = burned_fuel * 0.7))

	SET_REACTION_RESULTS(burned_fuel)
	return REACTING


// Proto-Nitrate

/**
 * Proto-Nitrate formation:
 *
 * Exothermic.
 */
/transformation/gas/proto_nitrate_formation
CAPABILITIES(/transformation/gas/proto_nitrate_formation)
	configure(transformation(name = "Proto Nitrate Formation",
		id = "proto_nitrate_formation",
		desc = "Production of proto-nitrate from pluoxium and hydrogen under high temperatures.",
		takes = list(gas(/datum/gas/pluoxium, MINIMUM_MOLE_COUNT), gas(/datum/gas/hydrogen, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(PN_FORMATION_MIN_TEMPERATURE, PN_FORMATION_MAX_TEMPERATURE)))

/transformation/gas/proto_nitrate_formation/react(datum/gas_mixture/air, datum/holder)
	var/pluoxium = air.get_moles(/datum/gas/pluoxium)
	var/hydrogen = air.get_moles(/datum/gas/hydrogen)
	var/temperature = air.return_temperature()

	var/heat_efficiency = min(temperature * 0.005, pluoxium * INVERSE(0.2), hydrogen * INVERSE(2))
	if (heat_efficiency <= 0 || (pluoxium - heat_efficiency * 0.2 < 0 ) || (hydrogen - heat_efficiency * 2 < 0)) //Shouldn't produce gas from nothing.
		return NO_REACTION

	gas_react(air, GAS_REACTION_PN_FORMATION, heat_efficiency, list(/datum/gas/hydrogen = -(heat_efficiency * 2), /datum/gas/pluoxium = -(heat_efficiency * 0.2), /datum/gas/proto_nitrate = heat_efficiency * 2.2))

	SET_REACTION_RESULTS(heat_efficiency * 2.2)
	return REACTING

/**
 * Proto-Nitrate Hydrogen Conversion
 *
 * Converts hydrogen into proto-nitrate.
 * Endothermic.
 */
/transformation/gas/proto_nitrate_hydrogen_response
CAPABILITIES(/transformation/gas/proto_nitrate_hydrogen_response)
	configure(transformation(name = "Proto Nitrate Hydrogen Response",
		id = "proto_nitrate_hydrogen_response",
		desc = "Conversion of hydrogen into proto nitrate.",
		takes = list(gas(/datum/gas/proto_nitrate, MINIMUM_MOLE_COUNT), gas(/datum/gas/hydrogen, PN_HYDROGEN_CONVERSION_THRESHOLD))))

/transformation/gas/proto_nitrate_hydrogen_response/react(datum/gas_mixture/air, datum/holder)
	var/proto_nitrate = air.get_moles(/datum/gas/proto_nitrate)
	var/hydrogen = air.get_moles(/datum/gas/hydrogen)
	var/produced_amount = min(PN_HYDROGEN_CONVERSION_MAX_RATE, hydrogen, proto_nitrate)
	if (produced_amount <= 0 || hydrogen - produced_amount < 0)
		return NO_REACTION

	gas_react(air, GAS_REACTION_PN_HYDROGEN_RESPONSE, produced_amount, list(/datum/gas/hydrogen = -produced_amount, /datum/gas/proto_nitrate = produced_amount * 0.5))

	SET_REACTION_RESULTS(produced_amount * 0.5)
	return REACTING

/**
 * Proto-Nitrate Tritium De-irradiation
 *
 * Converts tritium to hydrogen.
 * Releases radiation.
 * Exothermic.
 */
/transformation/gas/proto_nitrate_tritium_response
CAPABILITIES(/transformation/gas/proto_nitrate_tritium_response)
	configure(transformation(name = "Proto Nitrate Tritium Response",
		id = "proto_nitrate_tritium_response",
		desc = "Conversion of tritium into hydrogen that consumes a small amount of proto-nitrate.",
		takes = list(gas(/datum/gas/proto_nitrate, MINIMUM_MOLE_COUNT), gas(/datum/gas/tritium, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(PN_TRITIUM_CONVERSION_MIN_TEMP, PN_TRITIUM_CONVERSION_MAX_TEMP)))

/transformation/gas/proto_nitrate_tritium_response/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/proto_nitrate = air.get_moles(/datum/gas/proto_nitrate)
	var/tritium = air.get_moles(/datum/gas/tritium)
	var/temperature = air.return_temperature()
	var/produced_amount = min(temperature / 34 * (tritium * proto_nitrate) / (tritium + 10 * proto_nitrate), tritium, proto_nitrate * INVERSE(0.01))
	if(tritium - produced_amount < 0 || proto_nitrate - produced_amount * 0.01 < 0)
		return

	var/energy_released = gas_react(air, GAS_REACTION_PN_TRITIUM_RESPONSE, produced_amount, list(/datum/gas/proto_nitrate = -(produced_amount * 0.01), /datum/gas/tritium = -produced_amount, /datum/gas/hydrogen = produced_amount))

	SET_REACTION_RESULTS(produced_amount)
	var/turf/open/location
	if(istype(holder,/datum/pipeline)) //Find the tile the reaction is occurring on, or a random part of the network if it's a pipenet.
		var/datum/pipeline/pipenet = holder
		location = pick(pipenet.members)
	else if(isatom(holder))
		location = holder
	if (location && energy_released > PN_TRITIUM_CONVERSION_RAD_RELEASE_THRESHOLD * (air.return_volume() / CELL_VOLUME) ** ATMOS_RADIATION_VOLUME_EXP)
		. |= VOLATILE_REACTION
		radiation_pulse(location, max_range = min(sqrt(produced_amount) / PN_TRITIUM_RAD_RANGE_DIVISOR, GAS_REACTION_MAXIMUM_RADIATION_PULSE_RANGE), threshold = PN_TRITIUM_RAD_THRESHOLD)

	if(energy_released)
		. |= REACTING

/**
 * Proto-Nitrate BZase Action
 *
 * Breaks BZ down into nitrogen, helium, and plasma in the presence of proto-nitrate.
 */
/transformation/gas/proto_nitrate_bz_response
CAPABILITIES(/transformation/gas/proto_nitrate_bz_response)
	configure(transformation(name = "Proto Nitrate BZ Response",
		id = "proto_nitrate_bz_response",
		desc = "Breakdown of BZ into nitrogen, helium, and plasma by proto-nitrate under low temperatures.",
		takes = list(gas(/datum/gas/proto_nitrate, MINIMUM_MOLE_COUNT), gas(/datum/gas/bz, MINIMUM_MOLE_COUNT)),
		holds = temperature_in(PN_BZASE_MIN_TEMP, PN_BZASE_MAX_TEMP)))

/transformation/gas/proto_nitrate_bz_response/react(datum/gas_mixture/air, datum/holder)
	. = NO_REACTION
	var/proto_nitrate = air.get_moles(/datum/gas/proto_nitrate)
	var/bz = air.get_moles(/datum/gas/bz)
	var/temperature = air.return_temperature()
	var/consumed_amount = min(temperature / 2240 * bz * proto_nitrate / (bz + proto_nitrate), bz, proto_nitrate)
	if (consumed_amount <= 0 || bz - consumed_amount < 0)
		return

	var/energy_released = gas_react(air, GAS_REACTION_PN_BZ_RESPONSE, consumed_amount, list(/datum/gas/bz = -consumed_amount, /datum/gas/nitrogen = consumed_amount * 0.4, /datum/gas/helium = consumed_amount * 1.6, /datum/gas/plasma = consumed_amount * 0.8))

	SET_REACTION_RESULTS(consumed_amount)
	var/turf/open/location
	if(istype(holder,/datum/pipeline)) //Find the tile the reaction is occurring on, or a random part of the network if it's a pipenet.
		var/datum/pipeline/pipenet = holder
		location = pick(pipenet.members)
	else if(isatom(holder))
		location = holder
	if (location && energy_released > PN_BZASE_RAD_RELEASE_THRESHOLD * (air.return_volume() / CELL_VOLUME) ** ATMOS_RADIATION_VOLUME_EXP)
		. |= VOLATILE_REACTION
		///How many nuclear particles will fire in this reaction.
		var/nuclear_particle_amount = min(round(consumed_amount / PN_BZASE_NUCLEAR_PARTICLE_DIVISOR), PN_BZASE_NUCLEAR_PARTICLE_MAXIMUM)
		for(var/i in 1 to nuclear_particle_amount)
			location.fire_nuclear_particle()
		radiation_pulse(location, max_range = min(sqrt(consumed_amount - nuclear_particle_amount * PN_BZASE_NUCLEAR_PARTICLE_RADIATION_ENERGY_CONVERSION) / PN_BZASE_RAD_RANGE_DIVISOR, GAS_REACTION_MAXIMUM_RADIATION_PULSE_RANGE), threshold = PN_BZASE_RAD_THRESHOLD)
		visible_hallucination_pulse(location, 1, consumed_amount * 2 SECONDS)

	. |= REACTING

/transformation/gas/antinoblium_replication
CAPABILITIES(/transformation/gas/antinoblium_replication)
	configure(transformation(name = "Antinoblium Replication",
		id = "antinoblium_replication",
		desc = "Antinoblium breaks down all gases into more of itself.",
		takes = list(gas(/datum/gas/antinoblium, MOLES_GAS_VISIBLE)),
		holds = temperature_in(REACTION_OPPRESSION_MIN_TEMP, null)))

/**
 * Antinoblium Recplication
 *
 * Converts all gases into antinoblium.
 */
/transformation/gas/antinoblium_replication/react(datum/gas_mixture/air, datum/holder)
	. = REACTING | VOLATILE_REACTION
	// get_gases() returns an assoc list keyed by gas-type PATH (present gases);
	// iterating it yields the type-path keys. Exclude antinoblium itself by path.
	var/list/cached_gases = air.get_gases()
	var/antinoblium_id = /datum/gas/antinoblium
	var/total_moles = air.total_moles()
	var/antinoblium_moles = air.get_moles(/datum/gas/antinoblium)
	var/total_not_antinoblium_moles = total_moles - antinoblium_moles
	var/reaction_rate = min(antinoblium_moles / ANTINOBLIUM_CONVERSION_DIVISOR, total_not_antinoblium_moles)
	if(total_not_antinoblium_moles < MINIMUM_MOLE_COUNT) // Clear up the remaining gases if this condition is met.
		. = NO_REACTION
		reaction_rate = total_not_antinoblium_moles
	var/list/deltas = list()
	for(var/id in cached_gases)
		if(id == antinoblium_id)
			continue
		var/gas_moles = air.get_moles(id)
		// Let the gases get properly cleared while avoiding potential division by 0.
		deltas[id] = . == NO_REACTION ? -gas_moles : -(reaction_rate * gas_moles / total_not_antinoblium_moles)
	deltas[/datum/gas/antinoblium] = reaction_rate
	// No enthalpy: the mixture keeps its thermal energy over its new heat capacity.
	gas_react(air, GAS_REACTION_KEEP_TEMPERATURE, reaction_rate, deltas)

	SET_REACTION_RESULTS(reaction_rate)


#undef SET_REACTION_RESULTS
