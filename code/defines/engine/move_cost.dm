// MOVE_COST: what one step of a player's mob costs, split by where the time goes (code/domains/world_model/atom/move_cost.dm).
//
// A step is measured whenever a client moves its mob (client/Move()): the parts below are accumulated while GLOB.move_cost_on is set and
// logged as one MOVE_COST line for every MOVE_COST_SAMPLE_EVERYth step and for every step over MOVE_COST_SLOW_MS.

/// One step in this many by a client is traced even when it was cheap.
#define MOVE_COST_SAMPLE_EVERY 50
/// A step that takes this long (ms) is traced whatever the sampling says.
#define MOVE_COST_SLOW_MS 4

/// The parts of a step (indexes into GLOB.move_cost_parts), and their names in the trace line.
#define MOVE_COST_MOVE 1 // atom/movable/Move() up to Moved(): the Exit/Enter/Crossed/Uncrossed handlers and the pre_move action
#define MOVE_COST_MOVED 2 // the whole Moved() chain (every override), of which the next five are inside atom/movable and mob Moved()
#define MOVE_COST_LIGHTS 3 // the light sources riding on the mover told to update
#define MOVE_COST_PROXIMITY 4 // SSproximity.member_update()
#define MOVE_COST_LIFEFORM 5 // lifeform_moved(): registries and adjacency
#define MOVE_COST_MOB_PUBLISH 6 // publish_mob_move(): the mob chunk watches
#define MOVE_COST_EYE 7 // restore_remote_views() and SSproximity.eye_update(): the client's chunk interest, the glow holder
#define MOVE_COST_PART_COUNT 7

/// Starts timing a part: the tick usage now while a client's step is being measured, else 0.
#define MOVE_COST_BEGIN(started) var/started = GLOB.move_cost_on ? TICK_USAGE_REAL : 0
/// Adds the time since `started` (from MOVE_COST_BEGIN) to part `slot` of the step being measured.
#define MOVE_COST_END(slot, started) if(started) { GLOB.move_cost_parts[slot] += TICK_USAGE_REAL - started; }
