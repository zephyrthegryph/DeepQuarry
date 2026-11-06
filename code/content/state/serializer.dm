// Concrete singleton registry adapters for the engine serializer.
/// list(kind, id) for a registered singleton, or null.
/datum/state_registry_adapter/identity(datum/D)
	if(istype(D, /datum/material))
		var/datum/material/M = D
		if(GLOB.name_to_material[M.name] == M)
			return list(STATE_REGISTRY_MATERIAL, M.name)
	else if(istype(D, /datum/decl))
		if(GET_DECL(D.type) == D)
			return list(STATE_REGISTRY_DECL, "[D.type]")
	else if(istype(D, /datum/species))
		var/datum/species/S = D
		if(GLOB.all_species[S.name] == S)
			return list(STATE_REGISTRY_SPECIES, S.name)
	else if(istype(D, /datum/reagent))
		var/datum/reagent/R = D
		if(SSchemistry.ready().chemical_reagents[R.id] == R)
			return list(STATE_REGISTRY_REAGENT, R.id)
	return null

/datum/state_registry_adapter/lookup(list/registry)
	var/id = registry[2]
	switch(registry[1])
		if(STATE_REGISTRY_MATERIAL)
			return GLOB.name_to_material[id]
		if(STATE_REGISTRY_DECL)
			return GET_DECL(text2path(id))
		if(STATE_REGISTRY_SPECIES)
			return GLOB.all_species[id]
		if(STATE_REGISTRY_REAGENT)
			return SSchemistry.ready().chemical_reagents[id]
	return null
