// Map-time resolvers (doc/rewrite/systems.md §9). Declaration: code/library/maps/map_resolver_entry.dm. Runtime: code/modules/maps/map_resolvers.dm.
//
// A map atom whose only job is to change something at load declares map_resolver(GLOBAL_PROC_REF(x), vars = list(...)) in its CAPABILITIES block instead
// of an Initialize() that ends in INITIALIZE_HINT_QDEL. The resolver is `proc(atom/loc, path, list/varedits)`; MAP_VAR reads one of the map's var edits in it.

/// Captured for every resolvable instance.
#define MAP_RESOLVER_COMMON_VARS "name;icon;icon_state;dir;color;alpha;pixel_x;pixel_y"

/// Var NAME of the resolved type P (a var typed as that type): the instance's map varedit when it
/// has one, else the type's default.
#define MAP_VAR(P, VAREDITS, NAME) ((VAREDITS && (#NAME in VAREDITS)) ? VAREDITS[#NAME] : initial(P.NAME))

/// Entry kind of the map_resolver(...) declaration (code/library/maps/map_resolver_entry.dm).
#define ENTRY_MAP_RESOLVER "map_resolver"
