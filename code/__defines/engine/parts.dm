// The part engine's constants (doc/rewrite/final_api.html, sections 8 and 9; section 19 "E2, parts").
// Entry kinds of E2, the stage bits a part acts in, binding kinds and the small vocabularies of an op's resolution.

/// An op: op(key, binding | inputs(...), parts...). Its children are the op's parts.
#define ENTRY_OP "op"
/// A part of an op (bindings, selects, requirements, waits, effects, feedback, metadata). The entry's type says which.
#define ENTRY_OP_PART "op_part"
/// What a capability or an item declares it can do for an actor: provides(AFF_X, reach =, line_of_sight =, authority =, accepts =).
#define ENTRY_PROVIDES "provides"
/// A canonical click order of a bundle: click_order(input, keys...) (plan.dm). Keys it names that a type lacks are skipped.
#define ENTRY_CLICK_ORDER "click_order"

// ---- Stages a part acts in (section 9). ----
#define PART_STAGE_NONE 0
#define PART_STAGE_MATCH (1<<0)
#define PART_STAGE_REQUIRE (1<<1)
#define PART_STAGE_WAIT (1<<2)
#define PART_STAGE_DO (1<<3)

/// An input binding's kind (hand(), tool(Q), ...). A text so explain output reads as the declaration does.
#define BIND_HAND "hand"
#define BIND_TOOL "tool"
#define BIND_ITEM "item"
#define BIND_STACK "stack"
#define BIND_IN_HAND "in_hand"
#define BIND_AT_TARGET "at_target"
#define BIND_INSIDE "inside"
#define BIND_REMOTE "remote"
#define BIND_MENU "menu"
#define BIND_UI "ui_act"
#define BIND_TOPIC "topic"
#define BIND_AI "ai"
/// The actor's own op, reached by the actor clicking something (a natural weapon): the op sits on the actor, and the clicked thing is its target.
#define BIND_CLICKS "clicks"
/// Telekinesis: the hand's touch of a target out of every hand's reach, done by the telekinesis provider (an old INTERACT_TK).
#define BIND_TK "tk"
/// An observer's click or menu pick (the old INTERACT_OBSERVER): only an actor that provides AFF_OBSERVE (a ghost, observer.dm) reaches it, anywhere.
#define BIND_OBSERVE "observe"

/// The op tiers (section 8), highest first. OP_PRIORITY_* master values are kept; ATTACK is the one master lacks.
#ifndef OP_PRIORITY_ATTACK
#define OP_PRIORITY_ATTACK 20
#endif

/// Where an op's holder sits relative to the actor of the input: the target's own op, the held item's at_target op, the actor's own op.
#define CAND_TARGET 1
#define CAND_HELD 2
#define CAND_ACTOR 3

/// The window action names the engine gives a meaning: ui_act("*") answers every window action no op names, `modal_open` is how a client opens a modal of its
/// window (the op's ui_act is "modal:<id>"), and the action that reached an op is A.args["window_action"] (A.window_action()).
#define OP_UI_ANY "*"
#define OP_UI_MODAL_OPEN "modal_open"
#define OP_UI_MODAL_PREFIX "modal:"
#define OP_UI_WINDOW_ACTION "window_action"
/// The datum whose window forwarded the button to the op's holder (interface(forwards =)): A.window_forwarder().
#define OP_UI_FORWARDED_BY "window_forwarded_by"
/// The tgui window a button was pressed in (A.window_ui()), when it came through one.
#define OP_UI_TGUI "window_tgui"
/// The raw href a topic op was reached by (A.topic_href()): its params are the op's args, and a re-run of an ask reads it.
#define OP_TOPIC_HREF "topic_href"
/// How many windows deep a window action is forwarded (interface(forwards = ...)).
#define OP_UI_FORWARD_DEPTH 3

/// The refusal reason an engine gate reports when no binding of an op accepts the origin it was given.
#define GATE_ORIGIN "origin"
#define GATE_PROVIDER "provider"
#define GATE_REACH "reach"
#define GATE_ACTOR "actor"
#define GATE_MATCH "match"

/// Rule names an op report carries (a test asserts on them).
#define RULE_OP_CLASH "op_clash"
#define RULE_OP_ORDER "op_order"
#define RULE_OP_PART "op_part"
#define RULE_OP_KEY "op_key"

/// What a part's combine rule is.
#define PART_ALL 1
#define PART_REPLACE 2
#define PART_APPEND 3
#define PART_MERGE 4


/// Wait keeps of an asks() default.
#define KEEPS_NONE 0

/// How long the engine shows the same gate refusal again to one actor.
#define GATE_FEEDBACK_INTERVAL (2 SECONDS)
/// How long a menu read may spend evaluating requirements (section 8, "Resolution cost").
#define MENU_EVAL_BUDGET (0.2 SECONDS)
/// TRUE while a condition, a requirement or an output is being evaluated (code/engine/parts/purity.dm).
#define OP_PURE_ACTIVE (GLOB.op_pure_depth > 0 || GLOB.derived_evaluating > 0)
/// The check every write, publication and message makes first: a violation is reported, never silently allowed (code/engine/parts/purity.dm).
#define OP_PURE_GUARD(what) if(OP_PURE_ACTIVE) { op_pure_violation(what) }
/// The keys a waiting op watches for its keeps: the entity moved, the hands of the actor changed (published by the movement and inventory paths).
#define OP_KEEP_MOVED "keep:moved"
#define OP_KEEP_HAND "keep:hand"
