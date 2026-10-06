// Interaction framework (doc/rewrite/interactions.md §5-8).
// Code: code/datums/interactions/.

/// The shared singleton of an interaction type, e.g. INTERACTION(/datum/interaction/machine_panel).
#define INTERACTION(path) (GLOB.interactions_by_type[path])
/// The shared singleton with this id.
#define INTERACTION_BY_ID(id) (interaction_by_id(id))

// What trying an action through the resolver did.
/// An interaction ran (or started and was interrupted; either way the input was used).
#define INTERACTION_TRY_RAN "ran"
/// Several interactions tied for the action, so the Menu opened.
#define INTERACTION_TRY_MENU "menu"
/// The interaction the player meant is blocked; they were told why.
#define INTERACTION_TRY_BLOCKED "blocked"

// Interaction tags, for filtering and actor adapters.
/// Can be done remotely (the AI, a cyborg interfacing without an item). Used by I3.
#define INTERACTION_TAG_REMOTE "remote"
/// Hostile: attacks and sabotage. Used by combat mode (I6).
#define INTERACTION_TAG_HOSTILE "hostile"
/// Observer-only: offered to ghosts and to no one else (I3).
#define INTERACTION_TAG_OBSERVER "observer"
/// Telekinesis-only: offered to a telekinetic reach and to no one else (I3).
#define INTERACTION_TAG_TELEKINESIS "telekinesis"
/// Silicon-only: offered to the AI and cyborgs and to no one else (I3).
#define INTERACTION_TAG_SILICON "silicon"
/// Part of the Maintainable behaviour (panel, anchor, deconstruct, repair).
#define INTERACTION_TAG_MAINTENANCE "maintenance"

/// The keybinding id of a category key.
#define INTERACTION_CATEGORY_BINDING(category) "category_[category]"
/// The keybinding id of the Menu key.
#define INTERACTION_MENU_BINDING "interaction_menu"

// What an atom's plain Use does for actors without hands (I3, `/atom/var/silicon_use`).
// These replace the attack_ai/attack_robot overrides that only forwarded; the
// adapters read them through the base attack_ai and attack_robot procs, so a
// type's own override still wins. tools/ci/actor_forwarding_lint.py enforces it.
/// The AI's Use (and a cyborg's remote interfacing) is the hand's Use: attack_hand.
#define SILICON_USE_HAND (1<<0)
/// The AI's Use opens the atom's tgui interface.
#define SILICON_USE_UI (1<<1)
/// A cyborg's empty-gripper Use is the hand's Use, at any range.
#define ROBOT_USE_HAND (1<<2)
/// A cyborg's empty-gripper Use is the hand's Use when adjacent, and does nothing otherwise.
#define ROBOT_USE_HAND_ADJACENT (1<<3)

// Legacy input entries (I7). A converted handler's interactions keep the entry
// point the old proc had, so every caller of that proc still reaches them, in
// the same order: the most specific type first, then its parents, as an
// override chain did. Resolver-native interactions have no entry.
/// Used with an item: /atom/proc/attackby.
#define INTERACTION_ENTRY_ITEM "item"
/// Touched with an empty hand (or a silicon's Use through silicon_use): /atom/proc/attack_hand.
#define INTERACTION_ENTRY_HAND "hand"
/// The held item used on itself: /obj/item/proc/attack_self.
#define INTERACTION_ENTRY_SELF "self"
/// Alt-click: /atom/proc/click_alt.
#define INTERACTION_ENTRY_ALT "alt"
/// Something dragged onto the target (held is the dragged atom): /atom/proc/MouseDrop_T.
#define INTERACTION_ENTRY_DRAG "drag"

/// An entry effect's return: it handled the input but didn't use it up, as an old handler that
/// returned nothing without calling ..(): attackby's afterattack and drag's defaults still follow.
#define INTERACTION_HANDLED_PASS "handled_pass"
/// run_interaction_entry()'s `result` also gets this when the answering effect returned INTERACTION_HANDLED_PASS.
#define INTERACTION_TRY_PASS "pass"
/// run_interaction_entry(): the entry's gate (hand_gate()) stopped the input before any interaction.
#define INTERACTION_GATE_STOPPED "gate_stopped"

/// Requirement: in reach. Adjacent, or a silicon the target lets use it remotely (silicon_use),
/// or already dispatched by the legacy entry (which decided reach itself: telekinesis, the AI).
#define REQ_INTERACTION_REACH REQ_PROC(/proc/dq_interaction_reach, "too far away")

