// Destruction as a framework transaction (roadmap L track, doc/rewrite/lifecycle.md).
// destroy_transaction() (code/datums/lifecycle/transaction.dm) runs these in
// order; SSgarbage accumulates per-phase timing on /datum/qdel_item for the
// "per-phase destroy time" test (doc §8) and for live diagnostics, the same
// way it already times Destroy() itself.
#define LIFECYCLE_PHASE_GUARD 1
#define LIFECYCLE_PHASE_MIND 2
#define LIFECYCLE_PHASE_UNBIND 3
#define LIFECYCLE_PHASE_DEMATERIALIZE 4
#define LIFECYCLE_PHASE_CONTENTS 5
#define LIFECYCLE_PHASE_LINKS 6
#define LIFECYCLE_PHASE_TEARDOWN 7
#define LIFECYCLE_PHASE_EFFECTS 8
#define LIFECYCLE_PHASE_DESTROY 9
#define LIFECYCLE_PHASE_SCRUB 10
#define LIFECYCLE_PHASE_COUNT 10

/// A human label for a LIFECYCLE_PHASE_* id, for logs and test output.
#define LIFECYCLE_PHASE_NAME(id) (list("guard", "mind", "unbind", "dematerialize", "contents", "links", "teardown", "effects", "destroy", "scrub")[id])

// ---- Declared references (L2, doc/rewrite/lifecycle.md §4) ----
// One line next to the type replaces a hand-written Destroy() body. Each adds
// to what the parent type declared (read once per type, links.dm).
// NAMES is one var name or a list() of them; PAIRS/LISTS are assoc lists.

/// Owned children, not contained: deleted in phase 4 (was QDEL_NULL in Destroy()).
#define REF_OWNED(PATH, NAMES) ##PATH/declared_owned_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Owned lists of children: each member deleted in phase 4 (was QDEL_LIST in Destroy()).
#define REF_OWNED_LIST(PATH, NAMES) ##PATH/declared_owned_list_vars() { . = ..(); . = (. || list()) + NAMES; }
/// One inserted thing (a beaker, a card) spilled to the drop location in phase 3.
#define REF_SPILL(PATH, NAMES) ##PATH/declared_spill_vars() { . = ..(); . = (. || list()) + NAMES; }
/// A thing held in contents with no policy of its own (an installed board): the
/// var is nulled if the thing is destroyed while inside.
#define REF_HELD(PATH, NAMES) ##PATH/declared_held_vars() { . = ..(); . = (. || list()) + NAMES; }
/// A list var's members spilled to the drop location in phase 3.
#define REF_SPILL_LIST(PATH, NAMES) ##PATH/declared_spill_list_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Owned assoc lists whose values are children: deleted in phase 4 (was QDEL_LIST_ASSOC_VAL).
#define REF_OWNED_VALUES(PATH, NAMES) ##PATH/declared_owned_value_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Pairs, our var -> the partner's var pointing back: nulled on both sides in phase 4.
#define REF_PAIR(PATH, PAIRS) ##PATH/declared_pair_vars() { return lifecycle_merge_assoc(..(), PAIRS); }
/// Back-lists, our var (the owner) -> the owner's list var we sit in: removed in phase 4.
#define REF_BACKLIST(PATH, LISTS) ##PATH/declared_backlist_vars() { return lifecycle_merge_assoc(..(), LISTS); }
/// Membership in a partner's list, where our var names the partner by OM handle:
/// list("our_handle_var" = "their_list_var"), or a list of their list vars. Phase 4 removes us (or our handle) from it.
#define REF_BACKLIST_HANDLE(PATH, LISTS) ##PATH/declared_backlist_handle_vars() { return lifecycle_merge_assoc(..(), LISTS); }
/// A partner we name by OM handle whose var names us back (by reference or handle):
/// list("our_handle_var" = "their_var"). Phase 4 nulls their var if it still names us.
#define REF_BACK_HANDLE(PATH, BACKS) ##PATH/declared_back_handle_vars() { return lifecycle_merge_assoc(..(), BACKS); }
/// A partner reached through a path of our vars, whose var(s) name us back:
/// list("path" = "their_var"). The path is one var or several joined by "."
/// ("master_handle.cl_handle"); each hop may hold a reference or an OM handle, and
/// the end may be a /client. The value is a var name, a list of them, or
/// list(/partner/type = name or names), applied only when the partner is that type
/// (list("loc" = list(/obj/machinery = "component_parts"))). Phase 4 removes us
/// (and our handle) from each named list var and nulls each other named var that
/// names us. Our own vars are untouched. Replaces `partner()?.their_var = null` and
/// `LAZYREMOVE(partner().list, src)` bodies where the partner isn't a plain var of ours.
#define REF_BACK_VIA(PATH, PATHS) ##PATH/declared_back_via_vars() { return lifecycle_merge_assoc(..(), PATHS); }
/// The owner side of a back-list: list("our_list" = "member_var"). Each member of our
/// list (keys and assoc values; references or OM handles) whose named var(s) name us
/// has them cleared as REF_BACK_VIA clears a partner's; the value takes the same
/// forms. Then our list is dropped. Replaces `for(x in list) x.back = null` bodies.
#define REF_LIST_BACK(PATH, LISTS) ##PATH/declared_list_back_vars() { return lifecycle_merge_assoc(..(), LISTS); }
/// Vars just dropped (nulled) in phase 4: the target is not deleted, cut or told.
/// For scratch tables keyed by other objects, and lists src was handed and may share
/// with its caller (cutting those would empty someone else's list).
#define REF_DROP(PATH, NAMES) ##PATH/declared_drop_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Membership in a global or subsystem list that isn't an OM registry (a work
/// queue): list("flag_var" = /proc/getter). When src.flag_var is true (or the key is
/// LIFECYCLE_QUEUE_ALWAYS) phase 4 removes src from the list the global proc returns
/// (null-safe; a list of getters is allowed). The flag keeps a big queue from being
/// scanned for objects that aren't in it.
#define REF_QUEUE_MEMBER(PATH, QUEUES) ##PATH/declared_queue_vars() { return lifecycle_merge_assoc(..(), QUEUES); }
/// REF_QUEUE_MEMBER key for a membership that holds for the object's whole life.
#define LIFECYCLE_QUEUE_ALWAYS "*"

