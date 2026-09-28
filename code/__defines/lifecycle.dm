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
/// Fields of a pooled type (POOL_DECLARE) that belong to one use: pool_release()
/// resets each to its initial value before the object goes back to its pool, so a
/// forgotten clear can't leak a reference. Scalars may be listed too. The lint
/// accepts object-typed REF_TRANSIENT vars only on pooled types.
#define REF_TRANSIENT(PATH, NAMES) ##PATH/declared_transient_vars() { . = ..(); . = (. || list()) + NAMES; }

// ---- One-place declarations: the var and its kind together ----
// REF_VAR(/obj/machinery/foo, OWNED, /datum/bar, helper) declares
// `/obj/machinery/foo/var/datum/bar/helper` and adds "helper" to the type's
// REF_OWNED list. KIND is any single-name kind: OWNED, OWNED_LIST, OWNED_VALUES,
// SPILL, SPILL_LIST, HELD, DEF, TRANSIENT. VARTYPE is the full type path (/list
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
#define POOL_DECLARE(PATH) ##PATH { is_pooled() { return TRUE; } proc/release() { pool_release(src); } Destroy(force) { if(!force) { pool_refused_qdel(src); return QDEL_HINT_LETMELIVE; } return ..(); } }

/// First line of a pooled type's procs: crashes when the object was released
/// (poisoned) or is sitting in the pool, catching use after release.
#define POOL_ASSERT_LIVE(D) if((D).pool_state != POOL_STATE_TAKEN) { pool_use_after_release(D); }
