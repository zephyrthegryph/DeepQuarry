// The processes (the machinery: code/domains/world_model/reagents/blocks/process.dm, routes.dm). Fifteen, polymerise reserved for the materials lane.
//
// Each process says which structures it acts on and what they become (chem_variants()), what it adds (an oxidiser, a nitrating acid, water), the catalyst kinds it runs
// on and the temperature it wants, and which trace-potent contaminants it leaves (fallout()): the generator writes the reactions from that. A process never names a
// chemical it makes: the product is whichever chemical has the structure the process ends in, and where none has, it is organic residue.

/// The element each ion gives up when it is electrolysed or displaced.
GLOBAL_LIST_INIT(chem_ion_elements, list(
	CHEM_ION_HYDROGEN = REAGENT_ID_HYDROGEN,
	CHEM_ION_SODIUM = REAGENT_ID_SODIUM,
	CHEM_ION_POTASSIUM = REAGENT_ID_POTASSIUM,
	CHEM_ION_CALCIUM = REAGENT_ID_CALCIUM,
	CHEM_ION_CHLORIDE = REAGENT_ID_CHLORINE,
	CHEM_ION_HYDROXIDE = REAGENT_ID_OXYGEN,
))

/// What a fermentation, a displacement and an electrolysis always leave: contaminant id => units per unit of product (shared, read-only).
GLOBAL_LIST_INIT(chem_fallout_ferment, list(REAGENT_ID_CONTAMINANT_METHANOL = 0.03))
GLOBAL_LIST_INIT(chem_fallout_displace, list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 0.05))
GLOBAL_LIST_INIT(chem_fallout_electrolyse, list(REAGENT_ID_CONTAMINANT_HEAVY_METAL = 0.02))

/// Is this id a contaminant (never an anchor of the processes that make elements and salts)?
/proc/chem_is_contaminant_id(datum/chem_gen/G, id)
	return istype(G.reagents[id], /datum/reagent/contaminant)

// ---- oxidise ----

/datum/chem_process/oxidise
	id = CHEM_PROCESS_OXIDISE
	name = "Oxidise"
	desc = "Oxygen takes a hydroxyl to a carbonyl (and a water), and a carbonyl on to a carboxyl. Uncatalysed and hot it also leaves peroxide."
	kinds = list(CHEM_CATALYST_NONE, CHEM_CATALYST_SOLID_METAL)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/oxidise/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBONYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_OXYGEN = 1), list(REAGENT_ID_WATER = 1))
	T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_CARBOXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_OXYGEN = 1))

/datum/chem_process/oxidise/fallout(kind, datum/chem_structure/S, temperature)
	if(kind == CHEM_CATALYST_NONE && temperature >= T0C + 80)
		return list(REAGENT_ID_CONTAMINANT_PEROXIDE = 0.03)
	return list()

// ---- reduce ----

/datum/chem_process/reduce
	id = CHEM_PROCESS_REDUCE
	name = "Reduce"
	desc = "Hydrogen takes a carboxyl to a carbonyl, a carbonyl to a hydroxyl and a nitro to an amine, giving up water."
	kinds = list(CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_VIOLENT

/datum/chem_process/reduce/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_CARBOXYL, CHEM_GROUP_CARBONYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDROGEN = 1), list(REAGENT_ID_WATER = 1))
	T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_HYDROXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDROGEN = 1))
	T = S.swap_group(CHEM_GROUP_NITRO, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDROGEN = 3), list(REAGENT_ID_WATER = 2))

// ---- halogenate ----

/datum/chem_process/halogenate
	id = CHEM_PROCESS_HALOGENATE
	name = "Halogenate"
	desc = "Chlorine hangs a halide on a core, freeing hydrogen chloride, or takes a hydroxyl for one. Hot, on a ring that carries a hydroxyl, it leaves dioxin."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_WARM

/datum/chem_process/halogenate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	if(length(S.groups) < CHEM_GROUPS_MAX)
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HALIDE)), list(REAGENT_ID_CHLORINE = 1), list(REAGENT_ID_CONTAMINANT_HYDROCHLORIC = 1))
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_HALIDE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_CHLORINE = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_process/halogenate/fallout(kind, datum/chem_structure/S, temperature)
	if(S && chem_has_ring(S) && S.has_group(CHEM_GROUP_HYDROXYL) && temperature >= T0C + 110)
		return list(REAGENT_ID_CONTAMINANT_DIOXIN = 0.04)
	return list()