/// Requirement: a held item's self-use. In hand; or already dispatched by attack_self(), whose
/// callers decided that themselves (a worn item's action button, an anchored item's touch).
#define REQ_SELF_USE_REACH REQ_PROC(/proc/dq_interaction_self_reach, "not in your hand")

/// use_tool() and pay_cost(): the job is a timed action that has started; its on_done runs later.
#define USE_TOOL_PENDING 2
/// Internal to /datum/interaction/proc/attempt(): no result yet.
#define INTERACTION_TRY_PENDING "pending"
// ---------------------------------------------------------------------------
// Compact interaction specs (doc/rewrite/interactions.md §5a; code/datums/interactions/compact.dm).
//
// A get_interactions() override returning list(INTERACT_USE(...), ...) in place of a
// declare_interactions() override plus a one-off /datum/interaction subtype.
// Each macro builds a plain data tuple: list(kind, name, effect, requires, extra).
// `effect` is a proc reference (PROC_REF(x), written inside the
// type that owns the proc) or the string form. `name` may be null to derive
// one from the proc's name ("insert_cell" -> "Insert cell"). `requires` is an
// extra P2 spec (REQ_* clauses) added on top of the shape's own; omit or pass
// null for none. dq_interaction_from_spec() (compact.dm) turns a spec into an
// interned /datum/interaction/generic singleton, shared by every type that
// declares the identical spec (e.g. an inherited proc reference).

/// Kind tags read by dq_interaction_from_spec() to pick the entry/category/default_action.
#define INTERACT_KIND_USE "use"
#define INTERACT_KIND_HAND "hand"
#define INTERACT_KIND_ITEM "item"
#define INTERACT_KIND_INSERT "insert"
#define INTERACT_KIND_ALT "alt"
#define INTERACT_KIND_HAND_UNGATED "hand_ungated"
#define INTERACT_KIND_DRAG "drag"
#define INTERACT_KIND_SELF "self"

/// Self-use (old attack_self): the held item used on itself. `effect(actor, held, interaction)`.
#define INTERACT_USE(name, effect, requires...) list(INTERACT_KIND_USE, name, effect, list(requires))
/// Self-use whose effect's return counts (old attack_self that fell through to its parent's with `return ..()`):
/// FALSE moves on to the next self-use candidate (an ancestor's). `effect(actor, held, interaction)`.
#define INTERACT_SELF(name, effect, requires...) list(INTERACT_KIND_SELF, name, effect, list(requires))
/// Touched with an empty hand, or a silicon's Use (old attack_hand). `effect(actor, held, interaction)`.
#define INTERACT_HAND(name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires))
/// Touched with an empty hand, ahead of the type's hand_gate() (old attack_hand that never called ..():
/// no signal, no unbuckling, no structure smash first). `effect(actor, held, interaction)`.
#define INTERACT_HAND_UNGATED(name, effect, requires...) list(INTERACT_KIND_HAND_UNGATED, name, effect, list(requires))
/// Something dragged onto the target (old MouseDrop_T). `effect(actor, dropped, interaction)`.
#define INTERACT_DRAG(name, effect, requires...) list(INTERACT_KIND_DRAG, name, effect, list(requires))
/// Used with any item (old attackby, no type check). `effect(actor, item, interaction)` returns
/// FALSE to fall through to the next candidate, as an old attackby fell through to ..().
#define INTERACT_ITEM(name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires))
/// Alt-click (old click_alt). `effect(actor, held, interaction)`.
#define INTERACT_ALT(name, effect, requires...) list(INTERACT_KIND_ALT, name, effect, list(requires))
/// Used with an item of `held_type` (old attackby with an istype(W, held_type) guard at the top).
/// name may be null to derive one ("Insert " + the item type's article+name).
#define INTERACT_INSERT(held_type, effect, name, requires...) list(INTERACT_KIND_INSERT, name, effect, list(requires), held_type)

/**
 * Declares a type's compact interaction specs: generates its get_interactions()
 * getter returning a proc-local `var/static/list` (allocated once, on first use; AGENTS.md §3a).
 * It is built lazily rather than in the static's initializer: every static initializer runs in
 * one world-init proc, which DM caps in size, and there are hundreds of these.
 *
 *   DECLARE_INTERACTIONS(/obj/item/binoculars, \
 *   	INTERACT_USE("Zoom", PROC_REF(zoom)), \
 *   	INTERACT_ALT(null, PROC_REF(eject)), \
 *   )
 *
 * A multi-line call needs a trailing backslash on each line (DM does not continue a
 * macro call across lines at its top paren depth). PROC_REF() inside the specs resolves against `T`, since the getter is defined on it.
 * Like any get_interactions() override it replaces an ancestor's specs; to add to
 * them, use EXTEND_INTERACTIONS below. tools/ci/interactions_lint.py fails on a
 * DECLARE_INTERACTIONS whose ancestor also declares, unless the site is annotated
 * with an interactions justified-keep annotation and a reason (a deliberate replacement).
 */
