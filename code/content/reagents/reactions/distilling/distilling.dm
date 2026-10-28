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
		makes = list(reagent(REAGENT_ID_BIOMASS, 6)), energy = per_step(-2 * 1000), holds = temperature_in(T20C + 80, T20C + 130)))


// Medicinal
/transformation/chem/distilling/inaprovalaze

CAPABILITIES(/transformation/chem/distilling/inaprovalaze)
	configure(transformation(name = "Distilling Inaprovalaze", id = "distill_inaprovalaze",
		takes = list(reagent(REAGENT_ID_INAPROVALINE, 2), reagent(REAGENT_ID_FOAMINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_INAPROVALAZE, 2)), rate = half_life(10), holds = temperature_in(T0C + 100, T0C + 120)))



/transformation/chem/distilling/bicaridaze

CAPABILITIES(/transformation/chem/distilling/bicaridaze)
	configure(transformation(name = "Distilling Bicaridaze", id = "distill_bicaridaze",
		takes = list(reagent(REAGENT_ID_BICARIDINE, 2), reagent(REAGENT_ID_FOAMINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_BICARIDAZE, 2)), rate = half_life(10), holds = temperature_in(T0C + 110, T0C + 130)))



/transformation/chem/distilling/dermalaze

CAPABILITIES(/transformation/chem/distilling/dermalaze)
	configure(transformation(name = "Distilling Dermalaze", id = "distill_dermalaze",
		takes = list(reagent(REAGENT_ID_DERMALINE, 2), reagent(REAGENT_ID_FOAMINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_DERMALAZE, 2)), rate = half_life(10), holds = temperature_in(T0C + 115, T0C + 130)))



/transformation/chem/distilling/spacomycaze

CAPABILITIES(/transformation/chem/distilling/spacomycaze)
	configure(transformation(name = "Distilling Spacomycaze", id = "distill_spacomycaze",
		takes = list(reagent(REAGENT_ID_PARACETAMOL, 1), reagent(REAGENT_ID_SPACEACILLIN, 1), reagent(REAGENT_ID_FOAMINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_SPACOMYCAZE, 2)), rate = half_life(10), holds = temperature_in(T0C + 100, T0C + 120)))



/transformation/chem/distilling/tricorlidaze

CAPABILITIES(/transformation/chem/distilling/tricorlidaze)
	configure(transformation(name = "Distilling Tricorlidaze", id = "distill_tricorlidaze",
		takes = list(reagent(REAGENT_ID_TRICORDRAZINE, 1), reagent(REAGENT_ID_STERILIZINE, 1), reagent(REAGENT_ID_FOAMINGAGENT, 1)),
		makes = list(reagent(REAGENT_ID_TRICORLIDAZE, 2)), rate = half_life(10), holds = temperature_in(T0C + 100, T0C + 120)))



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
/transformation/chem/distilling/berserkjuice

CAPABILITIES(/transformation/chem/distilling/berserkjuice)
	configure(transformation(name = "Distilling Brute Juice", id = "distill_brutejuice",
		takes = list(reagent(REAGENT_ID_BIOMASS, 1), reagent(REAGENT_ID_HYPERZINE, 3), reagent(REAGENT_ID_SYNAPTIZINE, 2), reagent(REAGENT_ID_PHORON, 1)),
		makes = list(reagent(REAGENT_ID_BERSERKMED, 3)), energy = per_step(4 * 1000), holds = temperature_in(T0C + 600, T0C + 700),
		effects = sets_off(XFORM_FX_BLAST, chance = 1, blast = list(-1, list(-1, 1), list(1, 2), list(3, 5)))))


/transformation/chem/distilling/cryogel

CAPABILITIES(/transformation/chem/distilling/cryogel)
	configure(transformation(name = "Distilling Cryogellatin", id = "distill_cryoslurry",
		takes = list(reagent(REAGENT_ID_FROSTOIL, 7), reagent(REAGENT_ID_ENZYME, 3), reagent(REAGENT_ID_PLASTICIDE, 3), reagent(REAGENT_ID_FOAMINGAGENT, 2)),
		blocked_by = list(reagent(REAGENT_ID_WATER, 5)), makes = list(reagent(REAGENT_ID_CRYOSLURRY, 1)),
		energy = per_step(20 * 1000), holds = temperature_in(T0C + 10, T20C + 15),
		effects = sets_off(XFORM_FX_FROST, chance = 1, amount = 6)))

// I know this doesn't make sense, and this is a baindaid fix but distiller code refuses to go this low, even with correct variables


/transformation/chem/distilling/lichpowder

CAPABILITIES(/transformation/chem/distilling/lichpowder)
	configure(transformation(name = "Distilling Lichpowder", id = "distill_lichpowder",
		takes = list(reagent(REAGENT_ID_ZOMBIEPOWDER, 2), reagent(REAGENT_ID_LEPORAZINE, 1)),
		makes = list(reagent(REAGENT_ID_LICHPOWDER, 2)), rate = half_life(8), holds = temperature_in(T0C + 100, T0C + 150)))



/transformation/chem/distilling/necroxadone

