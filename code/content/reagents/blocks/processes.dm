// The processes (the machinery: code/domains/world_model/reagents/blocks/process.dm, routes.dm). Fifteen; polymerise makes the chemistry-side products only (a
// silicone chain), the materials lane's polymers come with the workshop.
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
	CHEM_ION_LITHIUM = REAGENT_ID_LITHIUM,
	CHEM_ION_IRON = REAGENT_ID_IRON,
	CHEM_ION_COPPER = REAGENT_ID_COPPER,
))

/// How reactive a metal is (a more reactive metal takes the place of a less reactive one in a salt, never the other way: no displacement is its own reverse).
GLOBAL_LIST_INIT(chem_metal_reactivity, list(
	CHEM_ION_POTASSIUM = 6,
	CHEM_ION_SODIUM = 5,
	CHEM_ION_LITHIUM = 4,
	CHEM_ION_CALCIUM = 3,
	CHEM_ION_IRON = 2,
	CHEM_ION_COPPER = 1,
))

/// A band by class (the class table of code/content/reagents/reactions/reaction_temperatures.dm), for a variant that runs in another class than its process.
/proc/chem_band_of(class)
	return GLOB.reaction_temperature_classes[class]

/// How many of this group the structure has.
/proc/chem_group_count(datum/chem_structure/S, group)
	return S.count_of(S.groups, group)

/// The kinds a clean no-solid-catalyst variant runs on.
GLOBAL_LIST_INIT(chem_kinds_uncatalysed, list(CHEM_CATALYST_NONE, CHEM_CATALYST_SOLID_METAL))

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
	desc = "Oxygen takes a hydroxyl to a carbonyl (and a water), and a carbonyl on to a carboxyl; it hangs a hydroxyl on a bare phoron lattice at gentle heat. An enzyme hangs one on a ring or a steroid, and a metal sheet on a double ring. Uncatalysed and hot it also leaves peroxide."
	kinds = list(CHEM_CATALYST_NONE, CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_ENZYME)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/oxidise/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	var/hydroxyls = chem_group_count(S, CHEM_GROUP_HYDROXYL)
	var/room = length(S.groups) < CHEM_GROUPS_MAX
	// A bare phoron lattice takes a hydroxyl, and a lattice with one a second: gently, or it burns.
	if(room && length(S.cores) == 1 && S.has_core(CHEM_CORE_PHORON_LATTICE) && hydroxyls < 2 && !S.has_group(CHEM_GROUP_METAL_CENTRE))
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HYDROXYL)), list(REAGENT_ID_OXYGEN = 1), null, null, GLOB.chem_kinds_uncatalysed, null, chem_band_of(REACTION_TEMP_GENTLE))
	// An enzyme hangs a hydroxyl on a ring or a steroid that has one; a double ring that has none takes it from an enzyme or a catalytic metal sheet.
	if(room && !S.has_group(CHEM_GROUP_METAL_CENTRE))
		if(S.has_core(CHEM_CORE_DOUBLE_RING) && hydroxyls < 1)
			. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HYDROXYL)), list(REAGENT_ID_OXYGEN = 1), null, null, list(CHEM_CATALYST_ENZYME, CHEM_CATALYST_SOLID_METAL))
		else if((S.has_core(CHEM_CORE_STEROID) || S.has_core(CHEM_CORE_RING)) && hydroxyls < 2 && hydroxyls >= 1)
			. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HYDROXYL)), list(REAGENT_ID_OXYGEN = 1), null, null, list(CHEM_CATALYST_ENZYME))
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_CARBONYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_OXYGEN = 1), list(REAGENT_ID_WATER = 1), null, GLOB.chem_kinds_uncatalysed)
	T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_CARBOXYL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_OXYGEN = 1), null, null, GLOB.chem_kinds_uncatalysed)
	// An enzyme takes ethanol all the way to the acid, gently and clean (vinegar); an oxidiser does it fast and dirty.
	if(length(S.cores) == 1 && S.has_core(CHEM_CORE_SHORT_CHAIN) && length(S.groups) == 1 && S.has_group(CHEM_GROUP_HYDROXYL) && !length(S.links))
		. += chem_variant(list(substrate_id), list(chem_structure_make(S.cores, list(CHEM_GROUP_CARBOXYL))), list(REAGENT_ID_OXYGEN = 1), list(REAGENT_ID_WATER = 1), null, list(CHEM_CATALYST_ENZYME))
	// A bare pyridine takes an acid on its side chain (hot), or a hydroxyl under an enzyme (gentle).
	if(room && length(S.cores) == 1 && S.has_core(CHEM_CORE_NITROGEN_RING) && !length(S.groups) && !length(S.links))
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_CARBOXYL)), list(REAGENT_ID_OXYGEN = 1), null, null, GLOB.chem_kinds_uncatalysed)
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HYDROXYL)), list(REAGENT_ID_OXYGEN = 1), null, null, list(CHEM_CATALYST_ENZYME))

