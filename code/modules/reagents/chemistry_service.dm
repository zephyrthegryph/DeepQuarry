// The chemistry system (was SSchemistry): the reagent table. The reactions are transformations (code/library/transformations), compiled at world setup.
// It has no periodic work (reactions run on the holders), so it is a lazy system: the table is
// built on first use through SSchemistry.ready(), not in a boot slot.
SYSTEM_DEF(chemistry)
	name = "Chemistry"

	var/list/chemical_reagents = list()

// Reagent definitions: round-long registry singletons.

/datum/system/chemistry/boots_in_dag()
	return FALSE

/// Typed, so `SSchemistry.ready().var` reads as the system's own var.
/datum/system/chemistry/ready()
	RETURN_TYPE(/datum/system/chemistry)
	return ..()

/datum/system/chemistry/initialize()
	initialized = TRUE
	initialize_chemical_reagents()
	log_world("Chemistry service initialized: [length(chemical_reagents)] reagents, [length(GLOB.xform_rules)] transformations.")

/datum/system/chemistry/stat_entry(msg)
	return "[..()]C: [length(chemical_reagents)] | R: [length(GLOB.xform_rules)]"

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
