//I AM THE LOREMASTER, ARE YOU THE GATEKEEPER?

/datum/lore/loremaster
	var/list/organizations

/// A global datum: its New() writes this var before the engine tables exist (a CAPABILITIES entry is not readable yet), so the legacy table proc declares it.
/datum/lore/loremaster/ownership()
	. = ..()
	. += owns(nameof(organizations), is_list = TRUE)

/datum/lore/loremaster/New()

	var/list/paths = subtypesof(/datum/lore/organization)
	for(var/path in paths)
		// Some intermediate paths are not real organizations (ex. /datum/lore/organization/mil). Only do ones with names
		var/datum/lore/organization/instance = path
		if(initial(instance.name))
			instance = new path()
			rel_add(src, nameof(organizations), instance, path)
