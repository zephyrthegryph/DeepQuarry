// Declared UI model (doc/rewrite/systems.md section 3). Runtime: code/datums/sys/ui.dm.
//
//	DECLARE_UI(/obj/machinery/recharger, "Recharger", UI_STATE(GLOB.tgui_physical_state))
//	UI_DATA(/obj/machinery/recharger, "on", "proc:charge_percent", "slot:SLOT_CHARGING")
//	UI_ACT(/obj/machinery/recharger, "toggle", ui_toggle)
//	UI_ACT(/obj/machinery/recharger, "set_rate", ui_set_rate, UI_ARG_NUM("rate", 0, 100))
//	UI_ACT(/obj/machinery/recharger, "select", ui_select, UI_ARG_CHOICE("id", "valid_ids"))
//	UI_ACT_PROC(/obj/machinery/recharger, ui_set_rate)
//		rate = params["rate"]  // already a number in 0..100
//		return TRUE
//
// Every row lives on a marker type `/datum/ui_declared<host path>`, so rows inherit along the host
// hierarchy (a subtype row for the same action replaces its parent's) and the whole table is
// readable per type without an instance (ui_decl_of(), the -DUI_TYPES_DUMP boot).
// The generic /datum/tgui_interact() opens, reuses and binds the window from the DECLARE_UI row;
// the generic /datum/tgui_act() parses a message against its UI_ACT row and calls the handler as
//	proc(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action)
// where params holds only the declared args, typed and validated. The handler is not called when
// a present arg fails validation; an absent arg reads null.

/// Declares the host's tgui window: interface name plus options (UI_STATE, UI_TITLE, UI_AUTOUPDATE).
#define DECLARE_UI(PATH, INTERFACE, OPTS...) /datum/ui_declared##PATH/declaration() { return ui_declare(INTERFACE, list(OPTS)) }
/// Exported data fields: "var" (a var of the host), "proc:getter" (host proc taking
/// (mob/user, datum/tgui/ui, datum/tgui_state/state)), "slot:SLOT" (a slot fragment from
/// ui_slot_fragment(), the slot system's hook), "merge:getter{key:type,...}" (a getter returning
/// several computed keys at once). "key=" before a form names the data key; a ":type" suffix
/// (num, text, bool, list, any) types the field for the generated TS.
#define UI_DATA(PATH, FIELDS...) /datum/ui_declared##PATH/field_rows() { return ui_declare_fields(..(), list(FIELDS)) }
/// UI_DATA for a type whose fields replace its parents' instead of adding to them.
#define UI_DATA_REPLACE(PATH, FIELDS...) /datum/ui_declared##PATH/field_rows() { return ui_declare_fields(null, list(FIELDS)) }
/// One action row. PROC is the handler's bare name on PATH (checked at compile time).
#define UI_ACT(PATH, ACTION, PROC, ARGS...) /datum/ui_declared##PATH/act_rows() { return ui_declare_act(..(), ACTION, TYPE_PROC_REF(PATH, PROC), list(ARGS)) }
/// The row for any action no UI_ACT row names (a controller whose actions are data, a host passing
/// its window's actions on to the module it shows). The handler reads `action` and must check it.
#define UI_ACT_FALLBACK(PATH, PROC, ARGS...) /datum/ui_declared##PATH/act_rows() { return ui_declare_act(..(), UI_ACT_ANY, TYPE_PROC_REF(PATH, PROC), list(ARGS)) }
/// act_rows() key of the UI_ACT_FALLBACK row.
#define UI_ACT_ANY "*"
/// Actions no row of PATH names go on to other datums: PROC(mob/user, action) returns a datum or
/// a list of datums, whose own tgui_act() rows parse the message (a console showing its
/// occupant pod's panel, a PDA running an app, preferences and their middleware). The first
/// that handles it wins.
#define UI_ACT_FORWARD(PATH, PROC) /datum/ui_declared##PATH/act_rows() { return ui_declare_act(..(), UI_ACT_FORWARD_KEY, TYPE_PROC_REF(PATH, PROC), null) }
/// act_rows() key of the UI_ACT_FORWARD row.
#define UI_ACT_FORWARD_KEY "->"
/// The host's tgui state (who may see and use its window), when it is the same for every instance:
/// the base tgui_state() returns it. A state that depends on the instance stays a tgui_state()
/// override.
#define DECLARE_UI_STATE(PATH, STATE) /datum/ui_declared##PATH/state_row() { return STATE }
/// Extra channels that push the window, beyond the UI_DATA fields' own.
#define UI_WATCH(PATH, MASK) /datum/ui_declared##PATH/watch_mask() { return ..() | (MASK) }
/// A UI_ACT handler's header.
#define UI_ACT_PROC(PATH, PROC) PATH/proc/PROC(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action)
/// A nested action: an action whose message names a sub-action and carries its args (a vore belly's
/// "set_attribute" with the attribute and its value, a board game's "game_action"). The outer
/// UI_ACT handler calls ui_subdispatch(src, NS, sub_action, sub_params, user, ui, state, extra);
/// the row for (NS, ACTION) parses sub_params with its own ARGS, as UI_ACT does. Subaction rows
/// are never reachable as top-level actions.
#define UI_SUBACT(PATH, NS, ACTION, PROC, ARGS...) /datum/ui_declared##PATH/subact_rows() { return ui_declare_subact(..(), NS, ACTION, TYPE_PROC_REF(PATH, PROC), list(ARGS)) }
/// An action whose message names its sub-action in SUBKEY: the dispatcher itself routes it to the
/// host's UI_SUBACT row (NS, params[SUBKEY]), which parses the rest of the message with its own
/// args (a vore belly's "set_attribute", whose "val" is a different type per attribute). The host
/// may refuse with ui_nested_allowed() and follow up in ui_nested_done().
#define UI_ACT_NESTED(PATH, ACTION, NS, SUBKEY) /datum/ui_declared##PATH/act_rows() { return ui_declare_act(..(), ACTION, null, null, list(NS, SUBKEY)) }
/// A UI_SUBACT handler's header; `extra` is whatever the outer handler passes on.
#define UI_SUBACT_PROC(PATH, PROC) PATH/proc/PROC(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action, extra)
/// A subtype's override of an inherited subaction handler.
#define UI_SUBACT_OVERRIDE(PATH, PROC) PATH/PROC(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action, extra)
/// A preference editor's UI_ACT handler: editors take the character setup window's nested
/// "dq_editor_action" messages (see /datum/preference_editor/proc/handle_action()).
#define UI_ACT_PREF_PROC(PATH, PROC) PATH/proc/PROC(mob/user, list/params, datum/preferences/preferences, datum/tgui_state/state, action)
/// A subtype's override of an inherited handler (call ..() for the parent's).
#define UI_ACT_OVERRIDE(PATH, PROC) PATH/PROC(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action)

