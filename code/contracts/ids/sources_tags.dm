// Flyweight sources and tags (doc/rewrite/final_api.html, sections 5 and 9). SOURCE_DEF(name) declares a flyweight source: no instance, no
// strings; `analyze gen declare_ids` writes SRC_<NAME>. SRC_STATUS: calls without source = use it (the ~700 existing status callers share one hold
// per status); SRC_VV: the admin's edit of a var in VV; SRC_AI_CONTROL: a bolt held through the AI's interface; SRC_HELD_ITEM: "the item owns it
// while it is in that hand or slot"; SRC_ALL: a wildcard release() and status_end() accept.


SOURCE_DEF(status)
SOURCE_DEF(vv)
SOURCE_DEF(ai_control)
SOURCE_DEF(held_item)
SOURCE_DEF(all)
/// A round event that holds a machine's state for good (an AI locked out of a door by a runtime): released by no one but an admin.
SOURCE_DEF(round_event)
/// The power grid's reading of a machine's area channel (set_powered()).
SOURCE_DEF(grid)
/// The machine's damage (atom_break() holds it, atom_fix() releases it).
SOURCE_DEF(damage)
/// A machine's maintenance state (an open service hatch).
SOURCE_DEF(maintenance)
/// A machine's own on/off switch.
SOURCE_DEF(switch)

/// Tags and capability ids share the numbers a bare id can be, so tags start at TAG_BASE and extend() tells the two apart.
#define TAG_BASE 1000
/// Every ui_act() op gets TAG_UI automatically.
#define TAG_UI 1001
/// Every topic() op gets TAG_TOPIC automatically.
#define TAG_TOPIC 1002
/// Ops that operate the thing (gated by a lock and by operability): extend(TAG_CONTROL, needs(...)).
#define TAG_CONTROL 1003
/// The ways into an occupant pod (occupant_pod(): a drag, a grab, "Move Inside"): extend(TAG_POD_ENTER, needs(...)) says what the machine asks of them all.
#define TAG_POD_ENTER 1004
