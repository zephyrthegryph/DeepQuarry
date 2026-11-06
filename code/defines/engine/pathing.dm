// The search a /datum/io/path request runs (code/engine/io/path.dm). The value is the pathfinding type itself, so the engine builds it
// without naming a library type.

/// A*: exact, honours one-way turfs. The default, and what the combat AI's brain asks for.
#define PATH_ALGORITHM_ASTAR /datum/pathfinding/astar
/// JPS: faster on open floor, emits diagonals, cannot cross turfs that allow in one direction only. Bots ask for it.
#define PATH_ALGORITHM_JPS /datum/pathfinding/jps