/datum/chem_process/oxidise/fallout(kind, datum/chem_structure/S, temperature)
	if(kind == CHEM_CATALYST_NONE && temperature >= T0C + 80)
		return list(REAGENT_ID_CONTAMINANT_PEROXIDE = 0.03)
	return list()

// ---- reduce ----

/datum/chem_process/reduce
	id = CHEM_PROCESS_REDUCE
	name = "Reduce"
	desc = "Hydrogen takes a carboxyl to a carbonyl, a carbonyl to a hydroxyl, a nitro to an amine and a hydroxyl off altogether, giving up water."
	kinds = list(CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_HOT

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
	T = S.swap_group(CHEM_GROUP_HYDROXYL, null)
	if(T && !S.has_core(CHEM_CORE_PHORON_LATTICE)) // phoron is mined, not reduced out of a medicine
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_HYDROGEN = 1), list(REAGENT_ID_WATER = 1))

// ---- halogenate ----

/datum/chem_process/halogenate
	id = CHEM_PROCESS_HALOGENATE
	name = "Halogenate"
	desc = "Chlorine or fluorine hangs a halide on a core, freeing hydrogen chloride (or an acid residue); on a polyol it takes a hydroxyl for one instead. Hot, on a ring that carries a hydroxyl, it leaves dioxin."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_WARM

/datum/chem_process/halogenate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	// A polyol (two hydroxyls or more) gives one up for a halide; anything else has a halide hung on it.
	if(chem_group_count(S, CHEM_GROUP_HYDROXYL) >= 2)
		var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_HYDROXYL, CHEM_GROUP_HALIDE)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_CHLORINE = 1), list(REAGENT_ID_WATER = 1))
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_FLUORINE = 1), list(REAGENT_ID_WATER = 1, REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 1))
		return
	if(length(S.groups) < CHEM_GROUPS_MAX)
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HALIDE)), list(REAGENT_ID_CHLORINE = 1), list(REAGENT_ID_HYDROCHLORIC = 1))
		. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_HALIDE)), list(REAGENT_ID_FLUORINE = 1), list(REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 1))

/datum/chem_process/halogenate/fallout(kind, datum/chem_structure/S, temperature)
	if(S && chem_has_ring(S) && S.has_group(CHEM_GROUP_HYDROXYL) && temperature >= T0C + 110)
		return list(REAGENT_ID_CONTAMINANT_DIOXIN = 0.04)
	return list()

// ---- nitrate ----

/datum/chem_process/nitrate
	id = CHEM_PROCESS_NITRATE
	name = "Nitrate"
	desc = "Nitric acid, with sulphuric acid dissolved in it, hangs a nitro on a core and gives up water. On a substrate that carries an amine it leaves nitrosamine."
	kinds = list(CHEM_CATALYST_ACID)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/nitrate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || length(S.groups) >= CHEM_GROUPS_MAX || S.has_group(CHEM_GROUP_NITRO))
		return
	. += chem_variant(list(substrate_id), list(S.with_group(CHEM_GROUP_NITRO)), list(REAGENT_ID_NITRICACID = 1), list(REAGENT_ID_WATER = 1))

/datum/chem_process/nitrate/fallout(kind, datum/chem_structure/S, temperature)
	if(S && S.has_group(CHEM_GROUP_AMINE))
		return list(REAGENT_ID_CONTAMINANT_NITROSAMINE = 0.05)
	return list()

