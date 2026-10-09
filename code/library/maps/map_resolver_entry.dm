// Map-time resolvers as a CAPABILITIES entry (doc/rewrite/proposals/loot_and_map_resolvers.md).
//
// A map atom whose only job is to change something at load (a floor decal painted onto its turf, an /obj/random rolled into loot, a window spawner, a
// landmark that records a coordinate) declares a resolver instead of an Initialize() that ends in INITIALIZE_HINT_QDEL:
//
//   CAPABILITIES(/obj/effect/floor_decal)
//       map_resolver(GLOBAL_PROC_REF(resolve_floor_decal))
//
//   CAPABILITIES(/obj/effect/gibspawner)
//       map_resolver(GLOBAL_PROC_REF(resolve_gibspawner), vars = list("bloodcolor", "fleshcolor"))
//
// The resolver is `proc(atom/loc, path, list/varedits)`: loc is where the atom would be (the turf for map placement), path its type, varedits the map's
// var edits for this instance (null when none). It does the work and returns TRUE, or returns FALSE to have the atom made normally (a landmark that has to
// stay). `vars` names the vars (besides MAP_RESOLVER_COMMON_VARS) it reads with MAP_VAR: only these are captured as var edits from an existing instance
// (the compiled map, runtime `new`); the map reader passes the model's edits as they are. The type and everything under it resolves; a subtype changes what
// it inherits with configure(map_resolver(GLOBAL_PROC_REF(x), vars = list(...))), naming only what changes. Consulted by:
//   - the map reader (templates, expedition sites, anything load_map() places): before instancing, so a resolved atom is never created;
//   - SSatoms.InitAtom() (the compiled station map, which BYOND instances itself, and `new` at runtime): before Initialize, so the atom is never
//     initialized nor qdel'd; it is detached and BYOND frees it.
// Resolvers run inside map loading: they must not sleep. The per-type cache is built at world setup (the static_entries system), before the first load.

STATIC_ENTRY(map_resolver)

/proc/map_resolver(resolver = null, vars = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_MAP_RESOLVER, null, list("resolver" = resolver, "vars" = vars))

/// What the cache holds for a resolvable type: the resolver proc and the vars its family reads.
/datum/map_resolver_info
	var/resolver
	/// The vars the entry names (besides MAP_RESOLVER_COMMON_VARS), in the order they were written.
	var/list/reads

/datum/entry_engine/map_resolver
	kind = ENTRY_MAP_RESOLVER
	static_kind = TRUE
	singleton = TRUE

/// A subtype's resolver or vars over the inherited ones: what it does not name stays.
/datum/entry_engine/map_resolver/merge(datum/entry/old, datum/entry/changes)
	return entry_make(ENTRY_MAP_RESOLVER, null, entry_merge_args(old, changes))

/// Builds the per-type resolver cache: every type under a declaring type, with inheritance resolved, keyed by type. SSatoms.InitAtom() and the map
/// reader read it; nothing builds after setup.
/datum/entry_engine/map_resolver/static_built(list/by_type)
	var/list/info_of_table = list()
	var/list/resolvers = list()
	for(var/type in by_type)
		var/datum/type_table/T = by_type[type]
		if(!(T in info_of_table))
			var/datum/centry/C = static_find(T, ENTRY_MAP_RESOLVER)
			var/datum/map_resolver_info/info = null
			var/datum/entry/E = C?.item
			if(E?.args["resolver"])
				info = new
				info.resolver = E.args["resolver"]
				info.reads = E.args["vars"] ? E.args["vars"].Copy() : list()
			info_of_table[T] = info
		var/datum/map_resolver_info/known = info_of_table[T]
		if(known)
			resolvers[type] = known
	GLOB.map_resolvers = resolvers
