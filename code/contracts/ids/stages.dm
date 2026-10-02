// Build stage and state-graph ids (doc/rewrite/final_api.html, section 12). STAGE_DEF(group, name) defines
// STAGE_<GROUP>_<NAME>, and the stage's text is MSG_DEF(stage/<group>/<name>, ...). Only the stages the contracts and the
// E0 proofs name are here; a content wave declares its own next to the graph that uses them.

// The door-assembly graph of section 12 (proof 9): a frame, wired, boarded or kit-fitted, finished.
#define STAGE_DOOR_FRAME 1
#define STAGE_DOOR_WIRED 2
#define STAGE_DOOR_BOARDED 3
#define STAGE_DOOR_FINISHED 4
#define GRAPH_DOOR_ASSEMBLY 1

STAGE_DEF(door, frame, STAGE_DOOR_FRAME)
STAGE_DEF(door, wired, STAGE_DOOR_WIRED)
STAGE_DEF(door, boarded, STAGE_DOOR_BOARDED)
STAGE_DEF(door, finished, STAGE_DOOR_FINISHED)