// ---- substitute ----

/datum/chem_process/substitute
	id = CHEM_PROCESS_SUBSTITUTE
	name = "Substitute"
	desc = "Ammonia, sulfur or cyanide swaps a halide for an amine, a thiol or a nitrile, freeing hydrogen chloride (or a salt); ammonia and hydrogen turn a carbonyl into an amine. The cyanide arm leaves cyanide."
	kinds = list(CHEM_CATALYST_SOLID_ACID, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_WARM
	rank = 10

/datum/chem_process/substitute/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic())
		return
	// A carbonyl and ammonia and hydrogen make an amine (the amination of an aldehyde): ranked before the plain reduction that would take the carbonyl to a hydroxyl.
	var/datum/chem_structure/T = S.swap_group(CHEM_GROUP_CARBONYL, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_AMMONIA = 1, REAGENT_ID_HYDROGEN = 1), list(REAGENT_ID_WATER = 1), null, list(CHEM_CATALYST_SOLID_METAL, CHEM_CATALYST_NONE))
	T = S.swap_group(CHEM_GROUP_HALIDE, CHEM_GROUP_AMINE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_AMMONIA = 1), list(REAGENT_ID_HYDROCHLORIC = 1))
	T = S.swap_group(CHEM_GROUP_HALIDE, CHEM_GROUP_THIOL)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_SULFUR = 1), list(REAGENT_ID_HYDROCHLORIC = 1))
	T = S.swap_group(CHEM_GROUP_HALIDE, CHEM_GROUP_CYANIDE)
	if(T)
		. += chem_variant(list(substrate_id), list(T), list(REAGENT_ID_CYANIDE = 1), list(REAGENT_ID_POTASSIUMCHLORIDE = 1), null, null, null, null, list(REAGENT_ID_CYANIDE = 0.05))

// ---- phosphorylate ----

/datum/chem_process/phosphorylate
	id = CHEM_PROCESS_PHOSPHORYLATE
	name = "Phosphorylate"
	desc = "Phosphorus hangs a phosphate on a core that carries a hydroxyl, giving up water."
	kinds = list(CHEM_CATALYST_ENZYME, CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_HOT

/datum/chem_process/phosphorylate/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || !S.has_group(CHEM_GROUP_HYDROXYL) || length(S.groups) >= CHEM_GROUPS_MAX || S.has_group(CHEM_GROUP_PHOSPHATE))
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
	desc = "A carboxyl and a hydroxyl join as an ester (a dissolved or solid acid helps), a carboxyl and an amine as an amide (warm, with no acid in the mixture: an acid ties the amine up), giving up water. Water in the mixture stops it (and undoes what it made: hydrolysis). Hot, on a ring, it leaves plasticiser."
	kinds = list(CHEM_CATALYST_ACID, CHEM_CATALYST_SOLID_ACID)
	fixed_band = TRUE
	blocked_by_water = TRUE
	residue_routes = FALSE // every acid and every alcohol or amine would be a route to residue (thousands of them): only the joins that make a chemical are written

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
		for(var/link in list(CHEM_LINK_AMIDE, CHEM_LINK_ESTER))
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
			var/datum/chem_structure/joined = chem_structure_make(cores, groups, joined_links, P.cation, null)
			if(link == CHEM_LINK_AMIDE)
				// No acid in the mixture: an acid protonates the amine, and the same two make an ester of the hydroxyl instead.
				. += chem_variant(list(substrate_id, partner_id), list(joined), null, list(REAGENT_ID_WATER = 1), null, list(CHEM_CATALYST_NONE), list(REAGENT_ID_SACID), list(T0C + 40, T0C + 60, T0C + 100, T0C + 150))
			else
				. += chem_variant(list(substrate_id, partner_id), list(joined), null, list(REAGENT_ID_WATER = 1))

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
	desc = "An acid and a base (a hydroxide, a carbonate or an amine) make a salt (and water, from a hydroxide or a carbonate). Where no chemical is that salt it is salts, a mild contaminant. This is how acid and base residue are spent. An acid on a silicate sets silanol free; sand in hot lye is silicate."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_AMBIENT
	clean = TRUE
	fixed_band = TRUE
	residue_id = REAGENT_ID_CONTAMINANT_SALTS

