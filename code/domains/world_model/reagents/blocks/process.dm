// Processes (the fifteen of them: code/content/reagents/blocks/processes.dm).
//
// A process is a change to a structure that a mixture can be made to do: oxidise, condense, neutralise, ... It names what it needs (an added reagent, a catalyst
// kind, a temperature) and which structures it can act on and what they become. At boot every process is run over every structure that exists
// (chem_routes_build(), routes.dm): where the new structure is a chemical that exists, the route makes it; where it is not, the route makes organic residue; the
// reaction the generator writes goes into the same transformation table as every hand-written recipe.
//
// Byproducts are balanced, one unit of anything being one part: a step that gives up a water makes a water, a step that frees hydrogen chloride makes it.

/// One thing a process can do to one structure: the substrates (units of 1 each; the first is the one the rule is filed under), the structures (or reagent ids)
/// they become, the reagent it adds and the reagents it also makes.
/datum/chem_variant
	/// Reagent ids of the substrates, 1u each.
	var/list/from
	/// What they become, one entry each: a /datum/chem_structure (looked up among the chemicals that exist) or a reagent id (text).
	var/list/to
	/// reagent id => units added per unit of substrate (an oxidiser, a nitrating acid, water to hydrolyse with).
	var/list/agents
	/// reagent id => units also made.
	var/list/byproducts
	/// A reagent id that is the product when no chemical has the structure (default: the process's residue); a variant with an explicit product ignores it.
	var/residue
	/// The catalyst kinds this variant runs on, or null for all of its process's (an enzyme oxidation, an uncatalysed amide).
	var/list/kinds
	/// reagent ids that stop this variant (an uncatalysed amide is blocked by the sulphuric acid that would make an ester of it).
	var/list/blocked
	/// An explicit band for this variant, kelvin (range low, ideal low, ideal high, range high), or null for its process's.
	var/list/band
	/// reagent id => units made per unit of product by this variant alone (the poisons it leaves: cyanide from the cyanide arm).
	var/list/fallout

/// A variant of these substrates.
/proc/chem_variant(list/from, list/to, list/agents = null, list/byproducts = null, residue = null, list/kinds = null, list/blocked = null, list/band = null, list/fallout = null)
	RETURN_TYPE(/datum/chem_variant)
	var/datum/chem_variant/V = new /datum/chem_variant
	V.from = from
	V.to = to
	V.agents = agents
	V.byproducts = byproducts
	V.residue = residue
	V.kinds = kinds
	V.blocked = blocked
	V.band = band
	V.fallout = fallout
	return V

/// What the generator hands a process: every structure that exists (reagent id => structure), and the condensations that made a chemical (structure key => rows of
/// list(acid id, partner id): what hydrolysis undoes).
/datum/chem_gen
	var/list/structures
	/// The ids of the structures, sorted: the order every loop over them runs in.
	var/list/ids
	var/list/condensed
	/// reagent id => prototype: what exists (an agent or catalyst that does not is a route that cannot be written).
	var/list/reagents

/// A process. Subtypes (code/content/reagents/blocks/processes.dm) override chem_variants(), fallout() and the vars, and declare() for a band that is arithmetic.
/datum/chem_process
	var/id
	var/name
	var/desc
	/// Reserved: the process is declared but generates nothing yet.
	var/reserved = FALSE
	/// The catalyst kinds (CHEM_CATALYST_*) a route can run on: one route per kind.
	var/list/kinds
	/// The temperature class (REACTION_TEMP_*) the process runs in with nothing but heat; `band` overrides it.
	var/band_class = REACTION_TEMP_HOT
	/// An explicit band, kelvin: list(range low, ideal low, ideal high, range high), or null for the class's.
	var/list/band
	/// A catalyst does not move the band (a process that is set apart from another by its temperature).
	var/fixed_band = FALSE
	/// Water in the mixture stops it (a condensation is undone by water).
	var/blocked_by_water = FALSE
	/// It needs a current through the mixture (an electrolysis: the container stands on a plate that is on).
	var/needs_current = FALSE
	/// What the process makes when no chemical has the structure it ends with.
	var/residue_id = REAGENT_ID_CONTAMINANT_ORGANIC_RESIDUE
	/// A step of it is clean: no share of the product is lost to residue for want of selectivity (neutralising, an electrolysis).
	var/clean = FALSE
	/// Write a route for a variant that ends in residue only.
	var/residue_routes = TRUE
	/// What a step of it says, when it is a loud one.
	var/says = ""
	/// Where its routes stand among the processes' when two want the same reactants: lower first (amination before reduction).
	var/rank = 50

/datum/chem_process/New()
	..()
	declare()

/// Sets what a type's vars cannot say (a band in kelvin is arithmetic).
/datum/chem_process/proc/declare()
	return

/// The variants of this process for the substrate `substrate_id` (structure `S`).
/datum/chem_process/proc/chem_variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	return list()

/// Contaminants a step of this process leaves besides its product: reagent id => units per unit of product, given the catalyst kind, the substrate and the
/// temperature (K). Where the trace-potent contaminants come from.
/datum/chem_process/proc/fallout(kind, datum/chem_structure/S, temperature)
	return list()

/// The band the process runs in on `kind`, before a solid catalyst moves it: list(range low, ideal low, ideal high, range high), kelvin.
/datum/chem_process/proc/band_for(kind, list/override = null)
	var/list/base = override || band
	if(!base)
		base = GLOB.reaction_temperature_classes[band_class]
	if(kind == CHEM_CATALYST_ENZYME)
		return list(T0C + 15, T0C + 28, T0C + 42, T0C + 50)
	var/shift = 0
	if(!fixed_band && (kind == CHEM_CATALYST_ACID || kind == CHEM_CATALYST_BASE))
		shift = CHEM_DISSOLVED_REDUCTION
	return list(base[1] - shift, base[2] - shift, base[3] - shift, base[4] - shift)

/// processes: id => the one instance of each process type, built once.
GLOBAL_LIST_EMPTY(chem_processes)

/// Makes the process instances. A process type with no id is a base.
/proc/chem_processes_build()
	GLOB.chem_processes = list()
	var/list/made = list()
	for(var/type in subtypesof(/datum/chem_process))
		var/datum/chem_process/proto = type
		if(!initial(proto.id))
			continue // a base type
		var/datum/chem_process/P = new type
		made[P.id] = P
	var/list/keys = list()
	for(var/made_id in made)
		var/datum/chem_process/ranked = made[made_id]
		keys += "[100 + ranked.rank]:[made_id]"
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/key in keys)
		var/list/split = splittext(key, ":")
		GLOB.chem_processes[split[2]] = made[split[2]]

/// The process with this id, or null.
/proc/chem_process_of(process_id)
	RETURN_TYPE(/datum/chem_process)
	return GLOB.chem_processes[process_id]

/// Does the structure have a core of a ring kind (the ones a substitution acts on)?
/proc/chem_has_ring(datum/chem_structure/S)
	return S.has_core(CHEM_CORE_RING) || S.has_core(CHEM_CORE_DOUBLE_RING) || S.has_core(CHEM_CORE_NITROGEN_RING)

/// The empty structure: what a variant ends in when it makes nothing that anyone has (it matches no chemical, so the route makes residue).
/proc/chem_nothing()
	return chem_structure_make()

/// The variants of the process `process_id` for a substrate (what the generator asks, and the tests).
/proc/chem_process_variants(process_id, substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	var/datum/chem_process/P = GLOB.chem_processes[process_id]
	return P ? P.chem_variants(substrate_id, S, G) : list()
