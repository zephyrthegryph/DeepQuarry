// Block structures (code/defines/content/chem_blocks.dm; the declarations: code/content/reagents/blocks/structures.dm).
//
// A chemistry reagent is declared by id in GLOB.chem_declared_structures (code/content/reagents/blocks/structures.dm): its `cores` (one or more), `groups` hung on
// them (a group named twice is two of it), `links` joining two parts (an ester, an amide), or, for an inorganic, a `cation` and an `anion`. By id and not by a var on
// the reagent type because a subtype inherits a var (every vodka is an ethanol) and a structure must not. Nothing else is declared: the formula, the class
// ("alcohol", "ester", "acid") and the tags ("organic", "polar", "ionic") a filter or the book reads are derived from the structure by the tables below.
//
// A structure is an immutable value: a process makes a new one (swap_group(), with_group(), ...) and the reaction it generates is found by looking the new
// structure up in the index of the reagents that declare one (chem_structure_index). The tables are built once from the reagent prototypes when the chemistry
// system builds them (chem_blocks_build(), called from initialize_chemical_reagents()), and every generated route is built from them (routes.dm).

/// reagent id => its /datum/chem_structure, for every reagent that declares one. Built by chem_blocks_build().
GLOBAL_LIST_EMPTY(chem_structures)
/// structure key => the ids of the chemistry reagents that have it (contaminants never are a product), sorted by id.
GLOBAL_LIST_EMPTY(chem_structure_index)

/// atoms of a core: symbol => count (hydrogen included, as the unsubstituted core has it).
GLOBAL_LIST_INIT(chem_core_atoms, list(
	CHEM_CORE_SHORT_CHAIN = list("C" = 2, "H" = 6),
	CHEM_CORE_LONG_CHAIN = list("C" = 12, "H" = 26),
	CHEM_CORE_RING = list("C" = 6, "H" = 6),
	CHEM_CORE_DOUBLE_RING = list("C" = 10, "H" = 8),
	CHEM_CORE_SUGAR_RING = list("C" = 5, "H" = 10, "O" = 5),
	CHEM_CORE_AMINO = list("C" = 2, "H" = 7, "N" = 1),
	CHEM_CORE_STEROID = list("C" = 17, "H" = 28),
	CHEM_CORE_NITROGEN_RING = list("C" = 5, "H" = 5, "N" = 1),
	CHEM_CORE_SILOXANE = list("Si" = 2, "O" = 1, "H" = 6),
	CHEM_CORE_PHORON_LATTICE = list("Ph" = 2),
))

/// atoms a group adds to the core it hangs on (a group takes the place of a hydrogen, so a negative count takes hydrogen away).
GLOBAL_LIST_INIT(chem_group_atoms, list(
	CHEM_GROUP_HYDROXYL = list("O" = 1),
	CHEM_GROUP_CARBONYL = list("O" = 1, "H" = -2),
	CHEM_GROUP_CARBOXYL = list("C" = 1, "O" = 2),
	CHEM_GROUP_AMINE = list("N" = 1, "H" = 1),
	CHEM_GROUP_NITRO = list("N" = 1, "O" = 2, "H" = -1),
	CHEM_GROUP_HALIDE = list("Cl" = 1, "H" = -1),
	CHEM_GROUP_THIOL = list("S" = 1),
	CHEM_GROUP_PHOSPHATE = list("P" = 1, "O" = 4, "H" = 1),
	CHEM_GROUP_METAL_CENTRE = list("Fe" = 1, "H" = -2),
))

/// atoms a link adds (it joins two parts, each of which gave up a hydrogen).
GLOBAL_LIST_INIT(chem_link_atoms, list(
	CHEM_LINK_ESTER = list("C" = 1, "O" = 2, "H" = -2),
	CHEM_LINK_AMIDE = list("C" = 1, "O" = 1, "N" = 1, "H" = -1),
))

/// ion => list(symbol, valence, is a compound ion that takes brackets when there are several).
GLOBAL_LIST_INIT(chem_ion_symbols, list(
	CHEM_ION_HYDROGEN = list("H", 1, FALSE),
	CHEM_ION_SODIUM = list("Na", 1, FALSE),
	CHEM_ION_POTASSIUM = list("K", 1, FALSE),
	CHEM_ION_AMMONIUM = list("NH4", 1, TRUE),
	CHEM_ION_CALCIUM = list("Ca", 2, FALSE),
	CHEM_ION_HEAVY_METAL = list("Pb", 2, FALSE),
	CHEM_ION_HYDROXIDE = list("OH", 1, TRUE),
	CHEM_ION_CHLORIDE = list("Cl", 1, FALSE),
	CHEM_ION_SULFATE = list("SO4", 2, TRUE),
	CHEM_ION_NITRATE = list("NO3", 1, TRUE),
	CHEM_ION_CARBONATE = list("CO3", 2, TRUE),
	CHEM_ION_PEROXIDE = list("O2", 2, FALSE),
	CHEM_ION_SILICATE = list("SiO3", 2, TRUE),
))

