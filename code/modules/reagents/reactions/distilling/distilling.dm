/datum/decl/chemical_reaction/distilling
	name = REAGENT_DEVELOPER_WARNING // Unit test ignore

	//how far the reaction proceeds each time it is processed. Used with either REACTION_RATE or HALF_LIFE macros.
	reaction_rate = HALF_LIFE(6)

	//if less than 1, the reaction will be inhibited if the ratio of products/reagents is too high.
	//0.5 = 50% yield -> reaction will only proceed halfway until products are removed.

	//If limits on reaction rate would leave less than this amount of any reagent (adjusted by the reaction ratios),
	//the reaction goes to completion. This is to prevent reactions from going on forever with tiny reagent amounts.

	mix_message = "The solution churns."
	reaction_sound = SFX_EFFECTS_SLOSH


	var/temp_shift = 0 // How much the temperature changes when the reaction occurs.

	var/require_xgm_gas = null
	var/rejects_xgm_gas = null
	var/maximum_xgm_pressure = null
	var/minimum_xgm_pressure = null
	var/consumes_xgm_gas = 0 // Mols of gas consumed during reaction

TYPE_TABLE_DECLARE(/datum/decl/chemical_reaction/distilling, distilling_temp_range, list(T0C, T20C))

/datum/decl/chemical_reaction/distilling/can_happen(datum/reagents/holder)
	if(!istype(holder, /datum/reagents/distilling))
		return FALSE

	// return_air() will get the current turf for most things unless overriden to use a tank or such!
	var/datum/gas_mixture/GM = holder.my_atom.return_air()
	if(require_xgm_gas || rejects_xgm_gas || minimum_xgm_pressure || maximum_xgm_pressure)
		if(!GM)
			return
		// XGM string-id .gas[id] → LINDA macro that translates to .gases lookup.
		if(require_xgm_gas && LINDA_GAS_AMT(GM, require_xgm_gas) <= 10)
			return
		if(rejects_xgm_gas && LINDA_GAS_AMT(GM, rejects_xgm_gas) >= 1)
			return
		if(minimum_xgm_pressure && GM.return_pressure() < minimum_xgm_pressure)
			return
		if(maximum_xgm_pressure && GM.return_pressure() > maximum_xgm_pressure)
			return

	// The holder's temperature: the bunsen burner's or distillery's heat body (H3).
	var/temperature = holder.get_temperature()
	if(temperature < TYPE_TABLE_GET(src, distilling_temp_range)[1] || temperature > TYPE_TABLE_GET(src, distilling_temp_range)[2])
		return FALSE

	return ..()

/datum/decl/chemical_reaction/distilling/on_reaction(datum/reagents/holder, created_volume)
	// Handle gas consumption
	var/datum/gas_mixture/GM = holder.my_atom.return_air()
	if(consumes_xgm_gas != 0 && GM)
		GM.adjust_gas(require_xgm_gas,-consumes_xgm_gas, TRUE)

	// Distilling can change gas temps, handle it here.
	if(temp_shift != 0)
		if(istype(holder.my_atom,/obj/distilling_tester))
			return
		// reagent_distillery (ZAS-tied) deleted; fall through to ambient
		// gas temp shift below for any distilling done in the open.
		// Change gas temps
		if(!GM)
			return
		heat_add(GM, temp_shift * 1000, HEAT_SOURCE_DEVICE)

// Subtypes //

// Biomass
/datum/decl/chemical_reaction/distilling/biomass
	name = "Distilling Biomass"
	id = "distill_biomass"
	result = REAGENT_ID_BIOMASS
	required_reagents = list(REAGENT_ID_BLOOD = 1, REAGENT_ID_SUGAR = 1, REAGENT_ID_PHORON = 0.5)
	result_amount = 6 // Buffed to 2400 units per sheet to be in line with the buffed instant reaction. Requires actually using the machine, and having blood to spare so this one should be more phoron-efficient.

	temp_shift = -2

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/biomass, distilling_temp_range, list(T20C + 80, T20C + 130))

// Medicinal
/datum/decl/chemical_reaction/distilling/inaprovalaze
	name = "Distilling Inaprovalaze"
	id = "distill_inaprovalaze"
	result = REAGENT_ID_INAPROVALAZE
	required_reagents = list(REAGENT_ID_INAPROVALINE = 2, REAGENT_ID_FOAMINGAGENT = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/inaprovalaze, distilling_temp_range, list(T0C + 100, T0C + 120))


