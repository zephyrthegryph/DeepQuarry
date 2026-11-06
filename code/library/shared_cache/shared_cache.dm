// Concrete singleton identity adapters for generic cache keys.
/datum/decl/shared_cache_stable_identity()
	return GLOB.decls_repository.fetched_decls[type] == src

/datum/material/shared_cache_stable_identity()
	return !!name && GLOB.name_to_material[name] == src
