// One declared loot system (doc/rewrite/systems.md §8). Runtime: code/datums/loot/loot.dm.
//
// A loot declaration is a line next to the type it describes:
//
//   DECLARE_LOOT(/obj/random/toolbox, LOOT_TABLE(/obj/item/storage/toolbox/mechanical = 3,
//       /obj/item/storage/toolbox/electrical = 2), LOOT_COUNT(1), LOOT_CHANCE(100))
//
// It becomes a /datum/loot_decl subtype named after the path (/datum/loot_decl/obj/random/toolbox),
// built once and shared. A subtype without its own line inherits its parent's declaration, and
// a subtype's line merges over its parent's (only the specs it names are replaced; what spawns -
// table, all, per_round - is replaced as one unit), the way the old per-type vars inherited. Pure tables that are not atoms are declared under /loot/...
// and named with LOOT_REF(/loot/...).
//
// Table entries: a type path (weight defaults to 1: `/obj/item/x = 5` for weight 5); a path with
// its own declaration or map resolver (e.g. another /obj/random) rolls that one (nesting); a
// /turf path changes the turf. LOOT_SET spawns a group together, LOOT_SUB is a nested weighted
// pick, LOOT_STACK a stack with an amount, LOOT_TYPES a computed list (typesof()) of equal weight.
//
// Rolls are seeded: map-time rolls use GLOB.loot_seed ^ hash(x, y, z, type), so a round's map loot
// is reproducible from its seed; runtime rolls also mix a serial.

/// Declares PATH's loot. SPECS are the LOOT_* macros below.
#define DECLARE_LOOT(PATH, SPECS...) /datum/loot_decl##PATH/specs() { return loot_merge_specs(..(), list(SPECS)); }

/// The declaration type of PATH, for a var that names a table (`loot_decl = LOOT_REF(/loot/maint/junk)`)
/// or as a nested table entry.
#define LOOT_REF(PATH) /datum/loot_decl##PATH

/// The weighted table one entry is rolled from, LOOT_COUNT times.
#define LOOT_TABLE(ENTRIES...) "table" = list(ENTRIES)
/// How many rolls of the table (default 1).
#define LOOT_COUNT(N) "count" = N
/// Percent chance that anything spawns at all (default 100).
#define LOOT_CHANCE(N) "chance" = N
/// Entries that all spawn, every time (after the table rolls).
#define LOOT_ALL(ENTRIES...) "all" = list(ENTRIES)
/// proc(atom/spawned, path, list/varedits, datum/loot_rng/rng) run on each atom this declaration
/// spawns directly (not on what nested tables spawn).
#define LOOT_HOOK(PROC) "hook" = PROC
/// The table's first roll is made once per round per declaration (a themed spawner picks one theme
/// for the whole round), then reused.
#define LOOT_PER_ROUND "per_round" = TRUE

/// Table entry: every path in ENTRIES spawns together, weight W.
#define LOOT_SET(W, ENTRIES...) new /datum/loot_entry/group(W, list(ENTRIES))
/// Table entry: a nested weighted pick (`/path = weight` entries), weight W.
#define LOOT_SUB(W, ENTRIES...) new /datum/loot_entry/sub(W, list(ENTRIES))
/// Table entry: a stack of PATH with AMOUNT, weight W.
#define LOOT_STACK(W, PATH, AMOUNT) new /datum/loot_entry/stack(W, PATH, AMOUNT)
/// Table entry: one of the paths in the list LIST_EXPR (evaluated once, e.g. subtypesof()), each
/// with weight W (so the entry weighs W * the list's length).
#define LOOT_TYPES(W, LIST_EXPR) new /datum/loot_entry/sub/types(W, LIST_EXPR)

// Searchable loot (loot piles, trash piles): tiers rolled by loot_search().
/// Only an unlucky searcher draws from this tier, always.
#define LOOT_UNLUCKY(ENTRIES...) "unlucky" = list(ENTRIES)
/// Percent chance of the uncommon tier, and its entries.
#define LOOT_UNCOMMON(CHANCE, ENTRIES...) "uncommon_chance" = CHANCE, "uncommon" = list(ENTRIES)
/// Percent chance of the rare tier (rolled after uncommon misses), and its entries.
#define LOOT_RARE(CHANCE, ENTRIES...) "rare_chance" = CHANCE, "rare" = list(ENTRIES)
/// Percent chance of drawing a unique item from GLOB.unique_gamma_loot (after rare misses).
#define LOOT_GAMMA(CHANCE) "gamma_chance" = CHANCE
/// The source can be searched LEFT times in total (by different searchers); DELETE: qdel it then.
#define LOOT_DEPLETION(LEFT, DELETE) "loot_left" = LEFT, "delete_on_depletion" = DELETE
/// The same searcher may search again (debugging).
#define LOOT_REPEAT_SEARCH "repeat_search" = TRUE


/// Modulus of the loot seed hashes: h * 31 + 255 stays below 2^24, exact in BYOND's floats.
#define LOOT_HASH_MOD 524287

// Entry kinds of the loot and map-resolver declarations (code/library/loot/loot_entries.dm, code/library/maps/map_resolver_entry.dm).
#define ENTRY_LOOT "loot"
#define ENTRY_LOOT_SEARCH "loot_search"
