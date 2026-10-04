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

/// The op tiers (section 8), highest first. OP_PRIORITY_* master values are kept; ATTACK is the one master lacks.
#ifndef OP_PRIORITY_ATTACK
#define OP_PRIORITY_ATTACK 20
#endif

/// Where an op's holder sits relative to the actor of the input: the target's own op, the held item's at_target op, the actor's own op.
#define CAND_TARGET 1
#define CAND_HELD 2
#define CAND_ACTOR 3

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