/// Back-references, our var -> the var on the referenced object that points at
/// us (or null): the non-owning side of an owner/child pair. Phase 4 nulls
/// ours, and theirs if it still points at us. Ownership stays a tree: a child
/// names its owner with REF_BACK, never REF_OWNED (ownership_cycle_lint.py).
#define REF_BACK(PATH, BACKS) ##PATH/declared_back_vars() { return lifecycle_merge_assoc(..(), BACKS); }
/// Vars deliberately left set after destruction (a shared, immortal singleton;
/// an id the GC report reads). Exempt from the destroy postcondition
/// (dq_lifecycle_leak_lines(), code/datums/lifecycle/leak_check.dm).
#define REF_KEEP(PATH, NAMES) ##PATH/declared_keep_vars() { . = ..(); . = (. || list()) + NAMES; }

/// Declared destruction effects (phase 6): DATA is a `new /datum/destroy_effects_data(...)`
/// with named arguments, built once per type. Replaces message/sound/debris/
/// neighbour-smoothing bodies in Destroy().
#define DESTROY_EFFECTS(PATH, DATA) ##PATH/destroy_effects() { var/static/datum/destroy_effects_data/data = DATA; return data; }

/// References to frozen definitions and registry objects that are never deleted
/// (a /datum/material, a /datum/decl, a techweb node, an uplink category). The
/// lint accepts them and destruction does nothing with them: there is nothing to
/// clear, because the target outlives every holder. Vars whose declared type is in
/// DEF_TYPES (tools/ci/state_schema_lint.py) need no declaration at all.
#define REF_DEF(PATH, NAMES) ##PATH/declared_def_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Strong references to round-long singletons, services and flyweights (a subsystem,
/// a /datum/material, a seed, a tgui_state, a techweb). The var holds the object
/// itself -- never an om_handle() -- because the holder may be what keeps a
/// flyweight alive (a diverged seed, an engineered material). Destruction never
/// clears it and the leak check never reports it: the target outlives or is
/// shared by every holder, and a holder going away just drops one reference.
/// Ownership rule (doc/rewrite/object_model_core.md "Ownership"): every datum has
/// exactly one owner; handles are only for other live entities whose lifetime
/// something else manages. tools/ci/handle_kinds_lint.py refuses a handle var
/// whose target type is marked OM_STATIC_TYPE.
#define REF_STATIC(PATH, NAMES) ##PATH/declared_static_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Lists of other live entities the holder neither owns nor keeps alive (alarms a
/// console monitors, sensors on a grid, hearers of a sound, queued items). Members
/// are stored as OM handles, never references: add/remove/iterate only through
/// WEAK_LIST_ADD / WEAK_LIST_REMOVE / WEAK_LIST_HAS / weak_list_live(), which resolve
/// and prune dead entries. Destruction cuts the list (phase 4) without deleting members.
#define REF_WEAK_LIST(PATH, NAMES) ##PATH/declared_weak_list_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Adds live entity X to weak list L (lazily created); a no-op for null or a deleted X.
#define WEAK_LIST_ADD(L, X) do { var/__wl_h = om_handle(X); if(__wl_h) { LAZYOR(L, __wl_h); } } while(0)
/// Removes X from weak list L; works while X is being destroyed (om_handle_of()).
#define WEAK_LIST_REMOVE(L, X) LAZYREMOVE(L, om_handle_of(X))
/// TRUE if X is a live member of weak list L.
#define WEAK_LIST_HAS(L, X) (LAZYLEN(L) && (om_handle_of(X) in L))
/// Marks PATH (and its subtypes) as a singleton / flyweight / definition type:
/// instances are shared and live for the round, so references to them are
/// REF_STATIC (or read from the registry at the use site), never handles.
/// tools/ci/ref_kinds.py reads these lines; om_static_type() answers at runtime.
#define OM_STATIC_TYPE(PATH) ##PATH/om_static_type() { return TRUE; }

