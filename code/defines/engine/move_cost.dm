// MOVE_COST: what one step of a player's mob costs, split by where the time goes (code/domains/world_model/atom/move_cost.dm).
//
// A step is measured whenever a client moves its mob (client/Move()): the parts below are accumulated while GLOB.move_cost_on is set and
// logged as one MOVE_COST line for every MOVE_COST_SAMPLE_EVERYth step and for every step over MOVE_COST_SLOW_MS.

/// One step in this many by a client is traced even when it was cheap.
#define MOVE_COST_SAMPLE_EVERY 50
/// A step that takes this long (ms) is traced whatever the sampling says.
#define MOVE_COST_SLOW_MS 12
/// Trace lines are written together this often, and at most this many wait.
#define MOVE_COST_FLUSH_EVERY (10 SECONDS)
#define MOVE_COST_LINES_MAX 40

/// The parts of a step (indexes into GLOB.move_cost_parts), and their names in the trace line.
#define MOVE_COST_MOVE 1 // atom/movable/Move() up to Moved(): the Exit/Enter/Crossed/Uncrossed handlers and the pre_move action
#define MOVE_COST_MOVED 2 // the whole Moved() chain (every override), of which the next five are inside atom/movable and mob Moved()
#define MOVE_COST_LIGHTS 3 // the light sources riding on the mover told to update
#define MOVE_COST_PROXIMITY 4 // SSproximity.member_update()
#define MOVE_COST_LIFEFORM 5 // lifeform_moved(): registries and adjacency
#define MOVE_COST_MOB_PUBLISH 6 // publish_mob_move(): the mob chunk watches
#define MOVE_COST_EYE 7 // restore_remote_views() and SSproximity.eye_update(): the client's chunk interest, the glow holder
// Pieces of the Moved() chain that no part above covers, so "other overrides" in the trace names what is left (a live round's trace showed 4-22 ms there).
#define MOVE_COST_NOTICES 8 // atom/movable/Moved(): the light-blocking update, the move notice and the observed-loc change
#define MOVE_COST_INTEREST 9 // atom/movable/Moved(): interest_parked_moved() and interest_anchor_moved()
#define MOVE_COST_HEAT 10 // atom/movable/Moved(): heat_recouple() and heat_followers_moved()
#define MOVE_COST_LIVING 11 // mob/living/Moved() after its parent: the loc change publish, the air watch, footsteps, the pulled thing, inertia, layer
#define MOVE_COST_BODY 12 // carbon and human Moved() after their parents: nutrition, germs, embedded objects, pose
#define MOVE_COST_FOLLOW 13 // mob/Moved() overrides after their parents: ghosts following, the cult net, blob chunk events
#define MOVE_COST_LOC_READS 14 // loc_changed(): own_field_changed(), the stat layer and derived entries that read `loc`
#define MOVE_COST_LOC_DRAW 15 // loc_changed(): tracked_changed() for a draw that reads `loc`
#define MOVE_COST_HOPS 16 // loc_changed(): hop_moved(), the turf and area hops
#define MOVE_COST_PART_COUNT 16

/// Starts timing a part: the tick usage now while a client's step is being measured, else 0.
#define MOVE_COST_BEGIN(started) var/started = GLOB.move_cost_on ? TICK_USAGE_REAL : 0
/// Adds the time since `started` (from MOVE_COST_BEGIN) to part `slot` of the step being measured.
#define MOVE_COST_END(slot, started) if(started) { GLOB.move_cost_parts[slot] += TICK_USAGE_REAL - started; }
