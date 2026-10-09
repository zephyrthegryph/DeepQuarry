// Map-time resolvers (doc/rewrite/systems.md §9). Runtime: code/modules/maps/map_resolvers.dm.
//
// A map atom whose only job is to change something at load (a floor decal painted onto its
// turf, an /obj/random rolled into loot, a window spawner, a landmark that records a coordinate)
// declares a resolver instead of an Initialize() that ends in INITIALIZE_HINT_QDEL:
//
//   MAP_RESOLVER(/obj/effect/floor_decal, /proc/resolve_floor_decal)
//
// The resolver is `proc(atom/loc, path, list/varedits)`: loc is where the atom would be (the turf
// for map placement), path its type, varedits the map's var edits for this instance (null when
// none). It does the work and returns TRUE, or returns FALSE to have the atom made normally (a
// landmark that has to stay). Consulted by:
//   - the map reader (templates, expedition sites, anything load_map() places): before instancing,
//     so a resolved atom is never created;
//   - SSatoms.InitAtom() (the compiled station map, which BYOND instances itself, and `new` at
//     runtime): before Initialize, so the atom is never initialized nor qdel'd; it is detached and
//     BYOND frees it.
// Resolvers run inside map loading: they must not sleep.

/// PATH (and its subtypes) resolve at map time through PROC.
#define MAP_RESOLVER(PATH, PROC) ##PATH{map_resolver = PROC}

/// The vars (besides the common MAP_RESOLVER_COMMON_VARS) a family's resolver reads with MAP_VAR:
/// a ";"-separated string. Only these are captured as var edits from an existing instance (the
/// compiled map, runtime `new`); the map reader passes the model's edits as they are.
#define MAP_RESOLVER_VARS(PATH, NAMES) ##PATH{map_resolver_vars = NAMES}

/// Captured for every resolvable instance.
#define MAP_RESOLVER_COMMON_VARS "name;icon;icon_state;dir;color;alpha;pixel_x;pixel_y"

/// Var NAME of the resolved type P (a var typed as that type): the instance's map varedit when it
/// has one, else the type's default.
#define MAP_VAR(P, VAREDITS, NAME) ((VAREDITS && (#NAME in VAREDITS)) ? VAREDITS[#NAME] : initial(P.NAME))

/// Entry kind of the map_resolver(...) declaration (code/library/maps/map_resolver_entry.dm).
#define ENTRY_MAP_RESOLVER "map_resolver"
