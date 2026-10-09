// Loot declarations as CAPABILITIES entries (doc/rewrite/proposals/loot_and_map_resolvers.md).
//
// A loot table is declared in the CAPABILITIES block of the type it belongs to: a spawner (/obj/random/toolbox), a landmark, or a pure table
// (/loot/maint/junk, an abstract type nobody makes):
//
//   CAPABILITIES(/obj/random/toolbox)
//       loot(table = list(/obj/item/storage/toolbox/mechanical = 3, /obj/item/storage/toolbox/electrical = 2), count = 1, chance = 100)
//
// The entry carries the rows the roll engine reads (code/datums/loot/loot.dm: /datum/loot_decl, loot_spawn(), loot_emit()):
//
//   table =        the weighted table one entry is rolled from, `count` times: type paths (`/obj/item/x = 5` for weight 5, weight 1 without), a
//                  nested table or spawner (rolled in turn), a /turf path (changes the turf) and the row constructors below.
//   count =        how many rolls of the table (default 1).        chance = percent chance that anything spawns at all (default 100).
//   all =          entries that all spawn, every time, after the table rolled.
//   hook =         GLOBAL_PROC_REF(x): proc(atom/spawned, path, list/varedits, datum/loot_rng/rng) run on each atom this declaration spawns itself.
//   per_round =    TRUE: the table's first roll is made once per round per spawner type, then reused (a themed spawner picks one theme).
//   unlucky =      the tier an unlucky searcher draws from, always.  uncommon = loot_tier(chance, list(entries)), rare = loot_tier(chance, list(entries)):
//                  the tiers of a searched pile (rolled uncommon first, then rare).  gamma_chance = percent chance of a unique item from the pool.
//   depletion =    loot_depletion(left, delete): the source can be searched `left` times in total; `delete`: qdel it then.
//   repeat_search = TRUE: the same searcher may search again.
//
// Rows of a table: loot_set(weight, list(entries)) spawns the group together; loot_sub(weight, list(entries)) is a nested weighted pick;
// loot_stack(weight, path, amount); loot_types(weight, list) is a computed list of equal weight (subtypesof()).
//
// A subtype changes what it inherits with configure(loot(...)): the rows it names replace the inherited ones (what spawns, table + all + per_round,
// as one unit); the rest stay. A plain loot() under a type that inherits one is an error. A searchable pile names its table with
// loot_search(table = /loot/maint/junk). The rolls themselves, their seeds and the cache are code/datums/loot/loot.dm.

STATIC_ENTRY(loot)
STATIC_ENTRY(loot_search)

/// The root of the pure loot tables (a table that is not an atom's: a searchable pile's, a costume's, a nested theme): each is an abstract type nobody makes,
/// declaring its loot(...) in its own CAPABILITIES block, and named in other tables and in loot_search(table =) by its path.
/loot
	abstract_type = /loot

/proc/loot(table = null, count = null, chance = null, all = null, hook = null, per_round = null, unlucky = null, uncommon = null, rare = null, gamma_chance = null, depletion = null, repeat_search = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_LOOT, null, list("table" = table, "count" = count, "chance" = chance, "all" = all, "hook" = hook, "per_round" = per_round, \
		"unlucky" = unlucky, "uncommon" = uncommon, "rare" = rare, "gamma_chance" = gamma_chance, "depletion" = depletion, "repeat_search" = repeat_search))

/// loot_tier(chance, list(entries)): a searched pile's uncommon or rare tier.
/proc/loot_tier(chance, list/entries)
	return list(chance, entries)

/// loot_depletion(left, delete): the source can be searched `left` times in total; `delete`: qdel it then.
/proc/loot_depletion(left, delete)
	return list(left, delete)

/// Table row: every entry of the list spawns together, weight `weight`.
/proc/loot_set(weight, list/entries)
	return new /datum/loot_entry/group(weight, entries)

/// Table row: a nested weighted pick among the list's entries (`/path = weight`, weight 1 without), weight `weight`.
/proc/loot_sub(weight, list/entries)
	return new /datum/loot_entry/sub(weight, entries)

/// Table row: a stack of `path` with `amount`, weight `weight`.
/proc/loot_stack(weight, path, amount)
	return new /datum/loot_entry/stack(weight, path, amount)

/// Table row: one of the paths in `types` (evaluated once, e.g. subtypesof()), each with weight `weight` (so the row weighs weight * the list's length).
/proc/loot_types(weight, list/types)
	return new /datum/loot_entry/sub/types(weight, types)

/// loot_search(table = /loot/x, wake_chance = 0): the pile type searches `table` (a pure table or a spawner with a loot entry); `wake_chance` percent of the
/// time a raccoon jumps out when it yields something.
/proc/loot_search(table = null, wake_chance = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_LOOT_SEARCH, null, list("table" = table, "wake_chance" = wake_chance))

/// What a configure(kind(...)) leaves: the inherited arguments, with the ones `changes` names (non-null) replaced. `groups` are the argument names that
/// replace one another as a unit (naming any of them drops all of the inherited ones).
/proc/entry_merge_args(datum/entry/old, datum/entry/changes, list/groups = null)
	var/list/merged = old.args ? old.args.Copy() : list()
	for(var/list/group as anything in groups)
		var/named = FALSE
		for(var/name in group)
			if(!isnull(changes.args?[name]))
				named = TRUE
		if(named)
			for(var/name in group)
				merged[name] = null
	for(var/name in changes.args)
		if(!isnull(changes.args[name]))
			merged[name] = changes.args[name]
	return merged

/datum/entry_engine/loot
	kind = ENTRY_LOOT
	static_kind = TRUE
	singleton = TRUE

/// A subtype's loot rows over the inherited ones. What spawns (table, all, per_round) is replaced as one unit, as the old per-type vars inherited.
/datum/entry_engine/loot/merge(datum/entry/old, datum/entry/changes)
	return entry_make(ENTRY_LOOT, null, entry_merge_args(old, changes, list(list("table", "all", "per_round"))))

/// Builds the loot declarations: one /datum/loot_decl per declaring type's table, shared by that type and its subtypes (as the one declaration of
/// a type was shared by the types under it), keyed by every type under a declaring one. Nothing is built after setup.
/datum/entry_engine/loot/static_built(list/by_type)
	var/list/decl_of_table = list()
	var/list/decls = list()
	for(var/type in by_type)
		var/datum/type_table/T = by_type[type]
		if(!(T in decl_of_table))
			var/datum/centry/C = static_find(T, ENTRY_LOOT)
			var/datum/loot_decl/decl = null
			if(C)
				decl = new
				if(!decl.build_entry(C.item))
					decl = null
			decl_of_table[T] = decl
		var/datum/loot_decl/known = decl_of_table[T]
		if(known)
			decls[type] = known
	GLOB.loot_decls = decls

/datum/entry_engine/loot_search
	kind = ENTRY_LOOT_SEARCH
	static_kind = TRUE
	singleton = TRUE

/datum/entry_engine/loot_search/merge(datum/entry/old, datum/entry/changes)
	return entry_make(ENTRY_LOOT_SEARCH, null, entry_merge_args(old, changes))

/// The table a pile of `type` searches (its loot_search(table =) entry, inherited), or null.
/proc/loot_search_table(type)
	var/datum/entry/E = static_entry_of(type, ENTRY_LOOT_SEARCH)
	return E?.args["table"]

/// Percent chance that a search of a pile of `type` wakes a raccoon.
/proc/loot_search_wake_chance(type)
	var/datum/entry/E = static_entry_of(type, ENTRY_LOOT_SEARCH)
	return E?.args["wake_chance"] || 0
