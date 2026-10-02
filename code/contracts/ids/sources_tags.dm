// Flyweight sources and tags (doc/rewrite/final_api.html, sections 5 and 9). SOURCE_DEF(name, id) declares a flyweight source: no instance,
// no strings (code/__defines/engine/declare.dm; the id is the second argument until the generator derives SRC_<NAME> from the name).

/// Calls without source = use this one: the ~700 existing status callers share one hold per status.
#define SRC_STATUS 1
/// The admin's edit of a var in VV.
#define SRC_VV 2
/// An AI controller (a bolt held through the AI's interface).
#define SRC_AI_CONTROL 3
/// "The item owns it while it is in that hand or slot".
#define SRC_HELD_ITEM 4
/// Wildcard accepted by release() and status_end() only.
#define SRC_ALL 5

SOURCE_DEF(status, SRC_STATUS)
SOURCE_DEF(vv, SRC_VV)
SOURCE_DEF(ai_control, SRC_AI_CONTROL)
SOURCE_DEF(held_item, SRC_HELD_ITEM)
SOURCE_DEF(all, SRC_ALL)

/// Tags and capability ids share the numbers a bare id can be, so tags start at TAG_BASE and extend() tells the two apart.
#define TAG_BASE 1000
/// Every ui_act() op gets TAG_UI automatically.
#define TAG_UI 1001
/// Every topic() op gets TAG_TOPIC automatically.
#define TAG_TOPIC 1002
/// Ops that operate the thing (gated by a lock and by operability): extend(TAG_CONTROL, needs(...)).
#define TAG_CONTROL 1003
