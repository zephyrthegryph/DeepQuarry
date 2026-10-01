// Construction ladders (doc/rewrite/dx_conventions.md §2). Runtime: code/datums/capabilities/construction.dm.

/// The step leaves the ladder: the holder becomes something else or is gone.
#define LADDER_DONE "done"
/// A branch leaving every stage (ladder_options(anywhere = ...)).
#define LADDER_ANY "*"

// What a step's cost does with the held item.
/// Only checked (a tool, or a cap_use_on() cost without uses).
#define LADDER_ITEM_KEEP 0
/// A stack's units are used (a cap_use_on() cost on a stack, with uses).
#define LADDER_ITEM_USE 1
/// The part is used up (a cap_use_on() cost on anything else, with uses).
#define LADDER_ITEM_DELETE 2
/// The part goes into the holder (a cap_insert() cost).
#define LADDER_ITEM_INSERT 3

// Cost kinds.
#define LADDER_COST_TOOL "tool"
#define LADDER_COST_USE "use"
#define LADDER_COST_INSERT "insert"
#define LADDER_COST_HOLD "hold"
#define LADDER_COST_HAND "hand"

// A cost spec (ladder_cost_spec()): a cost entry read into plain values when it is declared, so a
// stage or branch holds no entity (type_list rebuilds and interning drop declaration copies freely).
/// LADDER_COST_*, or null when the value given was not a cap_tool/cap_insert/cap_use_on/cap_hand entry.
#define LCOST_KIND 1
/// TOOL_* quality.
#define LCOST_TOOL 2
/// The held item type (or list of types).
#define LCOST_ITEM 3
/// Stack units (or 1 part) used up; what undoing gives back.
#define LCOST_USES 4
#define LCOST_DELAY 5
/// Welder fuel and the tool sound's volume.
#define LCOST_FUEL 6
#define LCOST_VOLUME 7
/// How reasons name the item (the entry's name).
#define LCOST_NAME 8
/// The entry's needs, as ladder_need() pairs.
#define LCOST_NEEDS 9
/// TRUE when the entry was given a handler (validate() reports it: the ladder is the handler).
#define LCOST_HANDLER 10
#define LCOST_LEN 10
