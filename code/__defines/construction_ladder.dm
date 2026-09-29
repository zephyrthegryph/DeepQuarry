// Construction ladders (doc/rewrite/dx_conventions.md §2). Runtime: code/datums/capabilities/construction.dm.

/// The step leaves the ladder: the holder becomes something else or is gone.
#define LADDER_DONE "done"
/// A branch leaving every stage (ladder_options(anywhere = ...)).
#define LADDER_ANY "*"

// What a step's cost does with the held item.
/// Only checked (a tool, or holding()).
#define LADDER_ITEM_KEEP 0
/// A stack's units are used (using() on a stack).
#define LADDER_ITEM_USE 1
/// The part is used up (using() on anything else).
#define LADDER_ITEM_DELETE 2
/// The part goes into the holder (inserting()).
#define LADDER_ITEM_INSERT 3

// Cost kinds.
#define LADDER_COST_TOOL "tool"
#define LADDER_COST_USE "use"
#define LADDER_COST_INSERT "insert"
#define LADDER_COST_HOLD "hold"
#define LADDER_COST_HAND "hand"
