// Process chemicals and clashes (the machinery; the declarations: code/content/reagents/blocks/agents.dm and clashes.dm).
//
// A process chemical is a chemical that IS a process: poured in, it performs the process on whatever it can act on, without the usual setup (no hydrogen and metal
// catalyst, no nitric acid and dissolved acid, no enzyme), and is consumed. It is less selective than the proper method and leaves its own residue. Its routes are
// generated like any other (chem_route_emit(), kind CHEM_CATALYST_AGENT); what it can act on is its own variants() (it is a process of its own: a hydride reduces
// every reducible group, a strong oxidiser goes all the way to a carboxyl). These are what the dirty shortcuts of the staples are made of.
//
// A clash is the other kind of reaction: two chemicals that meet react by the groups they carry (an acid group and an amine make a salt, a nitro compound and an
// amine nitrosamine, ...), with no catalyst and no temperature unless the clash names one. They run in a loose container and in the stomach (`ingested`, where
// swallowed doses mix) and never in the bloodstream or on the skin (chem_route.can_run(), holder.clash_allowed()).

/// A process chemical.
/datum/chem_agent
	/// The reagent that is the process.
	var/reagent_id
	/// The process it performs (CHEM_PROCESS_*): its routes are filed under it.
	var/process_id
	/// The share (0..1) of a step's product that is clean: the rest is organic residue.
	var/selectivity = 0.7
	/// An explicit band, kelvin: list(range low, ideal low, ideal high, range high), or null for its process's.
	var/list/band
	/// reagent id => units left per unit of product (its own residue, and the poisons it carries).
	var/list/leaves
	/// A condensation by it goes on in water (a coupling agent does not remove it).
	var/ignores_water = FALSE
	/// What it says in the book.
	var/desc = ""

/// The variants this agent performs on a substrate: chem_variant() rows whose `agents` name this agent in place of the process's own.
/datum/chem_agent/proc/variants(substrate_id, datum/chem_structure/S, datum/chem_gen/G)
	return list()

/// More it leaves given the substrate and the heat (K): reagent id => units per unit of product (dioxin from bleach on a hot ring, nitrosamine from a nitrating mix on an amine).
/datum/chem_agent/proc/trace(datum/chem_structure/S, temperature)
	return list()

/// agent key => the one instance of each agent type (a type with no reagent_id is a base).
GLOBAL_LIST_EMPTY(chem_agents)

/// Makes the agent instances.
/proc/chem_agents_build()
	GLOB.chem_agents = list()
	var/list/made = list()
	for(var/type in subtypesof(/datum/chem_agent))
		var/datum/chem_agent/proto = type
		if(!initial(proto.reagent_id))
			continue // a base type
		var/datum/chem_agent/A = new type
		made["[A.reagent_id]:[A.process_id]"] = A
	// By the rank of the process it performs, then by key: an amination ranks before a reduction, as the processes' own do.
	var/list/ranked = list()
	for(var/key in made)
		var/datum/chem_agent/A = made[key]
		var/datum/chem_process/P = chem_process_of(A.process_id)
		ranked["[100 + (P ? P.rank : 50)]:[key]"] = key
	var/list/keys = list()
	for(var/sort_key in ranked)
		keys += sort_key
	sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc))
	for(var/sort_key in keys)
		GLOB.chem_agents[ranked[sort_key]] = made[ranked[sort_key]]

/// The agents that are this reagent (one per process it performs), or an empty list.
/proc/chem_agents_of(reagent_id)
	. = list()
	for(var/key in GLOB.chem_agents)
		var/datum/chem_agent/A = GLOB.chem_agents[key]
		if(A.reagent_id == reagent_id)
			. += A

// ---- clashes ----

/// One clash: two chemicals that meet, and what they make.
/datum/chem_clash
	var/a
	var/b
	/// reagent id => units made (the first is the product).
	var/list/makes
	/// An explicit band (kelvin: range low, ideal low, ideal high, range high), or null: it runs at any temperature.
	var/list/band
	var/note = ""

/proc/chem_clash(a, b, list/makes, list/band = null, note = "")
	RETURN_TYPE(/datum/chem_clash)
	var/datum/chem_clash/C = new /datum/chem_clash
	C.a = a
	C.b = b
	C.makes = makes
	C.band = band
	C.note = note
	return C

/// Writes the route of every clash the declarations make (chem_clash_rows(), code/content/reagents/blocks/clashes.dm). Returns how many were new.
/proc/chem_clashes_build(datum/chem_gen/G)
	var/written = 0
	var/list/clashes = chem_clash_rows(G)
	for(var/datum/chem_clash/C as anything in clashes)
		if(C.a == C.b || !G.reagents[C.a] || !G.reagents[C.b])
			continue
		var/list/pair = list(C.a, C.b)
		sortTim(pair, GLOBAL_PROC_REF(cmp_text_asc))
		var/list/products = list()
		var/ok = TRUE
		for(var/made_id in C.makes)
			products += made_id
			if(!G.reagents[made_id])
				ok = FALSE
		if(!ok)
			continue
		var/route_id = "[CHEM_PROCESS_CLASH]:[pair[1]]+[pair[2]]>[jointext(products, "+")]"
		if(GLOB.chem_routes[route_id])
			continue
		var/datum/chem_route/R = new /datum/chem_route
		R.id = route_id
		R.process_id = CHEM_PROCESS_CLASH
		R.kind = CHEM_CATALYST_CONTACT
		R.substrate_id = pair[1]
		R.from = pair
		R.takes = list()
		R.takes[pair[1]] = 1
		R.takes[pair[2]] = 1
		var/list/rows = list()
		for(var/make_id in C.makes)
			rows += list(list(make_id, C.makes[make_id]))
		R.makes = rows
		R.products = products
		R.matched = TRUE
		R.band_base = C.band
		R.fixed_band = TRUE
		R.clean = TRUE
		GLOB.chem_routes[route_id] = R
		written++
	return written
