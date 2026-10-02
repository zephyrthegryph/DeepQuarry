// Build stage and state-graph ids (doc/rewrite/final_api.html, section 12). STAGE_DEF(group, name) declares
// STAGE_<GROUP>_<NAME> (`analyze gen declare_ids` writes the id), and the stage's text is MSG_DEF(stage/<group>/<name>, ...). Only the stages the contracts and the
// E0 proofs name are here; a content wave declares its own next to the graph that uses them.

// The door-assembly graph of section 12 (proof 9): a frame, wired, boarded or kit-fitted, finished.

STAGE_DEF(door, frame)
STAGE_DEF(door, wired)
STAGE_DEF(door, boarded)
STAGE_DEF(door, finished)