/// A structure: cores, groups, links, or a cation and anion. Never written after chem_structure_make().
/datum/chem_structure
	var/list/cores
	var/list/groups
	var/list/links
	var/cation
	var/anion
	/// The reagent that declares this structure (set when it is registered, chem_blocks_build()); null for one a process made along the way.
	var/reagent_id
	/// The canonical text of the structure: two structures are the same chemical when their keys are.
	var/key = ""
	/// The derived tags (CHEM_TAG_*).
	var/list/tags

/// A structure of these blocks, sorted into its canonical form with its key and tags. The lists given are copied.
/proc/chem_structure_make(list/core_list, list/group_list, list/link_list, cation = null, anion = null)
	RETURN_TYPE(/datum/chem_structure)
	var/datum/chem_structure/S = new /datum/chem_structure
	S.cores = core_list ? core_list.Copy() : list()
	S.groups = group_list ? group_list.Copy() : list()
	S.links = link_list ? link_list.Copy() : list()
	sortTim(S.cores, GLOBAL_PROC_REF(cmp_text_asc))
	sortTim(S.groups, GLOBAL_PROC_REF(cmp_text_asc))
	sortTim(S.links, GLOBAL_PROC_REF(cmp_text_asc))
	S.cation = cation
	S.anion = anion
	S.key = "[jointext(S.cores, ",")]|[jointext(S.groups, ",")]|[jointext(S.links, ",")]|[cation]|[anion]"
	S.tags = S.derive_tags()
	return S

/// The structure of the reagent with this id, or null.
/proc/chem_structure_of(reagent_id)
	RETURN_TYPE(/datum/chem_structure)
	return GLOB.chem_structures[reagent_id]

/// The chemistry reagent that has exactly this structure (the first by id), or null.
/proc/chem_structure_match(datum/chem_structure/S)
	var/list/ids = GLOB.chem_structure_index[S.key]
	return length(ids) ? ids[1] : null

/datum/chem_structure/proc/is_ionic()
	return !!cation && !!anion

/datum/chem_structure/proc/is_organic()
	return length(cores) > 0

/datum/chem_structure/proc/count_of(list/where, what)
	. = 0
	for(var/item in where)
		if(item == what)
			.++

/datum/chem_structure/proc/has_group(group)
	return (group in groups) ? TRUE : FALSE

/datum/chem_structure/proc/has_core(core)
	return (core in cores) ? TRUE : FALSE

/// An acid: a hydrogen cation on an anion that is not hydroxide (water is neither acid nor base) or peroxide (a peroxide is an oxidiser, not an acid).
/datum/chem_structure/proc/is_acid()
	return cation == CHEM_ION_HYDROGEN && anion && anion != CHEM_ION_HYDROXIDE && anion != CHEM_ION_PEROXIDE

/// A base: a hydroxide anion on a cation that is not hydrogen, or an organic amine that is nothing else.
/datum/chem_structure/proc/is_base()
	if(anion == CHEM_ION_HYDROXIDE)
		return cation && cation != CHEM_ION_HYDROGEN
	return is_organic() && has_group(CHEM_GROUP_AMINE) && !has_group(CHEM_GROUP_CARBOXYL) && !has_group(CHEM_GROUP_PHOSPHATE)

/// A copy with `from` (a group) replaced by `to` once; null when it does not have `from`. `to` null takes the group away.
/datum/chem_structure/proc/swap_group(from, to)
	RETURN_TYPE(/datum/chem_structure)
	if(!(from in groups))
		return null
	var/list/made = groups.Copy()
	made -= from // removes one
	if(to)
		made += to
	return chem_structure_make(cores, made, links, cation, anion)

/// A copy with a group added.
/datum/chem_structure/proc/with_group(group)
	RETURN_TYPE(/datum/chem_structure)
	var/list/made = groups.Copy()
	made += group
	return chem_structure_make(cores, made, links, cation, anion)

