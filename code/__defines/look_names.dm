// Standard look names (doc/rewrite/dx_conventions.md §3). A sprite names its states by one convention:
//
//	<base>				the base state
//	<base>-<variant>	the base with a variant (look.variant()): "airlock-lit"
//	<base>-<part>		a part drawn for this sprite only (look.part()): "airlock-panel-open"
//	<part>				a part every sprite of the icon shares: "panel-open", "broken", "locked"
//	<part>-<value>		a part with a value (look.part("charge", 3)): "charge-3"
//	<part>-glow ... the emissive of a part is made by look.glow(part), never a separate state
//
// "_" and "-" are the same in a name when it is looked up (an old "panel_open" state resolves as
// "panel-open"); tools/dq_icons/rename_states.py renames the states themselves. Use these defines, not
// string literals, for a name more than one type draws.

#define LOOK_BROKEN "broken"
#define LOOK_COVER_OPEN "cover-open"
#define LOOK_PANEL_OPEN "panel-open"
#define LOOK_LOCKED "locked"
#define LOOK_DARK "dark"
#define LOOK_POWER "power"
#define LOOK_LID "lid"
#define LOOK_WIRES "wires"
#define LOOK_CELL "cell"
#define LOOK_BOLTS "bolts"
#define LOOK_WELDED "welded"
#define LOOK_EMERGENCY "emergency"
#define LOOK_LIT "lit"
#define LOOK_OPEN "open"
#define LOOK_CLOSED "closed"
#define LOOK_ON "on"
#define LOOK_OFF "off"
