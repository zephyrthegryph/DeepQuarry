// The process chemicals (the machinery: code/domains/world_model/reagents/blocks/agents.dm).
//
// Pour one in and it performs its process on whatever it can act on, without the setup of the proper method, and is consumed. Each is less selective than the
// proper method and leaves its own residue and poisons; they are what the dirty shortcuts of the staples are made of. Eleven agents here (bleach performs two
// processes); the twelfth process chemicals of the design are not generated routes: the dry agent and the scavenger resin act on contact (clashes.dm), the
// enzyme is the catalyst of the proper methods, and the catalytic phoron belongs to the exotic blends.

/// A band for a process chemical poured in: a hot plate, never past the range of its own.
/proc/chem_agent_band(low, ideal_low, ideal_high, high)
	return list(T0C + low, T0C + ideal_low, T0C + ideal_high, T0C + high)

// ---- hydride: reduce, with no hydrogen and no metal catalyst; reduces every reducible group it meets ----

/datum/chem_agent/hydride_reduce
	reagent_id = REAGENT_ID_HYDRIDE
	process_id = CHEM_PROCESS_REDUCE
	selectivity = 0.55
	leaves = list(REAGENT_ID_CONTAMINANT_BASE_RESIDUE = 0.12, REAGENT_ID_CONTAMINANT_SALTS = 0.08)
	desc = "A strong reducer: the reduction needs no hydrogen and no metal sheet. It reduces every reducible group it meets and leaves base residue and boron salts."

/datum/chem_agent/hydride_reduce/New()
	..()
	band = chem_agent_band(15, 30, 80, 120)

/datum/chem_agent/hydride_reduce/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_CARBOXYL, CHEM_GROUP_CARBONYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDRIDE = 1), list(REAGENT_ID_WATER = 1))
	T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_HYDROXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDRIDE = 1))
	T = S.swap_group(CHEM_GROUP_NITRO, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDRIDE = 1), list(REAGENT_ID_WATER = 2))

/// The same hydride, doing the amination of an aldehyde in one pot (ammonia and hydride in place of ammonia, hydrogen and a metal sheet).
/datum/chem_agent/hydride_substitute
	reagent_id = REAGENT_ID_HYDRIDE
	process_id = CHEM_PROCESS_SUBSTITUTE
	selectivity = 0.55
	leaves = list(REAGENT_ID_CONTAMINANT_BASE_RESIDUE = 0.12, REAGENT_ID_CONTAMINANT_SALTS = 0.08)
	desc = "Ammonia and the hydride turn a carbonyl into an amine in one pot."

/datum/chem_agent/hydride_substitute/New()
	..()
	band = chem_agent_band(15, 30, 80, 120)

/datum/chem_agent/hydride_substitute/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_AMMONIA = 1, REAGENT_ID_HYDRIDE = 1), list(REAGENT_ID_WATER = 1))

// ---- strong oxidiser: oxidise all the way to a carboxyl ----

/datum/chem_agent/strong_oxidiser
	reagent_id = REAGENT_ID_STRONGOXIDISER
	process_id = CHEM_PROCESS_OXIDISE
	selectivity = 0.6
	leaves = list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 0.08)
	desc = "A permanganate-type oxidiser: it takes a hydroxyl or a carbonyl all the way to a carboxyl, burning what else it can. It leaves heavy metals."

/datum/chem_agent/strong_oxidiser/New()
	..()
	band = chem_agent_band(15, 30, 80, 120)

/datum/chem_agent/strong_oxidiser/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBOXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_STRONGOXIDISER = 1), list(REAGENT_ID_WATER = 1))
	T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_CARBOXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_STRONGOXIDISER = 1))
	if(length(S.cores) == 1 && S.has_core(CHEM_CORE_NITROGEN_RING) && !length(S.groups) && !length(S.links))
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_CARBOXYL)), list(REAGENT_ID_STRONGOXIDISER = 1))

// ---- bleach: oxidise one step, or halogenate a ring ----

/datum/chem_agent/bleach_oxidise
	reagent_id = REAGENT_ID_BLEACH
	process_id = CHEM_PROCESS_OXIDISE
	selectivity = 0.65
	leaves = list(REAGENT_ID_CONTAMINANT_SALTS = 0.1)
	desc = "Hypochlorite oxidises a bare phoron lattice to a hydroxyl and a hydroxyl to a carbonyl, in one step. It leaves a halide, and a reactive impurity on the lattice."

/datum/chem_agent/bleach_oxidise/New()
	..()
	band = chem_agent_band(0, 15, 45, 80)

/datum/chem_agent/bleach_oxidise/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	if(length(S.groups) < CHEM_GROUPS_MAX && length(S.cores) == 1 && S.has_core(CHEM_CORE_PHORON_LATTICE) && !length(S.groups))
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HYDROXYL)), list(REAGENT_ID_BLEACH = 1))
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBONYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_BLEACH = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_agent/bleach_oxidise/trace(datum/chem_structure/S, temperature)
	if(S && S.has_core(CHEM_CORE_PHORON_LATTICE))
		return list(REAGENT_ID_CONTAMINANT_REACTIVE = 0.05)
	return list()

/datum/chem_agent/bleach_halogenate
	reagent_id = REAGENT_ID_BLEACH
	process_id = CHEM_PROCESS_HALOGENATE
	selectivity = 0.65
	leaves = list(REAGENT_ID_CONTAMINANT_SALTS = 0.1)
	desc = "Hypochlorite hangs a halide on a ring, one pot, cold. Warm, on a ring with a hydroxyl, it leaves dioxin."