/// A copy with `from` (a core) replaced by `to` once; null when it does not have `from`.
/datum/chem_structure/proc/swap_core(from, to)
	RETURN_TYPE(/datum/chem_structure)
	if(!(from in cores))
		return null
	var/list/made = cores.Copy()
	made -= from
	made += to
	return chem_structure_make(made, groups, links, cation, anion)

// ---- derived: formula ----

/// The formula as text: carbon, hydrogen, then the rest by symbol, or the ions of an inorganic.
/datum/chem_structure/proc/formula()
	if(!length(cores))
		return is_ionic() ? ionic_formula() : (cation ? chem_ion_symbol(cation) : "?")
	var/list/atoms = list()
	for(var/core in cores)
		chem_atoms_add(atoms, GLOB.chem_core_atoms[core])
	for(var/group in groups)
		chem_atoms_add(atoms, GLOB.chem_group_atoms[group])
	for(var/link in links)
		chem_atoms_add(atoms, GLOB.chem_link_atoms[link])
	var/list/order = list()
	for(var/symbol in atoms)
		if(symbol != "C" && symbol != "H")
			order += symbol
	sortTim(order, GLOBAL_PROC_REF(cmp_text_asc))
	var/list/ranked = list()
	if(atoms["C"])
		ranked += "C"
	if(!isnull(atoms["H"]))
		ranked += "H"
	ranked += order
	var/text = ""
	for(var/symbol in ranked)
		var/amount = max(atoms[symbol], 0)
		if(amount <= 0)
			continue
		text += amount == 1 ? symbol : "[symbol][amount]"
	return text

/// "NaOH", "H2SO4", "Ca(OH)2": each ion as many times as the other's valence asks.
/datum/chem_structure/proc/ionic_formula()
	var/list/cation_row = GLOB.chem_ion_symbols[cation]
	var/list/anion_row = GLOB.chem_ion_symbols[anion]
	if(!cation_row || !anion_row)
		return "[cation][anion]"
	var/cation_valence = cation_row[2]
	var/anion_valence = anion_row[2]
	var/divisor = chem_gcd(cation_valence, anion_valence)
	return "[chem_ion_text(cation_row, anion_valence / divisor)][chem_ion_text(anion_row, cation_valence / divisor)]"

/// An ion `count` times: "Na2", "(OH)2", "SO4".
/proc/chem_ion_text(list/row, count)
	if(count <= 1)
		return row[1]
	return row[3] ? "([row[1]])[count]" : "[row[1]][count]"

/proc/chem_gcd(a, b)
	while(b)
		var/rest = a % b
		a = b
		b = rest
	return max(a, 1)

/proc/chem_ion_symbol(ion)
	var/list/row = GLOB.chem_ion_symbols[ion]
	return row ? row[1] : "[ion]"

/proc/chem_atoms_add(list/atoms, list/add)
	for(var/symbol in add)
		atoms[symbol] = (atoms[symbol] || 0) + add[symbol]

// ---- derived: class ----

/// What the structure is called: the first block that decides it.
/datum/chem_structure/proc/class_name()
	if(is_ionic())
		if(cation == CHEM_ION_HYDROGEN && anion == CHEM_ION_HYDROXIDE)
			return "water"
		if(anion == CHEM_ION_PEROXIDE)
			return "peroxide"
		if(is_acid())
			return "acid"
		if(is_base())
			return "base"
		return "salt"
	if(!length(cores))
		return cation ? "element" : "unclassified"
	if(has_group(CHEM_GROUP_METAL_CENTRE))
		return "organometallic"
	if(CHEM_LINK_ESTER in links)
		return "ester"
	if(CHEM_LINK_AMIDE in links)
		return "amide"
	if(has_group(CHEM_GROUP_CARBOXYL))
		return "carboxylic acid"
	if(has_group(CHEM_GROUP_PHOSPHATE))
		return "phosphate"
	if(has_group(CHEM_GROUP_NITRO))
		return "nitro compound"
	if(has_group(CHEM_GROUP_AMINE))
		return "amine"
	if(has_group(CHEM_GROUP_THIOL))
		return "thiol"
	if(has_group(CHEM_GROUP_HALIDE))
		return "organohalide"
	if(has_group(CHEM_GROUP_CARBONYL))
		return "carbonyl"
	if(has_core(CHEM_CORE_SUGAR_RING))
		return "sugar"
	if(has_group(CHEM_GROUP_HYDROXYL))
		return "alcohol"
	if(has_core(CHEM_CORE_STEROID))
		return "steroid"
	if(has_core(CHEM_CORE_SILOXANE))
		return "silicone"
	if(has_core(CHEM_CORE_PHORON_LATTICE))
		return "phoron lattice"
	if(has_core(CHEM_CORE_RING) || has_core(CHEM_CORE_DOUBLE_RING) || has_core(CHEM_CORE_NITROGEN_RING))
		return "aromatic"
	return "hydrocarbon"

