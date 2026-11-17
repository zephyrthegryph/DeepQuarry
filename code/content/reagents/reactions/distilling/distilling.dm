/transformation/chem/distilling

CAPABILITIES(/transformation/chem/distilling)
	//how far the reaction proceeds each time it is processed. Used with either REACTION_RATE or HALF_LIFE macros.
	//if less than 1, the reaction will be inhibited if the ratio of products/reagents is too high.
	//0.5 = 50% yield -> reaction will only proceed halfway until products are removed.
	//If limits on reaction rate would leave less than this amount of any reagent (adjusted by the reaction ratios),
	//the reaction goes to completion. This is to prevent reactions from going on forever with tiny reagent amounts.
	configure(transformation(regime = REGIME_DISTILLING, rate = half_life(6), says = "The solution churns.", plays = SFX_EFFECTS_SLOSH))

// Subtypes //

// Biomass
/transformation/chem/distilling/biomass

CAPABILITIES(/transformation/chem/distilling/biomass)
	configure(transformation(name = "Distilling Biomass", id = "distill_biomass",
		takes = list(reagent(REAGENT_ID_BLOOD, 1), reagent(REAGENT_ID_SUGAR, 1), reagent(REAGENT_ID_PHORON, 0.5)),
		makes = list(reagent(REAGENT_ID_BIOMASS, 2.5)), energy = per_step(-2 * 1000), holds = temperature_in(T20C + 80, T20C + 130)))

// Medicinal

/transformation/chem/distilling/synthplas

CAPABILITIES(/transformation/chem/distilling/synthplas)
	configure(transformation(name = "Distilling Synthplas", id = "distill_synthplas",
		takes = list(reagent(REAGENT_ID_PROTEIN, 2), reagent(REAGENT_ID_ANTIBODIES, 1), reagent(REAGENT_ID_BICARIDINE, 1)),
		makes = list(reagent(REAGENT_ID_SYNTHBLOOD_DILUTE, 3)), rate = half_life(15), holds = temperature_in(T0C + 110, T0C + 130)))

// Alcohol
/transformation/chem/distilling/beer

CAPABILITIES(/transformation/chem/distilling/beer)
	configure(transformation(name = "Distilling Beer", id = "distill_beer",
		takes = list(reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_BEER, 2)), rate = half_life(30), holds = temperature_in(T20C, T20C + 2)))

/transformation/chem/distilling/ale

CAPABILITIES(/transformation/chem/distilling/ale)
	configure(transformation(name = "Distilling Ale", id = "distill_ale", takes = list(reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_BEER, 1)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 1)), makes = list(reagent(REAGENT_ID_ALE, 2)), rate = half_life(30),
		energy = per_step(0.5 * 1000), holds = temperature_in(T0C + 7, T0C + 13)))

/transformation/chem/distilling/ethanol

CAPABILITIES(/transformation/chem/distilling/ethanol)
	configure(transformation(name = "Distilling Ethanol", id = "distill_ethanol",
		takes = list(reagent(REAGENT_ID_NUTRIMENT, 1), reagent(REAGENT_ID_WATER, 1), reagent(REAGENT_ID_SUGAR, 1)),
		makes = list(reagent(REAGENT_ID_ETHANOL, 2)), rate = half_life(30), holds = temperature_in(T20C+30, T20C + 40)))

// Unique

/transformation/chem/distilling/cryogel

CAPABILITIES(/transformation/chem/distilling/cryogel)
	configure(transformation(name = "Distilling Cryogellatin", id = "distill_cryoslurry",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 7), reagent(REAGENT_ID_ENZYME, 3), reagent(REAGENT_ID_PLASTICIDE, 3), reagent(REAGENT_ID_FOAMINGAGENT, 2)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 5)), makes = list(reagent(REAGENT_ID_CRYOSLURRY, 1)),
		energy = per_step(20 * 1000), holds = temperature_in(T0C + 10, T20C + 15),
		effects = sets_off(kind = XFORM_FX_FROST, chance = 1, amount = 6)))

// I know this doesn't make sense, and this is a baindaid fix but distiller code refuses to go this low, even with correct variables

/transformation/chem/distilling/hydrogen

CAPABILITIES(/transformation/chem/distilling/hydrogen)
	configure(transformation(name = "Distilling Hydrogen", id = "distill_hydrogen", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_PLATINUM, 1)), blocked_by = list(reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 1)), energy = per_step(1 * 1000),
		holds = xform_all(temperature_in(T20C + 110, T20C + 290), ambient_gas_over(GAS_N2, 10), ambient_gas_under(GAS_O2, 1))))

/transformation/chem/distilling/oxygen

CAPABILITIES(/transformation/chem/distilling/oxygen)
	configure(transformation(name = "Distilling Oxygen", id = "distill_oxygen", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_PLATINUM, 1)), blocked_by = list(reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_OXYGEN, 1)), energy = per_step(3 * 1000),
		holds = xform_all(temperature_in(T20C + 150, T20C + 320), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_O2, 1))))

/transformation/chem/distilling/mineralized_sodium

CAPABILITIES(/transformation/chem/distilling/mineralized_sodium)
	configure(transformation(name = "Distilling Sodium", id = "distill_sodium", takes = list(reagent(REAGENT_ID_MINERALIZEDFLUID, 1)),
		makes = list(reagent(REAGENT_ID_SODIUM, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 600, T20C + 800), ambient_gas_over(GAS_PHORON, 10), ambient_gas_under(GAS_O2, 1))))

/transformation/chem/distilling/mineralized_carbon

CAPABILITIES(/transformation/chem/distilling/mineralized_carbon)
	configure(transformation(name = "Distilling Carbon", id = "distill_carbon", takes = list(reagent(REAGENT_ID_MINERALIZEDFLUID, 1)),
		makes = list(reagent(REAGENT_ID_CARBON, 1)), energy = per_step(-1 * 1000),
		holds = xform_all(temperature_in(T20C + 400, T20C + 800), ambient_gas_over(GAS_O2, 10), ambient_gas_under(GAS_PHORON, 1))))

/transformation/chem/distilling/reduce_salt

CAPABILITIES(/transformation/chem/distilling/reduce_salt)
	configure(transformation(name = "Distilling Sodium", id = "distill_reduce_tablesalt", takes = list(reagent(REAGENT_ID_SODIUMCHLORIDE, 1)),
		makes = list(reagent(REAGENT_ID_SODIUM, 0.5)), energy = per_step(-1 * 1000),
		holds = temperature_in(T20C + 800, T20C + 1000)))