/datum/decl/chemical_reaction/distilling/bicaridaze
	name = "Distilling Bicaridaze"
	id = "distill_bicaridaze"
	result = REAGENT_ID_BICARIDAZE
	required_reagents = list(REAGENT_ID_BICARIDINE = 2, REAGENT_ID_FOAMINGAGENT = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/bicaridaze, distilling_temp_range, list(T0C + 110, T0C + 130))


/datum/decl/chemical_reaction/distilling/dermalaze
	name = "Distilling Dermalaze"
	id = "distill_dermalaze"
	result = REAGENT_ID_DERMALAZE
	required_reagents = list(REAGENT_ID_DERMALINE = 2, REAGENT_ID_FOAMINGAGENT = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/dermalaze, distilling_temp_range, list(T0C + 115, T0C + 130))


/datum/decl/chemical_reaction/distilling/spacomycaze
	name = "Distilling Spacomycaze"
	id = "distill_spacomycaze"
	result = REAGENT_ID_SPACOMYCAZE
	required_reagents = list(REAGENT_ID_PARACETAMOL = 1, REAGENT_ID_SPACEACILLIN = 1, REAGENT_ID_FOAMINGAGENT = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/spacomycaze, distilling_temp_range, list(T0C + 100, T0C + 120))


/datum/decl/chemical_reaction/distilling/tricorlidaze
	name = "Distilling Tricorlidaze"
	id = "distill_tricorlidaze"
	result = REAGENT_ID_TRICORLIDAZE
	required_reagents = list(REAGENT_ID_TRICORDRAZINE = 1, REAGENT_ID_STERILIZINE = 1, REAGENT_ID_FOAMINGAGENT = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/tricorlidaze, distilling_temp_range, list(T0C + 100, T0C + 120))


/datum/decl/chemical_reaction/distilling/synthplas
	name = "Distilling Synthplas"
	id = "distill_synthplas"
	result = REAGENT_ID_SYNTHBLOOD_DILUTE
	required_reagents = list(REAGENT_ID_PROTEIN = 2, REAGENT_ID_ANTIBODIES = 1, REAGENT_ID_BICARIDINE = 1)
	result_amount = 3

	reaction_rate = HALF_LIFE(15)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/synthplas, distilling_temp_range, list(T0C + 110, T0C + 130))


// Alcohol
/datum/decl/chemical_reaction/distilling/beer
	name = "Distilling Beer"
	id = "distill_beer"
	result = REAGENT_ID_BEER
	required_reagents = list(REAGENT_ID_NUTRIMENT = 1, REAGENT_ID_WATER = 1, REAGENT_ID_SUGAR = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(30)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/beer, distilling_temp_range, list(T20C, T20C + 2))


/datum/decl/chemical_reaction/distilling/ale
	name = "Distilling Ale"
	id = "distill_ale"
	result = REAGENT_ID_ALE
	required_reagents = list(REAGENT_ID_NUTRIMENT = 1, REAGENT_ID_BEER = 1)
	inhibitors = list(REAGENT_ID_WATER = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(30)

	temp_shift = 0.5

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/ale, distilling_temp_range, list(T0C + 7, T0C + 13))

/datum/decl/chemical_reaction/distilling/ethanol
	name = "Distilling Ethanol"
	id = "distill_ethanol"
	result = REAGENT_ID_ETHANOL
	required_reagents = list(REAGENT_ID_NUTRIMENT = 1, REAGENT_ID_WATER = 1, REAGENT_ID_SUGAR = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(30)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/ethanol, distilling_temp_range, list(T20C+30, T20C + 40))


// Unique
/datum/decl/chemical_reaction/distilling/berserkjuice
	name = "Distilling Brute Juice"
	id = "distill_brutejuice"
	result = REAGENT_ID_BERSERKMED
	required_reagents = list(REAGENT_ID_BIOMASS = 1, REAGENT_ID_HYPERZINE = 3, REAGENT_ID_SYNAPTIZINE = 2, REAGENT_ID_PHORON = 1)
	result_amount = 3

	temp_shift = 4

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/berserkjuice, distilling_temp_range, list(T0C + 600, T0C + 700))

