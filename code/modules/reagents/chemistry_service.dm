// The chemistry system (was SSchemistry): the reagent and reaction tables.
// It has no periodic work (reactions run on the holders), so it is a lazy system: the tables are
// built on first use through SSchemistry.ready(), not in a boot slot.
SYSTEM_DEF(chemistry)
	name = "Chemistry"

	var/list/chemical_reactions = list()
	var/list/chemical_reactions_by_product = list()
	var/list/instant_reactions_by_reagent = list()
	var/list/distilled_reactions_by_reagent = list()
	var/list/distilled_reactions_by_product = list()
	var/list/chemical_reagents = list()

// Reaction decls and reagent definitions: round-long registry singletons.

/datum/system/chemistry/boots_in_dag()
	return FALSE

/// Typed, so `SSchemistry.ready().var` reads as the system's own var.
/datum/system/chemistry/ready()
	RETURN_TYPE(/datum/system/chemistry)
	return ..()

/datum/system/chemistry/initialize()
	initialized = TRUE
	initialize_chemical_reagents()
	initialize_chemical_reactions()
	log_world("Chemistry service initialized: [length(chemical_reagents)] reagents, [length(chemical_reactions)] reactions.")

/datum/system/chemistry/stat_entry(msg)
	return "[..()]C: [length(chemical_reagents)] | R: [length(chemical_reactions)]"

//Chemical Reactions - Initialises all /datum/decl/chemical_reaction into a list
// It is filtered into multiple lists within a list.
// For example:
// chemical_reactions_by_reagent[REAGENT_ID_PHORON] is a list of all reactions relating to phoron
// Note that entries in the list are NOT duplicated. So if a reaction pertains to
// more than one chemical it will still only appear in only one of the sublists.
/datum/system/chemistry/proc/initialize_chemical_reactions()
	var/list/paths = GLOB.decls_repository.get_decls_of_subtype(/datum/decl/chemical_reaction)

	for(var/path in paths)
		var/datum/decl/chemical_reaction/D = paths[path]
		chemical_reactions += D

		var/list/scan_list = list()
		if(length(D.required_reagents))
			if(length(D.required_reagents)) scan_list += D.required_reagents
		if(length(D.catalysts))
			if(length(D.catalysts)) scan_list += D.catalysts

		for(var/i in 1 to length(scan_list))
			var/reagent_id = scan_list[i]

			var/list/add_to = instant_reactions_by_reagent // Default to instant reactions list, if something's gone wrong
			if(istype(D, /datum/decl/chemical_reaction/distilling))
				add_to = distilled_reactions_by_reagent

			if(D.result)
				if(istype(D, /datum/decl/chemical_reaction/distilling))
					LAZYINITLIST(distilled_reactions_by_product[D.result])
					distilled_reactions_by_product[D.result] |= D // for reverse lookup
				else
					LAZYINITLIST(chemical_reactions_by_product[D.result])
					chemical_reactions_by_product[D.result] |= D // for reverse lookup

			// we want to maintain original chemistry behavior, but still document all reactions above, only add to this list with the first reagent
			if(i > 1)
				continue
			LAZYINITLIST(add_to[reagent_id])
			add_to[reagent_id] |= D

//Chemical Reagents - Initialises all /datum/reagent into a list indexed by reagent id
/datum/system/chemistry/proc/initialize_chemical_reagents()
	var/paths = subtypesof(/datum/reagent)
	chemical_reagents = list()
	for(var/path in paths)
		var/datum/reagent/D = new path()
		if(!D.name)
			continue
		if(D.name == REAGENT_DEVELOPER_WARNING)
			continue
		chemical_reagents[D.id] = D