/datum/chem_process/neutralise/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_acid())
		return
	// Silica is the acid that is hardest to move: it wants the base hot.
	var/list/silica_band = S.anion == CHEM_ION_SILICATE ? chem_band_of(REACTION_TEMP_HOT) : null
	for(var/base_id in G.ids)
		var/datum/chem_structure/B = G.structures[base_id]
		if(!B.is_base() || (chem_is_contaminant_id(G, base_id) && !B.is_ionic()))
			continue // an organic contaminant (nitrosamine) is no base a chemist can quench it with
		if(!B.is_ionic() && !(base_id in GLOB.chem_building_blocks))
			continue // a finished amine is not spent by the acid its own making frees: the group clashes deal with an acid group and an amine
		var/list/byproducts = (B.anion == CHEM_ION_HYDROXIDE || B.anion == CHEM_ION_CARBONATE) ? list(REAGENT_ID_WATER = 1) : null
		var/datum/chem_structure/salt = B.is_ionic() ? chem_structure_make(null, null, null, B.cation, S.anion) : chem_nothing()
		. += chem_variant(list(substrate_id, base_id), list(salt), null, byproducts, null, null, null, silica_band)
	// An acid on a silicate sets the silanol free (a siloxane with a hydroxyl) and leaves the acid's salt.
	for(var/silicate_id in G.ids)
		var/datum/chem_structure/Si = G.structures[silicate_id]
		if(chem_is_contaminant_id(G, substrate_id) || Si.anion != CHEM_ION_SILICATE || Si.cation == CHEM_ION_HYDROGEN || S.anion == CHEM_ION_SILICATE)
			continue
		. += chem_variant(list(substrate_id, silicate_id), list(chem_structure_make(list(CHEM_CORE_SILOXANE), list(CHEM_GROUP_HYDROXYL)), REAGENT_ID_CONTAMINANT_SALTS))

// ---- displace ----

/datum/chem_process/displace
	id = CHEM_PROCESS_DISPLACE
	name = "Displace"
	desc = "A metal takes the place of another in a salt and sets it free, an acid dissolves a metal into its salt, two salts swap their ions, or a metal binds to an organic's groups out of a salt or a base. Only where the result is a chemical that exists."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_GENTLE
	clean = TRUE
	fixed_band = TRUE
	residue_routes = FALSE

/datum/chem_process/displace/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = binds(substrate_id, S, G)
	if(chem_is_contaminant_id(G, substrate_id))
		return
	. += dissolves(substrate_id, S, G)
	. += swaps(substrate_id, S, G)
	if(!S.is_ionic() || S.is_acid() || S.is_base() || S.cation == CHEM_ION_HYDROGEN)
		return
	var/freed = GLOB.chem_ion_elements[S.cation]
	if(!freed)
		return
	for(var/metal_id in G.ids)
		var/datum/chem_structure/M = G.structures[metal_id]
		if(M.is_ionic() || M.is_organic() || !M.cation || M.cation == S.cation || chem_is_contaminant_id(G, metal_id))
			continue
		if((GLOB.chem_metal_reactivity[M.cation] || 0) <= (GLOB.chem_metal_reactivity[S.cation] || 0))
			continue // a metal only takes the place of a less reactive one
		var/datum/chem_structure/salt = chem_structure_make(null, null, null, M.cation, S.anion)
		if(!chem_structure_match(salt))
			continue
		. += chem_variant(list(substrate_id, metal_id), list(salt, freed))

/// A metal binds to an organic out of a salt (an acid residue is left) or a base (water): where the organometallic is a chemical that exists.
/datum/chem_process/displace/proc/binds(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_organic() || chem_is_contaminant_id(G, substrate_id) || S.has_group(CHEM_GROUP_METAL_CENTRE) || !length(S.groups) || length(S.groups) >= CHEM_GROUPS_MAX)
		return
	for(var/salt_id in G.ids)
		var/datum/chem_structure/M = G.structures[salt_id]
		if(!M.is_ionic() || M.is_acid() || M.cation == CHEM_ION_HYDROGEN || chem_is_contaminant_id(G, salt_id))
			continue
		var/datum/chem_structure/bound = S.with_metal(M.cation)
		if(!bound || !chem_structure_match(bound))
			continue
		var/list/leaves = M.is_base() ? list(REAGENT_ID_WATER = 1) : list(REAGENT_ID_CONTAMINANT_ACID_RESIDUE = 1)
		. += chem_variant(list(substrate_id, salt_id), list(bound), null, leaves)