/datum/decl/chemical_reaction/distilling/berserkjuice/on_reaction(datum/reagents/holder, created_volume)
	..()

	if(prob(1))
		var/turf/T = get_turf(holder.my_atom)
		explosion(T, -1, rand(-1, 1), rand(1,2), rand(3,5))
	return

/datum/decl/chemical_reaction/distilling/cryogel
	name = "Distilling Cryogellatin"
	id = "distill_cryoslurry"
	result = REAGENT_ID_CRYOSLURRY
	required_reagents = list(REAGENT_ID_FROSTOIL = 7, REAGENT_ID_ENZYME = 3, REAGENT_ID_PLASTICIDE = 3, REAGENT_ID_FOAMINGAGENT = 2)
	inhibitors = list(REAGENT_ID_WATER = 5)
	result_amount = 1

	temp_shift = 20

// I know this doesn't make sense, and this is a baindaid fix but distiller code refuses to go this low, even with correct variables
TYPE_TABLE(/datum/decl/chemical_reaction/distilling/cryogel, distilling_temp_range, list(T0C + 10, T20C + 15))

/datum/decl/chemical_reaction/distilling/cryogel/on_reaction(datum/reagents/holder, created_volume)
	..()

	if(prob(1))
		var/turf/T = get_turf(holder.my_atom)
		var/datum/effect/effect/system/smoke_spread/frost/F = new (holder.my_atom)
		F.set_up(6, 0, T)
		F.start()
	return

/datum/decl/chemical_reaction/distilling/lichpowder
	name = "Distilling Lichpowder"
	id = "distill_lichpowder"
	result = REAGENT_ID_LICHPOWDER
	required_reagents = list(REAGENT_ID_ZOMBIEPOWDER = 2, REAGENT_ID_LEPORAZINE = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(8)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/lichpowder, distilling_temp_range, list(T0C + 100, T0C + 150))


/datum/decl/chemical_reaction/distilling/necroxadone
	name = "Distilling Necroxadone"
	id = "distill_necroxadone"
	result = REAGENT_ID_NECROXADONE
	required_reagents = list(REAGENT_ID_LICHPOWDER = 1, REAGENT_ID_CRYOXADONE = 1, REAGENT_ID_CARTHATOLINE = 1)
	result_amount = 2

	catalysts = list(REAGENT_ID_PHORON = 5)

	reaction_rate = HALF_LIFE(20)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/necroxadone, distilling_temp_range, list(T0C + 90, T0C + 95))


/datum/decl/chemical_reaction/distilling/hydrogen
	name = "Distilling Hydrogen"
	id = "distill_hydrogen"
	result = REAGENT_ID_HYDROGEN
	inhibitors = list(REAGENT_ID_CARBON = 1)
	required_reagents = list(REAGENT_ID_WATER = 1)
	catalysts = list(REAGENT_ID_PLATINUM = 1)
	result_amount = 2

	temp_shift = 1

	require_xgm_gas = GAS_N2
	rejects_xgm_gas = GAS_O2

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/hydrogen, distilling_temp_range, list(T20C + 110, T20C + 290))

/datum/decl/chemical_reaction/distilling/oxygen
	name = "Distilling Oxygen"
	id = "distill_oxygen"
	result = REAGENT_ID_OXYGEN
	inhibitors = list(REAGENT_ID_CARBON = 1)
	required_reagents = list(REAGENT_ID_WATER = 1)
	catalysts = list(REAGENT_ID_PLATINUM = 1)
	result_amount = 1

	temp_shift = 3 // It's burning off phoron

	require_xgm_gas = GAS_PHORON
	rejects_xgm_gas = GAS_O2

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/oxygen, distilling_temp_range, list(T20C + 150, T20C + 320))

/datum/decl/chemical_reaction/distilling/mineralized_sodium
	name = "Distilling Sodium"
	id = "distill_sodium"
	result = REAGENT_ID_SODIUM
	required_reagents = list(REAGENT_ID_MINERALIZEDFLUID = 1)
	result_amount = 1

	temp_shift = -1

	require_xgm_gas = GAS_PHORON
	rejects_xgm_gas = GAS_O2

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/mineralized_sodium, distilling_temp_range, list(T20C + 600, T20C + 800))

/datum/decl/chemical_reaction/distilling/mineralized_carbon
	name = "Distilling Carbon"
	id = "distill_carbon"
	result = REAGENT_ID_CARBON
	required_reagents = list(REAGENT_ID_MINERALIZEDFLUID = 1)
	result_amount = 1

	temp_shift = -1

	require_xgm_gas = GAS_O2
	rejects_xgm_gas = GAS_PHORON

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/mineralized_carbon, distilling_temp_range, list(T20C + 400, T20C + 800))

