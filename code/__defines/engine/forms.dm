// Engine forms for state-owned behaviour and keyed standings (doc/rewrite/final_api.html: coalesce() in section 10 "After hooks", modes() in section 11
// "Modes", standing() in section 5 "Standings"; doc/rewrite/ai_packs.md part A).

/// coalesce(interval): a part of an on_notice() / on_change() entry. Many triggers inside the window give one run of the parts after it.
#define ENTRY_COALESCE "coalesce"
/// modes(nameof(var)): a type-level entry. A TRACKED var holds a capability type; the engine keeps that capability granted (source: the holder).
#define ENTRY_MODES "modes"
/// go(/datum/capability/x): a part that sets the mode of the holder (or of the state running the part).
#define ENTRY_GO "go"
/// after_in_state(delay, parts...): an entry of a state capability. A timer the activation owns; it ends with the state.
#define ENTRY_AFTER_IN_STATE "after_in_state"

/// Set to TRUE (VV, or a test) to log mode changes, coalesce windows and standing cache invalidations with log_world().
GLOBAL_VAR_INIT(forms_trace, FALSE)

// ---- standings (code/engine/stats/standings.dm) ----

/// A standing toward every mob a player controls.
#define STANDING_PLAYERS "standing:players"
/// A standing toward everything: the last fallback of standing_toward().
#define STANDING_ANY "standing:any"

/// The H_STAT of a standing row in the hold store (a text, so it can never equal the id of a declared stat).
#define HOLD_STANDING "standing"

// Standing values: a number, LOWER is MORE HOSTILE. Between two rows of the same priority the lower value wins (ties go to the most hostile).
#define STANDING_HOSTILE -100
#define STANDING_WARY -50
#define STANDING_NEUTRAL 0
#define STANDING_FRIENDLY 50
#define STANDING_ALLY 100

// ---- modes ----

/// Transitions one modes() sync follows in a row (a state whose own activation goes on to another state); past it the chain is logged and stopped.
#define MODES_MAX_CHAIN 16
/// A compiled table with a modes() entry: the mode its var names is granted when the holder initializes (modes_init()).
#define ENGINE_HOOK_MODES (1<<8)