#define DECLARE_INTERACTIONS(T, specs...) ##T/get_interactions(){\
	var/static/list/dq_interaction_specs;\
	if(!dq_interaction_specs){\
		dq_interaction_specs = list(specs);\
	}\
	return dq_interaction_specs;\
}

/**
 * Like DECLARE_INTERACTIONS, but adds to the specs the type inherits instead of
 * replacing them: generates a declare_interactions() override that adds its own
 * specs first (most specific first, as an override chain ran) and then calls ..().
 * Use it on a subtype of a type that declares interactions of its own.
 */
#define EXTEND_INTERACTIONS(T, specs...) ##T/declare_interactions(list/into){\
	var/static/list/dq_interaction_specs;\
	if(!dq_interaction_specs){\
		dq_interaction_specs = list(specs);\
	}\
	for(var/dq_spec in dq_interaction_specs){\
		into += dq_interaction_from_spec(type, dq_spec);\
	}\
	..();\
}

// Stance-declared compact shapes (combat mode, doc/rewrite/interactions.md �12).
// Spec element 6 is the stance the interaction answers: I_HELP, I_DISARM, I_GRAB or
// I_HURT. The resolver offers it only when the actor's input has that stance, so
// the other stances fall through to the next candidate, and the interaction that
// runs carries the intent: its effect reads `interaction.stance`. Harm and disarm
// are hostile (INTERACTION_TAG_HOSTILE): the resolver ranks them by combat mode.
// Several stances sharing one effect proc are several declared interactions.
/// Self-use in `stance` (old attack_self branch on the stance). `effect(actor, held, interaction)`.
#define INTERACT_USE_AS(stance, name, effect, requires...) list(INTERACT_KIND_USE, name, effect, list(requires), null, stance)
/// Self-use in `stance` whose FALSE falls through (INTERACT_SELF).
#define INTERACT_SELF_AS(stance, name, effect, requires...) list(INTERACT_KIND_SELF, name, effect, list(requires), null, stance)
/// Touched with an empty hand in `stance`.
#define INTERACT_HAND_AS(stance, name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires), null, stance)
/// Touched with an empty hand in `stance`, ahead of hand_gate() (INTERACT_HAND_UNGATED).
#define INTERACT_HAND_UNGATED_AS(stance, name, effect, requires...) list(INTERACT_KIND_HAND_UNGATED, name, effect, list(requires), null, stance)
/// Used with any item in `stance`.
#define INTERACT_ITEM_AS(stance, name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires), null, stance)
/// Used with an item of `held_type` in `stance`.
#define INTERACT_INSERT_AS(stance, held_type, effect, name, requires...) list(INTERACT_KIND_INSERT, name, effect, list(requires), held_type, stance)
/// Something dragged onto the target in `stance`.
#define INTERACT_DRAG_AS(stance, name, effect, requires...) list(INTERACT_KIND_DRAG, name, effect, list(requires), null, stance)
/// Alt-click in `stance`.
#define INTERACT_ALT_AS(stance, name, effect, requires...) list(INTERACT_KIND_ALT, name, effect, list(requires), null, stance)
/// Used with any item, only in combat mode: INTERACT_ITEM_AS(I_HURT, ...).
#define INTERACT_ITEM_HOSTILE(name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires), null, I_HURT)
/// Used with any item, only with combat mode off: INTERACT_ITEM_AS(I_HELP, ...).
#define INTERACT_ITEM_PEACEFUL(name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires), null, I_HELP)
/// Used with an item of `held_type`, only in combat mode.
#define INTERACT_INSERT_HOSTILE(held_type, effect, name, requires...) list(INTERACT_KIND_INSERT, name, effect, list(requires), held_type, I_HURT)
/// Touched with an empty hand, only in combat mode.
#define INTERACT_HAND_HOSTILE(name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires), null, I_HURT)
/// Touched with an empty hand, only with combat mode off.
#define INTERACT_HAND_PEACEFUL(name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires), null, I_HELP)