// ---- nitrate ----

/datum/chem_process/nitrate
	id = CHEM_PROCESS_NITRATE
	name = "Nitrate"
	desc = "Polytrinic acid, with sulphuric acid dissolved in it, hangs a nitro on a core and gives up water. On a substrate that carries an amine it leaves nitrosamine."
	kinds = list(CHEM_CATALYST_ACID)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/nitrate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || length(S.groups) >= CHEM_GROUPS_MAX)
		return
	. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_NITRO)), list(REAGENT_ID_PACID = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_process/nitrate/fallout(kind, datum/chem_structure/S, temperature)
	if(S && S.has_group(CHEM_GROUP_AMINE))
		return list(REAGENT_ID_CONTAMINANT_NITROSAMINE = 0.05)
	return list()

// ---- substitute ----

/datum/chem_process/substitute
	id = CHEM_PROCESS_SUBSTITUTE
	name = "Substitute"
	desc = "Ammonia or sulfur swaps a halide for an amine or a thiol, freeing hydrogen chloride."
	kinds = list(CHEM_CATALYST_SOLID_ACID, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/substitute/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HALIDE, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_AMMONIA = 1), list(REAGENT_ID_CONTAMINANT_HYDROCHLORIC = 1))
	T = S.swap_group(CHEM_GROUP_HALIDE, CHEM_GROUP_THIOL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_SULFUR = 1), list(REAGENT_ID_CONTAMINANT_HYDROCHLORIC = 1))

// ---- phosphorylate ----

/datum/chem_process/phosphorylate
	id = CHEM_PROCESS_PHOSPHORYLATE
	name = "Phosphorylate"
	desc = "Phosphorus hangs a phosphate on a core that carries a hydroxyl, giving up water."
	kinds = list(CHEM_CATALYST_ENZYME, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/phosphorylate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || !S.has_group(CHEM_GROUP_HYDROXYL) || length(S.groups) >= CHEM_GROUPS_MAX)
		return
	. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_PHOSPHATE)), list(REAGENT_ID_PHOSPHORUS = 1), list(REAGENT_ID_WATER = 1))

// ---- decarboxylate ----

/datum/chem_process/decarboxylate
	id = CHEM_PROCESS_DECARBOXYLATE
	name = "Decarboxylate"
	desc = "Heat alone drives a carboxyl off (the carbon dioxide is lost). Uncatalysed it leaves tar."
	kinds = list(CHEM_CATALYST_NONE, CHEM_CATALYST_SOLID_ACID)
	band_class = REACTION_TEMP_VIOLENT

/datum/chem_process/decarboxylate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_CARBOXYL, null)
	if(T)
		. += chem_variant(list(substrate_id), list(T))

/datum/chem_process/decarboxylate/fallout(kind, datum/chem_structure/S, temperature)
	if(kind == CHEM_CATALYST_NONE)
		return list(REAGENT_ID_CONTAMINANT_TAR = 0.05)
	return list()

// ---- condense ----

/datum/chem_process/condense
	id = CHEM_PROCESS_CONDENSE
	name = "Condense"
	desc = "A carboxyl and a hydroxyl join as an ester, a carboxyl and an amine as an amide, giving up water. Water in the mixture stops it (and undoes what it made: hydrolysis). Hot, on a ring, it leaves plasticiser."
	kinds = list(CHEM_CATALYST_ACID, CHEM_CATALYST_SOLID_ACID)
	fixed_band = TRUE
	blocked_by_water = TRUE

/datum/chem_process/condense/declare()
	band = list(T0C + 70, T0C + 90, T0C + 130, T0C + 200)

/datum/chem_process/condense/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || !S.has_group(CHEM_GROUP_CARBOXYL))
		return
	for(var/partner_id in G.ids)
		if(partner_id == substrate_id || chem_is_contaminant_id(G, partner_id))
			continue
		var/datum/chem_structure/P = G.structures[partner_id]
		if(!P.is_organic())
			continue
		for(var/link in list(CHEM_LINK_ESTER, CHEM_LINK_AMIDE))
			var/consumed = link == CHEM_LINK_ESTER ? CHEM_GROUP_HYDROXYL : CHEM_GROUP_AMINE
			if(!P.has_group(consumed))
				continue
			var/list/cores = S.cores + P.cores
			var/list/groups = S.groups.Copy()
			groups -= CHEM_GROUP_CARBOXYL
			var/list/partner_groups = P.groups.Copy()
			partner_groups -= consumed
			groups += partner_groups
			var/list/joined_links = S.links + P.links
			joined_links += link
			. += chem_variant(list(substrate_id, partner_id), list(chem_structure_make(cores, groups, joined_links)), null, list(REAGENT_ID_WATER = 1))