/// An acid dissolves a metal: the salt of the acid's anion and the metal, and hydrogen.
/datum/chem_process/displace/proc/dissolves(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_acid() || S.is_organic())
		return
	for(var/metal_id in G.ids)
		var/datum/chem_structure/M = G.structures[metal_id]
		if(M.is_ionic() || M.is_organic() || !M.cation || M.cation == CHEM_ION_HYDROGEN || chem_is_contaminant_id(G, metal_id))
			continue
		var/datum/chem_structure/salt = chem_structure_make(null, null, null, M.cation, S.anion)
		if(!chem_structure_match(salt))
			continue
		. += chem_variant(list(substrate_id, metal_id), list(salt, REAGENT_ID_HYDROGEN))

/// Two salts swap their ions (a double displacement): where at least one of the two new salts is a chemical that exists, the other being salts if not.
/datum/chem_process/displace/proc/swaps(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(!S.is_ionic() || S.is_acid() || S.is_base() || S.cation == CHEM_ION_HYDROGEN)
		return
	for(var/other_id in G.ids)
		if(substrate_id >= other_id || chem_is_contaminant_id(G, other_id)) // each pair once (text compares alphabetically)
			continue
		var/datum/chem_structure/O = G.structures[other_id]
		if(!O.is_ionic() || O.is_acid() || O.is_base() || O.cation == CHEM_ION_HYDROGEN || O.cation == S.cation || O.anion == S.anion)
			continue
		var/datum/chem_structure/first = chem_structure_make(null, null, null, S.cation, O.anion)
		var/datum/chem_structure/second = chem_structure_make(null, null, null, O.cation, S.anion)
		var/first_id = chem_structure_match(first)
		var/second_id = chem_structure_match(second)
		if(!first_id && !second_id)
			continue
		if(first_id && second_id)
			// Both exist: only the direction that goes on in the alphabet, or the pair would swap back and forth for ever.
			var/list/products_out = list(first_id, second_id)
			sortTim(products_out, GLOBAL_PROC_REF(cmp_text_asc))
			if("[products_out[1]]+[products_out[2]]" < "[substrate_id]+[other_id]")
				continue
		. += chem_variant(list(substrate_id, other_id), list(first, second), null, null, REAGENT_ID_CONTAMINANT_SALTS)

/datum/chem_process/displace/fallout(kind, datum/chem_structure/S, temperature)
	return GLOB.chem_fallout_displace

// ---- electrolyse ----

/datum/chem_process/electrolyse
	id = CHEM_PROCESS_ELECTROLYSE
	name = "Electrolyse"
	desc = "A current splits an ionic compound into its elements. The container stands on a hot plate that is on, with a clip-on electrode pair dipping into the liquid."
	kinds = list(CHEM_CATALYST_NONE)
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
	desc = "Two silanols join into a siloxane chain, giving up water (the chemistry side: silicone oil is lube). The workshop's polymers, which are materials, are the materials lane's."
	kinds = list(CHEM_CATALYST_NONE)
	band_class = REACTION_TEMP_HOT
	residue_routes = FALSE

/datum/chem_process/polymerise/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	. = list()
	if(length(S.cores) != 1 || !S.has_core(CHEM_CORE_SILOXANE) || !S.has_group(CHEM_GROUP_HYDROXYL) || length(S.links) || S.has_group(CHEM_GROUP_METAL_CENTRE))
		return
	var/list/rest = S.groups.Copy()
	rest -= CHEM_GROUP_HYDROXYL
	var/list/groups = rest + rest
	var/datum/chem_structure/T = chem_structure_make(list(CHEM_CORE_SILOXANE, CHEM_CORE_SILOXANE), groups)
	. += chem_variant(list(substrate_id, substrate_id), list(T), null, list(REAGENT_ID_WATER = 1))
