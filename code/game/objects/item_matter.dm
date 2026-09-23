// Item material composition ("matter"): static per-type defaults, copy-on-write per instance.
//
// A type declares its default composition with DEFAULT_MATTER(list(...)) in its type body
// (see code/__defines/materials.dm). That expands to a default_matter() override returning a
// proc-local static list, so every instance of the type shares one read-only table, and a
// subtype that does not redeclare it inherits its parent's.
//
// The instance var `matter` is null ("use the type default") until this instance differs.
//  - Read with get_matter(). Never mutate what it returns.
//  - Mutate only after own_matter(), which gives this instance a private copy.
//  - Replace wholesale with set_matter(list), which takes ownership of the list passed.

/obj/item/proc/default_matter()
	return null

/// This item's material composition (material name -> amount). Read-only: may be the shared type table.
/obj/item/proc/get_matter()
	RETURN_TYPE(/list)
	return isnull(matter) ? default_matter() : matter

/// Copy-on-write: give this item a private matter list and return it for editing.
/obj/item/proc/own_matter()
	RETURN_TYPE(/list)
	if(isnull(matter))
		var/list/shared = default_matter()
		matter = shared ? shared.Copy() : list()
	return matter

/// Replace this item's composition. Takes ownership of new_matter; pass a fresh list, or null
/// to go back to the type default. An empty list means "made of nothing".
/obj/item/proc/set_matter(list/new_matter)
	matter = new_matter

/// Declared default tables by type (path -> list, or null for an explicit "no matter").
/// Filled by DEFAULT_MATTER's static initialisers at world start. No initialiser here: static
/// inits run in no fixed order, and one could wipe entries registered before it.
GLOBAL_REAL_VAR(list/dq_default_matter_registry)

/// Records a type's declared table so it can be read per type without an instance.
/// Called only from DEFAULT_MATTER. Returns the table unchanged.
/proc/dq_register_default_matter(path, list/table)
	if(isnull(dq_default_matter_registry))
		dq_default_matter_registry = list()
	dq_default_matter_registry[path] = table
	return table

/// A type's default matter table, as default_matter() would return for a fresh instance,
/// read without creating one. Walks parent types to the nearest DEFAULT_MATTER declaration.
/proc/dq_type_default_matter(path)
	RETURN_TYPE(/list)
	var/static/list/resolved
	if(isnull(resolved))
		resolved = list()
	if(path in resolved)
		return resolved[path]
	var/list/table = null
	if(dq_default_matter_registry)
		for(var/datum/T = path; T; T = initial(T.parent_type))
			if(T in dq_default_matter_registry)
				table = dq_default_matter_registry[T]
				break
	resolved[path] = table
	return table
