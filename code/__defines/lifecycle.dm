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
// Every object-typed var a datum holds is declared once, next to its type:
//
//     DECLARE_REF(/obj/machinery/foo, "board", HELD, null)
//     DECLARE_REF(/obj/item/part, "owner", BACK, "parts")
//
// VAR is the var name as a string (for BACK_VIA a "." path, for QUEUE a flag var
// or LIFECYCLE_QUEUE_ALWAYS). KIND is one of the REFKIND_* names below, written
// without the prefix. OPT is the kind's one argument (the partner's var for the
// two-sided kinds, a getter for QUEUE) or null. Each REF adds one entry to the
// type's declared_refs() table (links.dm), on top of what the parent type
// declared; dq_lifecycle_link_table() caches it per type.
#define DECLARE_REF(PATH, VAR, KIND, OPT) ##PATH/declared_refs() { return lifecycle_declare_ref(..(), REFKIND_##KIND, VAR, OPT); }

// The kinds. Each is the key of its entry list in the link table.
/// Owned child, not contained: deleted in phase 4 (was QDEL_NULL in Destroy()). OPT: null.
#define REFKIND_OWNED "owned"
/// Owned list of children: each member deleted in phase 4 (was QDEL_LIST). OPT: null.
#define REFKIND_OWNED_LIST "owned_list"
/// Owned assoc list whose values are children: deleted in phase 4 (was QDEL_LIST_ASSOC_VAL). OPT: null.
#define REFKIND_OWNED_VALUES "owned_values"
/// One inserted thing (a beaker, a card) spilled to the drop location in phase 3. OPT: null.
#define REFKIND_SPILL "spill"
/// A list var whose members spill to the drop location in phase 3. OPT: null.
#define REFKIND_SPILL_LIST "spill_list"
/// A thing held in contents with no policy of its own (an installed board): nulled if
/// the thing is destroyed while inside, and dropped with the holder. OPT: null.
#define REFKIND_HELD "held"
/// Two-sided pair, nulled on both sides in phase 4 (link_set()/link_clear()).
/// OPT: the partner's var pointing back.
#define REFKIND_PAIR "pair"
/// Membership in the owner's list: phase 4 removes src from it. OPT: the owner's list var.
#define REFKIND_BACKLIST "backlist"
/// Membership in a partner's list, where VAR names the partner by OM handle. OPT: the
/// partner's list var, a list of them, or list(/partner/type = name(s)).
#define REFKIND_BACKLIST_HANDLE "backlist_handle"
/// A partner named by OM handle whose var names us back (by reference or handle).
/// OPT: that var. Phase 4 nulls it if it still names us.
#define REFKIND_BACK_HANDLE "back_handle"
/// A partner reached through a path of our vars ("master_handle.cl_handle"; each hop a
/// reference or OM handle, the end may be a /client). OPT: the partner's var(s) naming us
/// -- a name, a list, or list(/partner/type = name(s)). Phase 4 removes us from each named
/// list and nulls each other named var that names us. Our own vars are untouched.
#define REFKIND_BACK_VIA "back_via"
/// The owner side of a back-list: each member of our list (keys and assoc values,
/// references or handles) stops naming us through OPT's var(s), then the list is dropped.
#define REFKIND_LIST_BACK "list_back"
/// Just dropped (nulled) in phase 4: not deleted, cut or told. For scratch tables keyed
/// by other objects and lists src was handed and may share. OPT: null.
#define REFKIND_DROP "drop"
/// Membership in a global or subsystem list that isn't an OM registry. VAR is a flag var
/// (or LIFECYCLE_QUEUE_ALWAYS); OPT is a global proc path, or a list of them, returning the
/// list. Phase 4 removes src from each list while the flag is set.
#define REFKIND_QUEUE "queue"
/// Non-owning side of an owner/child pair: phase 4 nulls ours, and theirs if it still
/// points at us. OPT: the owner's var pointing at us, or null. A child names its owner
/// with BACK, never OWNED (ownership_cycle_lint.py).
#define REFKIND_BACK "back"
/// Deliberately left set after destruction (an id the GC report reads). Exempt from the
/// destroy postcondition (leak_check.dm). OPT: null.
#define REFKIND_KEEP "keep"
/// A frozen definition or registry object that is never deleted (a /datum/decl, a
/// techweb node): nothing to clear. Vars typed in DEF_TYPES (state_schema_lint.py) need
/// no declaration at all. OPT: null.
#define REFKIND_DEF "def"
/// A strong reference to a round-long singleton, service or flyweight (a subsystem, a
/// /datum/material, a seed). Held as the object itself, never an om_handle(): the holder
/// may be what keeps a flyweight alive. Never cleared, never reported as a leak.
/// tools/ci/handle_kinds_lint.py refuses a handle to an OM_STATIC_TYPE. OPT: null.
#define REFKIND_STATIC "static"
/// A list of OM handles naming live entities the holder neither owns nor keeps alive.
/// Use WEAK_LIST_ADD / WEAK_LIST_REMOVE / WEAK_LIST_HAS / weak_list_live(). Phase 4 cuts
/// the list without deleting members. OPT: null.
#define REFKIND_WEAK_LIST "weak_list"
/// A pooled type's (POOL_DECLARE) per-use field: pool_release() resets it to its initial
/// value. Only valid on pooled types. OPT: null.
#define REFKIND_TRANSIENT "transient"

/// The VAR of a DECLARE_REF(PATH, VAR, QUEUE, getter) for a membership that holds for the object's whole life.
#define LIFECYCLE_QUEUE_ALWAYS "*"

/// Declared destruction effects (phase 6): DATA is a `new /datum/destroy_effects_data(...)`
/// with named arguments, built once per type. Replaces message/sound/debris/
/// neighbour-smoothing bodies in Destroy().
#define DESTROY_EFFECTS(PATH, DATA) ##PATH/destroy_effects() { var/static/datum/destroy_effects_data/data = DATA; return data; }

/// Adds live entity X to weak list L (lazily created); a no-op for null or a deleted X.
#define WEAK_LIST_ADD(L, X) do { var/__wl_h = om_handle(X); if(__wl_h) { LAZYOR(L, __wl_h); } } while(0)
/// Removes X from weak list L; works while X is being destroyed (om_handle_of()).
#define WEAK_LIST_REMOVE(L, X) LAZYREMOVE(L, om_handle_of(X))
/// TRUE if X is a live member of weak list L.
#define WEAK_LIST_HAS(L, X) (LAZYLEN(L) && (om_handle_of(X) in L))
/// Marks PATH (and its subtypes) as a singleton / flyweight / definition type:
/// instances are shared and live for the round, so references to them are
/// declared STATIC (or read from the registry at the use site), never handles.
/// tools/ci/ref_kinds.py reads these lines; om_static_type() answers at runtime.
#define OM_STATIC_TYPE(PATH) ##PATH/om_static_type() { return TRUE; }

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
