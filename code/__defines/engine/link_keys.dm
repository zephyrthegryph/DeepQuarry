// The keys of the sparse declared links (code/engine/declare/link_state.dm). A sparse end is not a var: it is written and read by its key through
// link_make() / link_get() / link_list(), and the typed accessors of its type (buckled_to(), pulling_target(), grab_target(), ...) wrap the reads.

/// A mob and the thing it is buckled to: LK_BUCKLED_TO on the mob (a /mob/living), LK_BUCKLED_MOBS on the seat (any /atom/movable, many).
#define LK_BUCKLED_TO "buckled_to"
#define LK_BUCKLED_MOBS "buckled_mobs"
/// A puller and what it pulls (any two /atom/movable: a mob, a wheelchair): LK_PULLING on the puller, LK_PULLED_BY on the pulled.
#define LK_PULLING "pulling"
#define LK_PULLED_BY "pulled_by"
/// A grab item and the mob it holds: LK_GRABBING on the grab, LK_GRABBED_BY on the mob (many: a mob can be held by several).
#define LK_GRABBING "grabbing"
#define LK_GRABBED_BY "grabbed_by"