/datum/decl/chemical_reaction/distilling/reduce_salt
	name = "Distilling Sodium"
	id = "distill_reduce_tablesalt"
	result = REAGENT_ID_SODIUM
	required_reagents = list(REAGENT_ID_SODIUMCHLORIDE = 1)
	result_amount = 0.5

	temp_shift = -1

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/reduce_salt, distilling_temp_range, list(T20C + 800, T20C + 1000))


//Grub
//Spider
//Carp
//Meteroid
//Deathclaw

/datum/decl/chemical_reaction/distilling/energybooster
	name = "Distilling Energy Booster"
	id = "distill_energybooster"
	result = REAGENT_ID_ENERGYBOOSTER
	required_reagents = list(REAGENT_ID_HYPERZINE = 1, REAGENT_ID_STIMM = 1, REAGENT_ID_SHOCKCHEM = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/energybooster, distilling_temp_range, list(T0C + 180, T0C + 200))


/datum/decl/chemical_reaction/distilling/oceaniccure
	name = "Distilling Oceanic Cure"
	id = "distill_oceaniccure"
	result = REAGENT_ID_OCEANICCURE
	required_reagents = list(REAGENT_ID_CUREA = 1, REAGENT_ID_SOULDEW = 1, REAGENT_ID_CARPOTOXIN = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/oceaniccure, distilling_temp_range, list(T0C + 130, T0C + 150))


/datum/decl/chemical_reaction/distilling/deathclawmutagen
	name = "Distilling Deathclaw Mutagen"
	id = "distill_deathclawmutagen"
	result = REAGENT_ID_DEATHCLAWMUTAGEN
	required_reagents = list(REAGENT_ID_ARITHRAZINE = 1, REAGENT_ID_MUTAGEN = 1, REAGENT_ID_DEATHBLOOD = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/deathclawmutagen, distilling_temp_range, list(T0C + 100, T0C + 120))


/datum/decl/chemical_reaction/distilling/senseenhancer
	name = "Distilling Sense Enhancer"
	id = "distill_senseenhancer"
	result = REAGENT_ID_SENSEENHANCER
	required_reagents = list(REAGENT_ID_QUADCORD = 1, REAGENT_ID_MINDBREAKER = 1, REAGENT_ID_LIQUIDLIFE = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/senseenhancer, distilling_temp_range, list(T0C + 50, T0C + 70))


/datum/decl/chemical_reaction/distilling/heatnullifer
	name = "Distilling heatnullifer"
	id = "distill_heatnullifer"
	result = REAGENT_ID_HEATNULLIFER
	required_reagents = list(REAGENT_ID_TRAMADOL = 1, REAGENT_ID_LEPORAZINE = 1, REAGENT_ID_SPIDERTOXIN = 1)
	result_amount = 2

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/heatnullifer, distilling_temp_range, list(T0C + 230, T0C + 250))


/datum/decl/chemical_reaction/distilling/juggernog
	name = "juggernog"
	id = "distill_juggernog"
	result = REAGENT_ID_JUGGERNOG
	required_reagents = list(REAGENT_ID_CARBON = 1, REAGENT_ID_IRON = 1, REAGENT_ID_QUADCORD = 1, REAGENT_ID_NEOLIQUIDFIRE = 1, REAGENT_ID_RADIUM = 1)
	result_amount = 5

	reaction_rate = HALF_LIFE(10)

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/juggernog, distilling_temp_range, list(T0C + 180, T0C + 200))



/datum/decl/chemical_reaction/distilling/phoenixbreath
	name = REAGENT_PHOENIXBREATH
	id = REAGENT_ID_PHOENIXBREATH
	result = REAGENT_ID_PHOENIXBREATH
	required_reagents = list(REAGENT_ID_SHOCKCHEM = 1, REAGENT_ID_NEOTANE = 1, REAGENT_ID_BURNCARD = 1, REAGENT_ID_QUADCORD = 1, REAGENT_ID_MINDBREAKER = 1)
	result_amount = 6

TYPE_TABLE(/datum/decl/chemical_reaction/distilling/phoenixbreath, distilling_temp_range, list(T0C + 100, T0C + 120))