/datum/chem_process/condense/fallout(kind, datum/chem_structure/S, temperature)
	if(S && chem_has_ring(S) && temperature >= T0C + 95)
		return list(REAGENT_ID_CONTAMINANT_PLASTICISER = 0.04)
	return list()

// ---- hydrolyse ----

/datum/chem_process/hydrolyse
	id = CHEM_PROCESS_HYDROLYSE
	name = "Hydrolyse"
	desc = "Water splits an ester or an amide into the acid and the alcohol or amine it was condensed from. It wants a base or an enzyme, and a cool mixture."
	kinds = list(CHEM_CATALYST_BASE, CHEM_CATALYST_ENZYME)
	fixed_band = TRUE

/datum/chem_process/hydrolyse/declare()
	band = list(T0C + 5, T0C + 20, T0C + 45, T0C + 60)

/datum/chem_process/hydrolyse/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!(CHEM_LINK_ESTER in S.links) && !(CHEM_LINK_AMIDE in S.links))
		return
	var/list/pairs = G.condensed[S.key]
	if(!length(pairs))
		. += chem_variant(list(substrate_id), list(chem_nothing()), list(REAGENT_ID_WATER = 1))
		return
	for(var/list/pair as anything in pairs)
		. += chem_variant(list(substrate_id), list(pair[1], pair[2]), list(REAGENT_ID_WATER = 1))

// ---- ferment ----

/datum/chem_process/ferment
	id = CHEM_PROCESS_FERMENT
	name = "Ferment"
	desc = "An enzyme turns a sugar ring into a short chain (the carbon dioxide is lost). It leaves a trace of methanol."
	kinds = list(CHEM_CATALYST_ENZYME)

/datum/chem_process/ferment/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	var/datum/chem_structure/T = S.swap_core(CHEM_CORE_SUGAR_RING, CHEM_CORE_SHORT_CHAIN)
	if(T)
		. += chem_variant(list(substrate_id), list(T))

/datum/chem_process/ferment/fallout(kind, datum/chem_structure/S, temperature)
	return GLOB.chem_fallout_ferment

// ---- crack ----

/datum/chem_process/crack
	id = CHEM_PROCESS_CRACK
	name = "Crack"
	desc = "Heat breaks a long chain into a short one. It leaves tar, more of it without a solid acid."
	kinds = list(CHEM_CATALYST_NONE, CHEM_CATALYST_SOLID_ACID)
	band_class = REACTION_TEMP_VIOLENT

/datum/chem_process/crack/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	var/datum/chem_structure/T = S.swap_core(CHEM_CORE_LONG_CHAIN, CHEM_CORE_SHORT_CHAIN)
	if(T)
		. += chem_variant(list(substrate_id), list(T))

/datum/chem_process/crack/fallout(kind, datum/chem_structure/S, temperature)
	return list(REAGENT_ID_CONTAMINANT_TAR = (kind == CHEM_CATALYST_NONE ? 0.1 : 0.03))

// ---- neutralise ----

/datum/chem_process/neutralise
	id = CHEM_PROCESS_NEUTRALISE
	name = "Neutralise"
	desc = "An acid and a base make a salt (and water, from a hydroxide). Where no chemical is that salt it is salts, a mild contaminant. This is how acid and base residue are spent. An acid on a silicate sets silanol free."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_AMBIENT
	clean = TRUE
	fixed_band = TRUE
	residue_id = REAGENT_ID_CONTAMINANT_SALTS