CAPABILITIES(/transformation/chem/distilling/necroxadone)
	configure(transformation(name = "Distilling Necroxadone", id = "distill_necroxadone",
		takes = list(reagent(REAGENT_ID_LICHPOWDER, 1), reagent(REAGENT_ID_CRYOXADONE, 1), reagent(REAGENT_ID_CARTHATOLINE, 1)),
		catalysts = list(reagent(REAGENT_ID_PHORON, 5)), makes = list(reagent(REAGENT_ID_NECROXADONE, 2)), rate = half_life(20),
		holds = temperature_in(T0C + 90, T0C + 95)))



/transformation/chem/distilling/hydrogen

CAPABILITIES(/transformation/chem/distilling/hydrogen)
	configure(transformation(name = "Distilling Hydrogen", id = "distill_hydrogen", takes = list(reagent(REAGENT_ID_WATER, 1)),
		catalysts = list(reagent(REAGENT_ID_PLATINUM, 1)), blocked_by = list(reagent(REAGENT_ID_CARBON, 1)),
		makes = list(reagent(REAGENT_ID_HYDROGEN, 2)), energy = per_step(1 * 1000),
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



//Grub
//Spider
//Carp
//Meteroid
//Deathclaw

/transformation/chem/distilling/energybooster

CAPABILITIES(/transformation/chem/distilling/energybooster)
	configure(transformation(name = "Distilling Energy Booster", id = "distill_energybooster",
		takes = list(reagent(REAGENT_ID_HYPERZINE, 1), reagent(REAGENT_ID_STIMM, 1), reagent(REAGENT_ID_SHOCKCHEM, 1)),
		makes = list(reagent(REAGENT_ID_ENERGYBOOSTER, 2)), rate = half_life(10), holds = temperature_in(T0C + 180, T0C + 200)))



/transformation/chem/distilling/oceaniccure

CAPABILITIES(/transformation/chem/distilling/oceaniccure)
	configure(transformation(name = "Distilling Oceanic Cure", id = "distill_oceaniccure",
		takes = list(reagent(REAGENT_ID_CUREA, 1), reagent(REAGENT_ID_SOULDEW, 1), reagent(REAGENT_ID_CARPOTOXIN, 1)),
		makes = list(reagent(REAGENT_ID_OCEANICCURE, 2)), rate = half_life(10), holds = temperature_in(T0C + 130, T0C + 150)))



/transformation/chem/distilling/deathclawmutagen

CAPABILITIES(/transformation/chem/distilling/deathclawmutagen)
	configure(transformation(name = "Distilling Deathclaw Mutagen", id = "distill_deathclawmutagen",
		takes = list(reagent(REAGENT_ID_ARITHRAZINE, 1), reagent(REAGENT_ID_MUTAGEN, 1), reagent(REAGENT_ID_DEATHBLOOD, 1)),
		makes = list(reagent(REAGENT_ID_DEATHCLAWMUTAGEN, 2)), rate = half_life(10), holds = temperature_in(T0C + 100, T0C + 120)))



/transformation/chem/distilling/senseenhancer

CAPABILITIES(/transformation/chem/distilling/senseenhancer)
	configure(transformation(name = "Distilling Sense Enhancer", id = "distill_senseenhancer",
		takes = list(reagent(REAGENT_ID_QUADCORD, 1), reagent(REAGENT_ID_MINDBREAKER, 1), reagent(REAGENT_ID_LIQUIDLIFE, 1)),
		makes = list(reagent(REAGENT_ID_SENSEENHANCER, 2)), rate = half_life(10), holds = temperature_in(T0C + 50, T0C + 70)))



/transformation/chem/distilling/heatnullifer

CAPABILITIES(/transformation/chem/distilling/heatnullifer)
	configure(transformation(name = "Distilling heatnullifer", id = "distill_heatnullifer",
		takes = list(reagent(REAGENT_ID_TRAMADOL, 1), reagent(REAGENT_ID_LEPORAZINE, 1), reagent(REAGENT_ID_SPIDERTOXIN, 1)),
		makes = list(reagent(REAGENT_ID_HEATNULLIFER, 2)), rate = half_life(10), holds = temperature_in(T0C + 230, T0C + 250)))



/transformation/chem/distilling/juggernog

CAPABILITIES(/transformation/chem/distilling/juggernog)
	configure(transformation(name = "juggernog", id = "distill_juggernog",
		takes = list(reagent(REAGENT_ID_CARBON, 1), reagent(REAGENT_ID_IRON, 1), reagent(REAGENT_ID_QUADCORD, 1), reagent(REAGENT_ID_NEOLIQUIDFIRE, 1), reagent(REAGENT_ID_RADIUM, 1)),
		makes = list(reagent(REAGENT_ID_JUGGERNOG, 5)), rate = half_life(10), holds = temperature_in(T0C + 180, T0C + 200)))




/transformation/chem/distilling/phoenixbreath

CAPABILITIES(/transformation/chem/distilling/phoenixbreath)
	configure(transformation(name = REAGENT_PHOENIXBREATH, id = REAGENT_ID_PHOENIXBREATH,
		takes = list(reagent(REAGENT_ID_SHOCKCHEM, 1), reagent(REAGENT_ID_NEOTANE, 1), reagent(REAGENT_ID_BURNCARD, 1), reagent(REAGENT_ID_QUADCORD, 1), reagent(REAGENT_ID_MINDBREAKER, 1)),
		makes = list(reagent(REAGENT_ID_PHOENIXBREATH, 6)), holds = temperature_in(T0C + 100, T0C + 120)))