/// DECLARE_UI's interface read from a host var (each subtype sets its own), e.g.
/// DECLARE_UI(/datum/tgui_module, UI_FROM_VAR("tgui_id")).
#define UI_FROM_VAR(VARNAME) list("__var", VARNAME)

// DECLARE_UI options.
#define UI_STATE(STATE) list("state", STATE)
#define UI_TITLE(TITLE) list("title", TITLE)
#define UI_AUTOUPDATE list("autoupdate", TRUE)
/// Not closed by "close all windows" (dedicated skin elements: lobby, tooltip, media panel).
#define UI_PINNED list("pinned", TRUE)
/// ui_window() returns a window the host already initialized; open() doesn't initialize it again.
#define UI_PREINITIALIZED list("preinitialized", TRUE)

// Arg kinds (spec[1]); spec[2] is the param name.
#define UI_ARGK_NUM 1
#define UI_ARGK_INT 2
#define UI_ARGK_TEXT 3
#define UI_ARGK_BOOL 4
#define UI_ARGK_CHOICE 5
#define UI_ARGK_REF 6
#define UI_ARGK_PATH 7
#define UI_ARGK_LIST 8
#define UI_ARGK_VALUE 9

/// Default cap for UI_ARG_TEXT.
#define UI_TEXT_MAXLEN 4096

/// A number, clamped to [LO, HI] when given (UI_ARG_NUM("rate", 0, 100)).
#define UI_ARG_NUM(NAME, BOUNDS...) (list(UI_ARGK_NUM, NAME) + list(BOUNDS))
/// A whole number (rounded to nearest), clamped to [LO, HI] when given.
#define UI_ARG_INT(NAME, BOUNDS...) (list(UI_ARGK_INT, NAME) + list(BOUNDS))
/// Text, cut to MAXLEN (UI_TEXT_MAXLEN by default). A number is rendered as text.
#define UI_ARG_TEXT(NAME, MAXLEN...) (list(UI_ARGK_TEXT, NAME) + list(MAXLEN))
/// TRUE / FALSE (numbers by truth, text "0" / "false" / "" as FALSE).
#define UI_ARG_BOOL(NAME) list(UI_ARGK_BOOL, NAME)
/// A value that must be in SOURCE (a list, a host var name, "proc:x" or "glob:x"; see ui_arg_source()).
#define UI_ARG_CHOICE(NAME, SOURCE) list(UI_ARGK_CHOICE, NAME, SOURCE)
/// A ref: locate(ref) in SOURCE (null: anything locate() finds), optionally istype() one of TYPE.
#define UI_ARG_REF(NAME, SOURCE, TYPE...) (list(UI_ARGK_REF, NAME, SOURCE) + list(TYPE))
/// A type path (text2path), which must be BASE or a subtype of it.
#define UI_ARG_PATH(NAME, BASE) list(UI_ARGK_PATH, NAME, BASE)
/// A scalar the frontend sends as either a number or text (a keyword or an amount, a select's
/// value, an id): passed through as the client sent it, a number or text cut to MAXLEN; lists
/// and refs are rejected. Prefer NUM / TEXT whenever the frontend sends one kind.
#define UI_ARG_VALUE(NAME, MAXLEN...) (list(UI_ARGK_VALUE, NAME) + list(MAXLEN))
/// A list (a JSON array or object, or JSON text of one); its elements are the handler's to check.
#define UI_ARG_LIST(NAME) list(UI_ARGK_LIST, NAME)

// Field kinds.
#define UI_FIELD_VAR 1
#define UI_FIELD_PROC 2
#define UI_FIELD_SLOT 3
#define UI_FIELD_MERGE 4