/datum/chem_process/neutralise/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_acid())
		return
	for(var/base_id in G.ids)
		var/datum/chem_structure/B = G.structures[base_id]
		if(!B.is_base() || (chem_is_contaminant_id(G, base_id) && !B.is_ionic()))
			continue // an organic contaminant (nitrosamine) is no base a chemist can quench it with
		var/list/byproducts = B.anion == CHEM_ION_HYDROXIDE ? list(REAGENT_ID_WATER = 1) : null
		var/datum/chem_structure/salt = B.is_ionic() ? chem_structure_make(null, null, null, B.cation, S.anion) : chem_nothing()
		. += chem_variant(list(substrate_id, base_id), list(salt), null, byproducts)
	// An acid on a silicate sets the silanol free (a siloxane with a hydroxyl) and leaves the acid's salt.
	for(var/silicate_id in G.ids)
		if(chem_is_contaminant_id(G, substrate_id) || G.structures[silicate_id].anion != CHEM_ION_SILICATE)
			continue
		. += chem_variant(list(substrate_id, silicate_id), list(chem_structure_make(list(CHEM_CORE_SILOXANE), list(CHEM_GROUP_HYDROXYL)), REAGENT_ID_CONTAMINANT_SALTS))

// ---- displace ----

/datum/chem_process/displace
	id = CHEM_PROCESS_DISPLACE
	name = "Displace"
	desc = "A metal takes the place of another in a salt and sets it free, or a salt's metal binds to a carboxyl or phosphate group. Only where the result is a chemical that exists."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_GENTLE
	clean = TRUE
	fixed_band = TRUE
	residue_routes = FALSE

/datum/chem_process/displace/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = binds(substrate_id, S, G)
	if(!S.is_ionic() || S.is_acid() || S.is_base() || S.cation == CHEM_ION_HYDROGEN || chem_is_contaminant_id(G, substrate_id))
		return
	var/freed = GLOB.chem_ion_elements[S.cation]
	if(!freed)
		return
	for(var/metal_id in G.ids)
		var/datum/chem_structure/M = G.structures[metal_id]
		if(M.is_ionic() || M.is_organic() || !M.cation || M.cation == S.cation || chem_is_contaminant_id(G, metal_id))
			continue
		var/datum/chem_structure/salt = chem_structure_make(null, null, null, M.cation, S.anion)
		if(!chem_structure_match(salt))
			continue
		. += chem_variant(list(substrate_id, metal_id), list(salt, freed))

/datum/chem_process/displace/proc/binds(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || chem_is_contaminant_id(G, substrate_id) || S.has_group(CHEM_GROUP_METAL_CENTRE) || !(S.has_group(CHEM_GROUP_CARBOXYL) || S.has_group(CHEM_GROUP_PHOSPHATE)))
		return
	var/datum/chem_structure/bound = S.with_group(CHEM_GROUP_METAL_CENTRE)
	if(!chem_structure_match(bound))
		return
	for(var/salt_id in G.ids)
		var/datum/chem_structure/M = G.structures[salt_id]
		if(!M.is_ionic() || M.is_acid() || M.is_base() || M.cation == CHEM_ION_HYDROGEN || chem_is_contaminant_id(G, salt_id))
			continue
		. += chem_variant(list(substrate_id, salt_id), list(bound), null, list(REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 1))

/datum/chem_process/displace/fallout(kind, datum/chem_structure/S, temperature)
	return GLOB.chem_fallout_displace

// ---- electrolyse ----

/datum/chem_process/electrolyse
	id = CHEM_PROCESS_ELECTROLYSE
	name = "Electrolyse"
	desc = "A current splits an ionic compound into its elements. The container stands on a hot plate that is on, with a sheet of conductive metal in it for the electrodes."
	kinds = list(CHEM_CATALYST_SOLID_METAL)
	band_class = REACTION_TEMP_AMBIENT
	clean = TRUE
	fixed_band = TRUE
	needs_current = TRUE
	residue_routes = FALSE

/datum/chem_process/electrolyse/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_ionic() || S.is_acid() || chem_is_contaminant_id(G, substrate_id))
		return
	var/from_cation = GLOB.chem_ion_elements[S.cation]
	var/from_anion = GLOB.chem_ion_elements[S.anion]
	if(!from_cation || !from_anion)
		return
	. += chem_variant(list(substrate_id), list(from_cation, from_anion))

/datum/chem_process/electrolyse/fallout(kind, datum/chem_structure/S, temperature)
	return GLOB.chem_fallout_electrolyse

// ---- polymerise ----

/datum/chem_process/polymerise
	id = CHEM_PROCESS_POLYMERISE
	name = "Polymerise"
	desc = "Units join into a chain: chemistry makes the units, material science makes the chain (the materials lane)."
	reserved = TRUE
	kinds = list(CHEM_CATALYST_NONE)
