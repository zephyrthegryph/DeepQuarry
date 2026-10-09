// Map-time resolvers (doc/rewrite/systems.md §9). Macro and contract: code/__defines/map_resolvers.dm.

/// type => its /datum/map_resolver_info, for every type under one that declares map_resolver(...): built at world setup, never after.
GLOBAL_LIST_EMPTY(map_resolvers)

/// The vars (besides the common ones) the resolver of `type` reads, in the order they were written: its map_resolver entry's `vars` (or an ancestor's).
/proc/map_resolver_vars_of(type)
	static_entries_ensure("map_resolver_vars_of([type])")
	var/datum/map_resolver_info/info = GLOB.map_resolvers[type]
	return info ? info.reads : list()

/// The resolver proc of `type`, or null: its map_resolver entry (or an ancestor's).
/proc/map_resolver_proc(type)
	static_entries_ensure("map_resolver_proc([type])")
	var/datum/map_resolver_info/info = GLOB.map_resolvers[type]
	return info?.resolver

/// Per-load scratch state for resolvers (key -> value), cleared when the load's atoms finish.
GLOBAL_LIST_EMPTY(map_resolve_scratch)

/// TRUE while a map load (or the boot map's initialization) is running.
/proc/map_loading()
	return SSatoms.initialize_depth || SSatoms.atom_initialized != INITIALIZATION_INNEW_REGULAR

/// Where a spawner's product goes: into what holds the spawner (a supply crate), else into the
/// closet on its tile, else onto the tile.
/proc/map_spawn_container(atom/loc)
	if(!isturf(loc))
		return loc
	var/obj/structure/closet/C = locate_on(loc, /obj/structure/closet)
	return C || loc

/// The map reader's hook: resolves `path` at `crds` from the model's var edits. TRUE when it was
/// resolved (the reader then creates nothing).
/proc/map_resolve_path(path, turf/crds, list/varedits)
	var/resolver = map_resolver_proc(path)
	if(!resolver)
		return FALSE
	if(!call(resolver)(crds, path, varedits))
		return FALSE
	return TRUE

/// SSatoms.InitAtom()'s hook for an atom that already exists (the compiled station map, or `new`
/// at runtime): resolves it with its var edits, then detaches it so BYOND frees it, never
/// initialized nor qdel'd. TRUE when resolved.
/proc/map_resolve_instance(atom/A)
	var/list/varedits = map_varedits_of(A)
	var/datum/map_resolver_info/info = GLOB.map_resolvers[A.type]
	if(!call(info.resolver)(A.loc, A.type, varedits))
		return FALSE
	A.tag = null
	if(ismovable(A))
		var/atom/movable/AM = A
		AM.loc = null // ALLOW(containment): a resolved map atom was never live; detached so BYOND frees it
	return TRUE

/// The var edits an instance carries over its type's defaults, over the vars its family's
/// resolver reads (MAP_RESOLVER_COMMON_VARS + the entry's vars; the name list is built once per
/// type). A named list var is included whenever set: a type's list default only exists on an
/// instance, and initial() cannot read it.
/proc/map_varedits_of(atom/A)
	var/static/list/names_by_type = list()
	var/list/names = names_by_type[A.type]
	if(!names)
		names = splittext(MAP_RESOLVER_COMMON_VARS, ";")
		names |= map_resolver_vars_of(A.type)
		for(var/name in names.Copy())
			if(!(name in A.vars))
				names -= name
		names_by_type[A.type] = names
	var/list/out
	var/list/all_vars = A.vars
	for(var/name in names)
		var/value = all_vars[name]
		if(islist(value))
			LAZYSET(out, name, value)
		else if(value != initial(A.vars[name]))
			LAZYSET(out, name, value)
	return out

/// The map resolver of mapping-only markers (previews, editor aids) that leave nothing behind.
/proc/map_resolve_discard(atom/loc, path, list/varedits)
	return TRUE

/// For a resolver whose work needs the rest of the load in place (another atom on the tile, a
/// controller elsewhere in the area): runs `proc(loc, path, varedits)` after the load's atoms have
/// initialized, or now when no load is running.
/proc/map_resolve_later(proc_path, atom/loc, path, list/varedits)
	if(SSatoms.atom_initialized == INITIALIZATION_INNEW_REGULAR && !SSatoms.initialize_depth)
		call(proc_path)(loc, path, varedits)
		return
	LAZYADD(SSatoms.deferred_resolvers, list(list(proc_path, loc, path, varedits)))

/// Runs the deferred resolvers and clears the load's scratch (the outermost InitializeAtoms(), once
/// its atoms are created).
/proc/map_resolve_flush_deferred()
	while(length(SSatoms.deferred_resolvers))
		var/list/rows = SSatoms.deferred_resolvers
		SSatoms.deferred_resolvers = null
		for(var/list/row as anything in rows)
			call(row[1])(row[2], row[3], row[4])
	GLOB.map_resolve_scratch.Cut()