// ---- derived: tags ----

/// The tags a structure has: what filters take by and the book lists.
/datum/chem_structure/proc/derive_tags()
	var/list/made = list()
	if(length(cores))
		made += CHEM_TAG_ORGANIC
	if(is_ionic())
		made += CHEM_TAG_IONIC
		made += CHEM_TAG_POLAR
	if(has_group(CHEM_GROUP_HYDROXYL) || has_group(CHEM_GROUP_CARBOXYL) || has_group(CHEM_GROUP_AMINE) || has_group(CHEM_GROUP_PHOSPHATE) || has_group(CHEM_GROUP_NITRO) || has_core(CHEM_CORE_AMINO))
		made |= CHEM_TAG_POLAR
	if(length(cores) && !(CHEM_TAG_POLAR in made))
		made += CHEM_TAG_NONPOLAR
	if(has_group(CHEM_GROUP_CARBOXYL) || has_group(CHEM_GROUP_PHOSPHATE) || is_acid())
		made |= CHEM_TAG_ACIDIC
	if(is_base())
		made |= CHEM_TAG_BASIC
	if(has_group(CHEM_GROUP_METAL_CENTRE) || cation == CHEM_ION_HEAVY_METAL)
		made |= CHEM_TAG_METALLIC
	if(has_group(CHEM_GROUP_THIOL) || anion == CHEM_ION_SULFATE)
		made |= CHEM_TAG_SULFUROUS
	if(has_group(CHEM_GROUP_HALIDE) || anion == CHEM_ION_CHLORIDE)
		made |= CHEM_TAG_HALOGENATED
	if(has_group(CHEM_GROUP_AMINE) || has_group(CHEM_GROUP_NITRO) || (CHEM_LINK_AMIDE in links) || has_core(CHEM_CORE_AMINO) || has_core(CHEM_CORE_NITROGEN_RING) || anion == CHEM_ION_NITRATE)
		made |= CHEM_TAG_NITROGENOUS
	if(has_group(CHEM_GROUP_NITRO) || anion == CHEM_ION_NITRATE || anion == CHEM_ION_PEROXIDE)
		made |= CHEM_TAG_OXIDISER
	if(has_core(CHEM_CORE_AMINO))
		made |= CHEM_TAG_BIOLOGICAL
	return made

// ---- the registry ----

/// Builds the structure tables from the declarations and the reagent prototypes (reagent id => prototype). Idempotent: a second call rebuilds.
/proc/chem_blocks_build(list/reagents)
	GLOB.chem_structures = list()
	GLOB.chem_structure_index = list()
	var/list/ids = list()
	for(var/reagent_id in reagents)
		ids += reagent_id
	sortTim(ids, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/id in ids)
		var/datum/reagent/R = reagents[id]
		var/datum/chem_structure/S = GLOB.chem_declared_structures[id]
		if(!S)
			continue
		S.reagent_id = id
		GLOB.chem_structures[id] = S
		if(istype(R, /datum/reagent/contaminant))
			continue
		LAZYINITLIST(GLOB.chem_structure_index[S.key])
		GLOB.chem_structure_index[S.key] += id
	log_world("Chemistry blocks: [length(GLOB.chem_structures)] structures, [length(GLOB.chem_structure_index)] distinct")
	chem_routes_build(reagents)
	chem_routes_install()

/// The tags of a reagent: its structure's, and `solid` when it is a solid.
/proc/chem_tags_of(datum/reagent/R)
	var/list/made = list()
	var/datum/chem_structure/S = GLOB.chem_structures[R.id]
	if(S)
		made += S.tags
	if(R.reagent_state == SOLID)
		made |= CHEM_TAG_SOLID
	return made

/// The formula, class and tags of a reagent, as the book reads them, or null for a reagent with no structure.
/proc/chem_structure_summary(reagent_id)
	var/datum/chem_structure/S = GLOB.chem_structures[reagent_id]
	if(!S)
		return null
	return list("formula" = S.formula(), "class" = S.class_name(), "tags" = S.tags.Copy())