// Default interactions: what a type does with an input when nothing more specific it
// offers takes it (an item's pickup, a mob being hit or touched). Spec element 7.
// They sort after every other interaction of the entry, whichever type declared them.
#define INTERACT_ORDER_DEFAULT "default"
/// Priority of a default interaction: below every ordinary one (0) and hostile shifts (-2 * COMBAT_MODE_PRIORITY_SHIFT).
/// One scale with the ops': a converted _DEFAULT shape is cap_op(priority = OP_PRIORITY_DEFAULT).
#define INTERACTION_DEFAULT_PRIORITY OP_PRIORITY_DEFAULT
/// Touched with an empty hand, when nothing else answers: the type's default touch (an item's pickup).
#define INTERACT_HAND_DEFAULT(name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires), null, null, INTERACT_ORDER_DEFAULT)
/// Used with any item, when nothing else takes it: the type's default (a mob is hit with it).
#define INTERACT_ITEM_DEFAULT(name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires), null, null, INTERACT_ORDER_DEFAULT)
/// The type's default touch in `stance` (a living mob's help, disarm, grab and punch).
#define INTERACT_HAND_DEFAULT_AS(stance, name, effect, requires...) list(INTERACT_KIND_HAND, name, effect, list(requires), null, stance, INTERACT_ORDER_DEFAULT)
/// The type's default for any item in `stance` (a living mob used on, disarmed, grabbed or hit with it).
#define INTERACT_ITEM_DEFAULT_AS(stance, name, effect, requires...) list(INTERACT_KIND_ITEM, name, effect, list(requires), null, stance, INTERACT_ORDER_DEFAULT)
/// Something dragged onto the target, when nothing else takes it (a movable's drag-buckle).
#define INTERACT_DRAG_DEFAULT(name, effect, requires...) list(INTERACT_KIND_DRAG, name, effect, list(requires), null, null, INTERACT_ORDER_DEFAULT)
/// Used with an item of `held_type`, when nothing else takes it.
#define INTERACT_INSERT_DEFAULT(held_type, effect, name, requires...) list(INTERACT_KIND_INSERT, name, effect, list(requires), held_type, null, INTERACT_ORDER_DEFAULT)

// Actor-kind shapes (I3). Resolver-native Use for one kind of actor, replacing the
// attack_ai / attack_robot / attack_ghost overrides. The actor's adapter decides reach.
#define INTERACT_KIND_SILICON "silicon"
#define INTERACT_KIND_ROBOT "robot"
#define INTERACT_KIND_OBSERVER "observer"
/// The AI's Use, and a cyborg's empty-gripper Use (old attack_ai). `effect(actor, held, interaction)`.
#define INTERACT_SILICON(name, effect, requires...) list(INTERACT_KIND_SILICON, name, effect, list(requires))
/// A cyborg's empty-gripper Use only (old attack_robot). List it before an INTERACT_SILICON it overrides.
#define INTERACT_ROBOT(name, effect, requires...) list(INTERACT_KIND_ROBOT, name, effect, list(requires))
#define INTERACT_KIND_TK "tk"
/// A telekinetic Use at range (old attack_tk). FALSE lets the default telekinetic grab happen.
#define INTERACT_TK(name, effect, requires...) list(INTERACT_KIND_TK, name, effect, list(requires))
/// A ghost's Use (old attack_ghost). `effect(actor, held, interaction)`.
#define INTERACT_OBSERVER(name, effect, requires...) list(INTERACT_KIND_OBSERVER, name, effect, list(requires))

// Object verbs as interactions (I7). A Menu entry with no key or click of its own: what an
// object verb (the right-click popup) did. Reach is the entry's usual (adjacent, or carried);
// add REQ_IN_INVENTORY for an old `set src in usr`.
#define INTERACT_KIND_VERB "verb"
/// An action chosen from the Menu (old object verb). `effect(actor, held, interaction)`.
#define INTERACT_VERB(name, effect, requires...) list(INTERACT_KIND_VERB, name, effect, list(requires))
/// Requirement: the target is on the actor (held, worn or in their bags), as an old `set src in usr`.
#define REQ_IN_INVENTORY REQ_PROC(/proc/dq_interaction_in_inventory, "you need to be carrying it")

/// A lowered datum interaction's offered_when clause (tools/codemods/interaction_datums.py) on a spec the op codemod has not converted yet:
/// the compact builder treats it as one more requirement.
#define OFFERED_WHEN(clause) clause