/datum/chem_agent/bleach_halogenate/New()
	..()
	band = chem_agent_band(0, 15, 45, 80)

/datum/chem_agent/bleach_halogenate/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || !chem_has_ring(S) || length(S.groups) >= CHEM_GROUPS_MAX)
		return
	. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HALIDE)), list(REAGENT_ID_BLEACH = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_agent/bleach_halogenate/trace(datum/chem_structure/S, temperature)
	if(S && S.has_group(CHEM_GROUP_HYDROXYL) && temperature >= T0C + 30)
		return list(REAGENT_ID_CONTAMINANT_DIOXIN = 0.05)
	return list()

// ---- nitrating mix: nitrate, with no separate nitric acid and no acid catalyst ----

/datum/chem_agent/nitrating_mix
	reagent_id = REAGENT_ID_NITRATINGMIX
	process_id = CHEM_PROCESS_NITRATE
	selectivity = 0.7
	leaves = list(REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 0.1)
	desc = "Nitric and sulphuric acid already mixed: the nitration needs nothing else. It leaves acid residue, and nitrosamine on an amine."

/datum/chem_agent/nitrating_mix/New()
	..()
	band = chem_agent_band(15, 30, 70, 110)

/datum/chem_agent/nitrating_mix/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || length(S.groups) >= CHEM_GROUPS_MAX || S.has_group(CHEM_GROUP_NITRO))
		return
	. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_NITRO)), list(REAGENT_ID_NITRATINGMIX = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_agent/nitrating_mix/trace(datum/chem_structure/S, temperature)
	if(S && S.has_group(CHEM_GROUP_AMINE))
		return list(REAGENT_ID_CONTAMINANT_NITROSAMINE = 0.06)
	return list()

// ---- chlorinating agent: take a hydroxyl for a halide cleanly ----

/datum/chem_agent/chlorinating_agent
	reagent_id = REAGENT_ID_CHLORINATINGAGENT
	process_id = CHEM_PROCESS_HALOGENATE
	selectivity = 0.85
	leaves = list(REAGENT_ID_HYDROCHLORIC = 0.1, REAGENT_ID_CONTAMINANT_SULFUR = 0.06)
	desc = "Takes a hydroxyl for a halide without chlorine gas. It leaves hydrochloric acid and sulfur."

/datum/chem_agent/chlorinating_agent/New()
	..()
	band = chem_agent_band(0, 15, 45, 80)

/datum/chem_agent/chlorinating_agent/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_HALIDE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_CHLORINATINGAGENT = 1), list(REAGENT_ID_WATER = 1))

// ---- coupling agent: condense without removing the water ----

/datum/chem_agent/coupling_agent
	reagent_id = REAGENT_ID_COUPLINGAGENT
	process_id = CHEM_PROCESS_CONDENSE
	selectivity = 0.75
	ignores_water = TRUE
	leaves = list(REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE = 0.1)
	desc = "Joins a carboxyl to a hydroxyl or an amine at a warm bath with no drying and no acid. It leaves organic residue."

/datum/chem_agent/coupling_agent/New()
	..()
	band = chem_agent_band(10, 25, 60, 90)

/datum/chem_agent/coupling_agent/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	var/datum/chem_process/condense = chem_process_of(CHEM_PROCESS_CONDENSE)
	for(var/variant in condense.chem_variants(substrate_id, S, G))
		var/datum/chem_variant/V = variant
		V.agents = list(REAGENT_ID_COUPLINGAGENT = 1)
		V.kinds = null
		V.blocked = null
		V.band = null
		. += V

// ---- caustic digest: hydrolyse anything ----

/datum/chem_agent/caustic_digest
	reagent_id = REAGENT_ID_CAUSTICDIGEST
	process_id = CHEM_PROCESS_HYDROLYSE
	selectivity = 0.65
	leaves = list(REAGENT_ID_CONTAMINANT_BASE_RESIDUE = 0.1, REAGENT_ID_CONTAMINANT_TAR = 0.04)
	desc = "Hot lye hydrolyses any ester or amide, polymers included. It leaves base residue and tar."

/datum/chem_agent/caustic_digest/New()
	..()
	band = chem_agent_band(55, 85, 110, 150)

/datum/chem_agent/caustic_digest/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	var/datum/chem_process/hydrolyse = chem_process_of(CHEM_PROCESS_HYDROLYSE)
	for(var/variant in hydrolyse.chem_variants(substrate_id, S, G))
		var/datum/chem_variant/V = variant
		V.agents = list(REAGENT_ID_CAUSTICDIGEST = 1, REAGENT_ID_WATER = 1)
		. += V

// ---- yeast: ferment ----

/datum/chem_agent/yeast_ferment
	reagent_id = REAGENT_ID_YEAST
	process_id = CHEM_PROCESS_FERMENT
	selectivity = 0.8
	leaves = list(REAGENT_ID_CONTAMINANT_BIOLOGICAL = 0.1, REAGENT_ID_CONTAMINANT_METHANOL = 0.03)
	desc = "Yeast ferments a sugar to a short chain. It leaves endotoxin, and methanol when the bath is warm."

/datum/chem_agent/yeast_ferment/New()
	..()
	band = chem_agent_band(10, 22, 40, 55)

/datum/chem_agent/yeast_ferment/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	var/datum/chem_structure/T = S.swap_core(CHEM_CORE_SUGAR_RING, CHEM_CORE_SHORT_CHAIN)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_YEAST = 1))

/datum/chem_agent/yeast_ferment/trace(datum/chem_structure/S, temperature)
	if(temperature >= T0C + 32)
		return list(REAGENT_ID_CONTAMINANT_METHANOL = 0.1)
	return list()