/// Fields of a pooled type (POOL_DECLARE) that belong to one use: pool_release()
/// resets each to its initial value before the object goes back to its pool, so a
/// forgotten clear can't leak a reference. Scalars may be listed too. The lint
/// accepts object-typed REF_TRANSIENT vars only on pooled types.
#define REF_TRANSIENT(PATH, NAMES) ##PATH/declared_transient_vars() { . = ..(); . = (. || list()) + NAMES; }

// ---- One-place declarations: the var and its kind together ----
// REF_VAR(/obj/machinery/foo, OWNED, /datum/bar, helper) declares
// `/obj/machinery/foo/var/datum/bar/helper` and adds "helper" to the type's
// REF_OWNED list. KIND is any single-name kind: OWNED, OWNED_LIST, OWNED_VALUES,
// SPILL, SPILL_LIST, HELD, DEF, STATIC, TRANSIENT, WEAK_LIST, DROP. VARTYPE is the full type path (/list
// for list kinds). The older REF_* forms keep working.
#define REF_VAR(PATH, KIND, VARTYPE, NAME) ##PATH { var##VARTYPE/##NAME; } REF_##KIND(PATH, #NAME)
/// REF_VAR for a pair: OTHER is the partner's var pointing back.
#define REF_PAIR_VAR(PATH, VARTYPE, NAME, OTHER) ##PATH { var##VARTYPE/##NAME; } REF_PAIR(PATH, list(#NAME = OTHER))
/// REF_VAR for a backlist: LIST_VAR is the owner's list var src sits in.
#define REF_BACKLIST_VAR(PATH, VARTYPE, NAME, LIST_VAR) ##PATH { var##VARTYPE/##NAME; } REF_BACKLIST(PATH, list(#NAME = LIST_VAR))

// ---- Object pools (code/datums/lifecycle/pool.dm, lifecycle.md §4.1) ----
/// /datum/var/pool_state values. Null: the datum is not pooled.
#define POOL_STATE_FREE 1
#define POOL_STATE_TAKEN 2
/// Released while poisoning was on: never handed out again, and every
/// POOL_ASSERT_LIVE on it crashes.
#define POOL_STATE_POISONED 3

/// Makes PATH a pooled type: take one with pool_take(PATH), give it back with
/// pool_release(obj) or obj.release(). Pooled objects refuse a normal qdel.
#define POOL_DECLARE(PATH) PATH/is_pooled() { return TRUE; }; PATH/proc/release() { pool_release(src); }; PATH/Destroy(force) { if(!force) { pool_refused_qdel(src); return QDEL_HINT_LETMELIVE; } return ..(); }

/// First line of a pooled type's procs: crashes when the object was released
/// (poisoned) or is sitting in the pool, catching use after release.
#define POOL_ASSERT_LIVE(D) if((D).pool_state != POOL_STATE_TAKEN) { pool_use_after_release(D); }

/// PATH refuses qdel() unless forced (singletons, registries, pooled objects):
/// the object is left untouched. See /datum/proc/lifecycle_keep().
#define LIFECYCLE_KEEP_UNLESS_FORCED(PATH) ##PATH/lifecycle_keep(force) { return !force; }
/// PATH refuses every qdel(), forced or not.
#define LIFECYCLE_KEEP_ALWAYS(PATH) ##PATH/lifecycle_keep(force) { return TRUE; }
