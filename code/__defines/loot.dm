// One declared loot system (doc/rewrite/systems.md §8). Declarations: code/library/loot/loot_entries.dm. Runtime: code/datums/loot/loot.dm.
//
// A loot table is a loot(...) entry in the CAPABILITIES block of the type it describes (a pure table is an abstract /loot/... type); a subtype changes
// it with configure(loot(...)). Rolls are seeded: map-time rolls use GLOB.loot_seed ^ hash(x, y, z, type), so a round's map loot is reproducible from
// its seed; runtime rolls also mix a serial.

/// Modulus of the loot seed hashes: h * 31 + 255 stays below 2^24, exact in BYOND's floats.
#define LOOT_HASH_MOD 524287

/// The key the yields of a searcher without a ckey are counted under (code/library/loot/loot_search.dm).
#define LOOT_SEARCH_NO_KEY "(no key)"

// Entry kinds of the loot and map-resolver declarations (code/library/loot/loot_entries.dm, code/library/maps/map_resolver_entry.dm).
#define ENTRY_LOOT "loot"
#define ENTRY_LOOT_SEARCH "loot_search"
